import Foundation
import FoundationModelsExtras
import Synchronization

/// Owns every marketplace of a host: the source list, the cache on the disk,
/// and the layers that ``SkillsRegistry`` reads (marketplace.md §6.1, §6.2,
/// §7.3, and §7.6).
///
/// ``marketplaceLayers()`` reads only the cache, thus a registry is built with
/// no network work at all. ``start()`` then brings each git marketplace to its
/// remote head one time, and each install publishes
/// ``MarketplaceEvent/updated(id:from:to:)`` and one value on
/// ``layerUpdates``, which makes the registry rebuild its catalog.
///
/// ```swift
/// let store = MarketplaceStore(sources: [MarketplaceSource("github:acme/team-skills")])
/// let registry = SkillsRegistry(marketplaces: store, stack: stack, watch: true)
/// await store.start()
/// ```
///
/// This version serves git sources. A source that names a local folder gets an
/// advisory and no layer.
public actor MarketplaceStore: MarketplaceLayerProviding {
    /// The ref that a source with no branch, tag, or pin follows.
    private static let defaultRef = "HEAD"

    /// The suffix of the staged snapshot folder, before the install renames
    /// it. It is no commit, thus cleanup never reads it as a snapshot.
    private static let stagedSnapshotSuffix = ".tmp"

    /// One git source, with everything that the sync needs and that never
    /// changes.
    fileprivate struct PreparedSource: Sendable {
        /// The source, as the host wrote it.
        let source: MarketplaceSource

        /// The pre-fetch key: the alias, else the repository name.
        let key: String

        /// The normalized git URL of the remote.
        let url: String

        /// The branch or the tag to follow, or `nil` for the remote `HEAD`.
        let ref: String?

        /// The folder of this marketplace in the cache.
        let cache: MarketplaceCache
    }

    /// One marketplace as the store serves it now.
    private struct ServedMarketplace: Sendable {
        /// The layer that the registry reads.
        var layer: MarketplaceLayer

        /// The shared lock on the snapshot that `current` names, so that
        /// cleanup in another process keeps it (marketplace.md §7.6).
        var lease: SnapshotLease?
    }

    // MARK: - State

    /// The git sources, in list order. It is empty when the source list is
    /// refused.
    private let prepared: [PreparedSource]

    /// The cache directory that holds `state.json` and every marketplace
    /// folder.
    private let cacheDirectory: URL

    /// What the host lets the store do.
    private let policy: MarketplacePolicy

    /// The git transport that fetches.
    private let transport: any GitTransport

    /// The clock that the periodic check sleeps on, and that the fetch
    /// timeout measures with.
    ///
    /// The package names no interval and no timeout of its own: the clock
    /// runs only when the policy gives a value (marketplace.md §8.2 and
    /// decision 13). A store test gives a manual clock.
    private let clock: any Clock<Duration>

    /// The pass that runs now for each marketplace, by list index.
    ///
    /// A second request for a marketplace joins the pass that is already
    /// there, thus no second remote connection opens (marketplace.md §8.2).
    private var inFlight: [Int: InFlightPass] = [:]

    /// The id that the next pass gets. It tells a finished pass from the
    /// pass that followed it.
    private var nextPassID = 0

    /// The task of the periodic check, or `nil` when the policy gives no
    /// interval or when ``stop()`` ended it.
    private var intervalLoop: Task<Void, Never>?

    /// What the store serves now, one entry for each entry of ``prepared``.
    ///
    /// A `Mutex` and not actor state, because ``marketplaceLayers()`` is
    /// `nonisolated`: the registry reads the layers on its own thread, with no
    /// `await`.
    private let served: Mutex<[ServedMarketplace]>

    /// The findings about the source list itself. They never change.
    private let listDiagnostics: [MarketplaceDiagnostic]

    /// The findings of the last sync of each marketplace, one list for each
    /// entry of ``prepared``. A sync replaces its own list, thus repeated
    /// updates do not grow the findings.
    private let sourceDiagnostics: Mutex<[[MarketplaceDiagnostic]]>

    /// The subscribers of ``events``.
    private let eventSubscribers = EventBroadcaster<MarketplaceEvent>()

    /// The subscribers of ``layerUpdates``.
    private let updateSubscribers = EventBroadcaster<Void>()

    // MARK: - Making a store

    /// Creates a store over a source list.
    ///
    /// The initializer does no network work and no fetch. It reads the cache
    /// that is already on the disk, thus a registry that is built right after
    /// it holds whatever the last run installed (marketplace.md §7.5).
    ///
    /// The initializer runs ``MarketplaceIdentity`` over the pre-fetch keys.
    /// When a source has no usable key, or when two sources have the same key,
    /// the store refuses the whole list: it serves no layer, and
    /// ``diagnostics`` tells why.
    ///
    /// - Parameters:
    ///   - sources: The marketplaces, in list order. A later source wins over
    ///     an earlier one in the registry.
    ///   - cacheDirectory: The cache directory. The default is
    ///     ``cacheDirectory(environment:)`` of the process environment.
    ///   - policy: What the host lets the store do. The default is
    ///     `MarketplacePolicy()`.
    public init(
        sources: [MarketplaceSource],
        cacheDirectory: URL = MarketplaceStore.cacheDirectory(),
        policy: MarketplacePolicy = MarketplacePolicy()
    ) {
        self.init(
            sources: sources, cacheDirectory: cacheDirectory, policy: policy,
            transport: LibGit2Transport())
    }

    /// Creates a store over a source list and one git transport.
    ///
    /// A store test gives a counting transport here (marketplace.md §13).
    ///
    /// - Parameters:
    ///   - sources: The marketplaces, in list order.
    ///   - cacheDirectory: The cache directory.
    ///   - policy: What the host lets the store do.
    ///   - transport: The git transport that fetches.
    ///   - clock: The clock of the periodic check and of the fetch timeout.
    ///     The default is a `ContinuousClock`.
    internal init(
        sources: [MarketplaceSource], cacheDirectory: URL, policy: MarketplacePolicy,
        transport: any GitTransport, clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.clock = clock
        let identity = MarketplaceIdentity.validate(sources)
        let refused = identity.contains { $0.severity == .error }
        let preparation =
            refused ? Preparation() : Preparation(sources: sources, cacheDirectory: cacheDirectory)
        prepared = preparation.sources
        listDiagnostics = identity + preparation.diagnostics
        self.cacheDirectory = cacheDirectory
        self.policy = policy
        self.transport = transport
        sourceDiagnostics = Mutex(preparation.sources.map { _ in [] })
        served = Mutex(
            Self.servedFromCache(
                prepared: preparation.sources,
                state: (try? MarketplaceState.load(from: MarketplaceCache.stateFile(inCacheDirectory: cacheDirectory)))
                    ?? MarketplaceState()))
    }

    /// The cache directory that an environment names (marketplace.md §7.1).
    ///
    /// The value is `SKILLS_MARKETPLACE_CACHE` when it is set and not empty,
    /// else `~/.cache/skills/marketplaces`. The call is a pure function of the
    /// environment, thus a test gives its own.
    ///
    /// - Parameter environment: The environment to read. The default is the
    ///   environment of this process.
    /// - Returns: The cache directory.
    public static func cacheDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        MarketplaceCache.cacheDirectory(environment: environment)
    }

    // MARK: - What the registry reads

    /// Gives the marketplace layers, lowest precedence first.
    ///
    /// The root of each layer is the stable `<cache>/<folder>/current` path,
    /// thus it never changes; only the provenance of the layer does. The call
    /// does no network work and no fetch.
    ///
    /// - Returns: One layer for each git source, in list order.
    public nonisolated func marketplaceLayers() -> [MarketplaceLayer] {
        served.withLock { $0.map(\.layer) }
    }

    /// One value for each time the layers changed, for the registry.
    ///
    /// Each access registers a subscription of its own, thus two readers each
    /// see every value.
    public nonisolated var layerUpdates: AsyncStream<Void> {
        updateSubscribers.subscribe()
    }

    /// What the store did with each marketplace (marketplace.md §6.2).
    ///
    /// Each access registers a subscription of its own, thus two readers each
    /// see every event. A host takes the stream before it calls ``start()``.
    public nonisolated var events: AsyncStream<MarketplaceEvent> {
        eventSubscribers.subscribe()
    }

    /// The findings about the source list and about the last sync of each
    /// marketplace.
    ///
    /// No message holds a credential.
    public nonisolated var diagnostics: [MarketplaceDiagnostic] {
        listDiagnostics + sourceDiagnostics.withLock { $0.flatMap { $0 } }
    }

    // MARK: - Syncing

    /// One pass over a marketplace, as the policy resolved it.
    private enum PassKind: Equatable {
        /// Read the remote head and report it. The pass fetches nothing.
        case check

        /// Read the remote head, and install it when it differs from the
        /// snapshot on the disk.
        ///
        /// - Parameter force: Whether to materialize again even with no
        ///   remote change.
        case update(force: Bool)

        /// Whether a pass that runs now also answers a new request.
        ///
        /// An update reads the remote head as a check does, thus it answers a
        /// check. A check installs nothing, thus it answers no update.
        ///
        /// - Parameter other: The pass that a caller asks for.
        /// - Returns: `true` when the caller waits for this pass.
        func answers(_ other: PassKind) -> Bool {
            switch other {
            case .check:
                return true
            case .update:
                return self == other
            }
        }
    }

    /// What one pass over a marketplace gave.
    private struct PassResult: Sendable {
        /// What the store now knows about the marketplace.
        let status: MarketplaceStatus

        /// The event for the caller, or `nil` when nothing changed.
        /// ``MarketplaceEvent/checked(id:current:latest:)`` goes to the
        /// stream only.
        let event: MarketplaceEvent?
    }

    /// One pass that runs now, so that a second request joins it.
    private struct InFlightPass {
        /// The id that tells this pass from the next one of the same
        /// marketplace.
        let id: Int

        /// What the pass does.
        let kind: PassKind

        /// The task of the pass.
        let task: Task<PassResult, Never>
    }

    /// Checks every git marketplace one time, installs what the policy lets
    /// it install, and starts the periodic check of the host
    /// (marketplace.md §7.5, §8.2, and §8.3).
    ///
    /// With the default policy the call fetches, materializes, and swaps
    /// `current` for each source whose remote head differs from the snapshot
    /// on the disk. A source that is already at its head does no fetch. With
    /// the automatic update off, or with a dry-run policy, the call publishes
    /// ``MarketplaceEvent/updateAvailable(id:from:to:)`` and fetches nothing.
    ///
    /// The periodic check runs only when the policy gives a
    /// ``MarketplacePolicy/checkInterval``. Without one, the store makes no
    /// later call until a request comes.
    public func start() async {
        await runPassOverEverySource()
        startIntervalLoop()
    }

    /// Ends the periodic check and every fetch that runs now
    /// (marketplace.md §8.2).
    ///
    /// The snapshot that `current` names does not change: a cancelled fetch
    /// is a failure, and a failure keeps the last good snapshot.
    public func stop() {
        intervalLoop?.cancel()
        intervalLoop = nil
        for pass in inFlight.values {
            pass.task.cancel()
        }
    }

    /// Reads the remote head of every git marketplace, and downloads no
    /// content (marketplace.md §8.1).
    ///
    /// The call publishes ``MarketplaceEvent/checked(id:current:latest:)``
    /// for each marketplace, and
    /// ``MarketplaceEvent/updateAvailable(id:from:to:)`` for each one whose
    /// head differs from its snapshot. A pass that already runs for a
    /// marketplace answers this call too, thus two concurrent calls open one
    /// remote connection.
    ///
    /// - Returns: One status for each git source, in list order.
    public func check() async -> [MarketplaceStatus] {
        var statuses: [MarketplaceStatus] = []
        for index in prepared.indices {
            statuses.append(await result(of: .check, atIndex: index).status)
        }
        return statuses
    }

    /// Brings one marketplace, or every marketplace, to its remote head.
    ///
    /// With ``MarketplacePolicy/checkOnly`` the call is a dry run: it reads
    /// the remote head, reports it, and fetches nothing (marketplace.md
    /// §8.3).
    ///
    /// - Parameters:
    ///   - id: The pre-fetch key or the display id of one marketplace, or
    ///     `nil` for every marketplace. The default is `nil`.
    ///   - force: Whether to materialize again even when the remote head is
    ///     the snapshot that `current` names. The default is `false`.
    /// - Returns: One event for each marketplace that installed a snapshot,
    ///   reported an update of a dry run, or failed, in list order. A
    ///   marketplace that is already at its head gives no event.
    @discardableResult
    public func update(_ id: String? = nil, force: Bool = false) async -> [MarketplaceEvent] {
        var events: [MarketplaceEvent] = []
        for index in prepared.indices where names(index: index, id: id) {
            if let event = await result(of: .update(force: force), atIndex: index).event {
                events.append(event)
            }
        }
        return events
    }

    /// Runs the pass that the policy wants over every marketplace: an update
    /// when the automatic update is on, else a check (marketplace.md §8.3).
    private func runPassOverEverySource() async {
        let kind: PassKind = policy.autoUpdate ? .update(force: false) : .check
        for index in prepared.indices {
            _ = await result(of: kind, atIndex: index)
        }
    }

    /// Runs one pass over a marketplace, or joins the pass that already runs
    /// for it (marketplace.md §8.2).
    ///
    /// The wait needs no debounce time: a second request holds the task of
    /// the first, thus it opens no second remote connection.
    ///
    /// - Parameters:
    ///   - kind: The pass that the caller asks for.
    ///   - index: The marketplace.
    /// - Returns: What the pass gave.
    private func result(of kind: PassKind, atIndex index: Int) async -> PassResult {
        let wanted = resolved(kind)
        while let running = inFlight[index] {
            if running.kind.answers(wanted) {
                return await running.task.value
            }
            _ = await running.task.value
        }
        let id = nextPassID
        nextPassID += 1
        let task = Task<PassResult, Never> {
            let outcome = await self.runPass(wanted, atIndex: index)
            self.finishPass(id: id, atIndex: index)
            return outcome
        }
        inFlight[index] = InFlightPass(id: id, kind: wanted, task: task)
        return await task.value
    }

    /// The pass that the policy lets a request run.
    ///
    /// ``MarketplacePolicy/checkOnly`` is a dry run: an update request
    /// becomes a check, thus the store downloads no content
    /// (marketplace.md §8.3).
    ///
    /// - Parameter kind: The pass that the caller asks for.
    /// - Returns: The pass that runs.
    private func resolved(_ kind: PassKind) -> PassKind {
        policy.checkOnly ? .check : kind
    }

    /// Does the work of one pass.
    ///
    /// - Parameters:
    ///   - kind: What the pass does.
    ///   - index: The marketplace.
    /// - Returns: What the pass gave.
    private func runPass(_ kind: PassKind, atIndex index: Int) async -> PassResult {
        switch kind {
        case .check:
            return await checkHead(atIndex: index)
        case .update(let force):
            return await sync(atIndex: index, force: force)
        }
    }

    /// Takes one finished pass out of the table, so that the next request
    /// starts a pass of its own.
    ///
    /// - Parameters:
    ///   - id: The pass that finished.
    ///   - index: The marketplace.
    private func finishPass(id: Int, atIndex index: Int) {
        if inFlight[index]?.id == id {
            inFlight[index] = nil
        }
    }

    /// Reads the remote head of one marketplace and reports it, with no fetch
    /// (marketplace.md §8.1).
    ///
    /// - Parameter index: The marketplace to check.
    /// - Returns: The status, and
    ///   ``MarketplaceEvent/updateAvailable(id:from:to:)`` when the head
    ///   differs from the snapshot.
    private func checkHead(atIndex index: Int) async -> PassResult {
        let entry = prepared[index]
        let current = entry.cache.currentSha()
        do {
            let latest = try await remoteHead(of: entry)
            let identifier = displayID(atIndex: index)
            eventSubscribers.publish(.checked(id: identifier, current: current, latest: latest))
            let status = MarketplaceStatus(id: identifier, current: current, latest: latest)
            guard status.updateAvailable else {
                return PassResult(status: status, event: nil)
            }
            let event = MarketplaceEvent.updateAvailable(id: identifier, from: current, to: latest)
            eventSubscribers.publish(event)
            return PassResult(status: status, event: event)
        } catch {
            return failureResult(atIndex: index, error: error, current: current)
        }
    }

    /// Starts the periodic check, when the host gave an interval
    /// (marketplace.md §8.2 and decision 13).
    ///
    /// The package has no interval of its own: with no
    /// ``MarketplacePolicy/checkInterval``, the store makes no check after
    /// ``start()`` until a request comes. A second ``start()`` starts no
    /// second loop.
    private func startIntervalLoop() {
        guard let interval = policy.checkInterval, intervalLoop == nil else {
            return
        }
        let clock = self.clock
        intervalLoop = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: interval)
                } catch {
                    return
                }
                guard let self else {
                    return
                }
                await self.runPassOverEverySource()
            }
        }
    }

    /// Whether an id names one marketplace.
    ///
    /// - Parameters:
    ///   - index: The marketplace to test.
    ///   - id: The pre-fetch key or the display id, or `nil` for every
    ///     marketplace.
    /// - Returns: `true` when the store syncs this marketplace.
    private func names(index: Int, id: String?) -> Bool {
        guard let id else {
            return true
        }
        return id == prepared[index].key || id == displayID(atIndex: index)
    }

    /// Syncs one marketplace, and keeps the last good snapshot on a failure.
    ///
    /// The whole sync holds the exclusive writer lock of the marketplace
    /// folder, thus one writer works on that folder at a time, also across
    /// processes (marketplace.md §7.6).
    ///
    /// - Parameters:
    ///   - index: The marketplace to sync.
    ///   - force: Whether to materialize again even with no remote change.
    /// - Returns: The status, and the event of the sync when something
    ///   changed or the sync failed.
    private func sync(atIndex index: Int, force: Bool) async -> PassResult {
        let entry = prepared[index]
        let current = entry.cache.currentSha()
        do {
            try entry.cache.makeFolders()
            return try await entry.cache.withWriterLock {
                try await installHead(ofIndex: index, force: force)
            }
        } catch {
            return failureResult(atIndex: index, error: error, current: current)
        }
    }

    /// Fetches the head of one marketplace and installs it, when it differs
    /// from the snapshot on the disk (marketplace.md §7.3).
    ///
    /// The caller holds the writer lock and has made the folders.
    ///
    /// - Parameters:
    ///   - index: The marketplace to sync.
    ///   - force: Whether to materialize again even with no remote change.
    /// - Returns: The status, and ``MarketplaceEvent/updated(id:from:to:)``.
    ///   The event is `nil` when the remote head is already the snapshot that
    ///   `current` names.
    /// - Throws: ``GitTransportError``, ``MarketplaceTimeoutError``,
    ///   ``SnapshotError``, ``MarketplaceCacheError``, or the error of a file
    ///   read or write.
    private func installHead(ofIndex index: Int, force: Bool) async throws -> PassResult {
        let entry = prepared[index]
        let previous = entry.cache.currentSha()
        let head = try await remoteHead(of: entry)
        eventSubscribers.publish(
            .checked(id: displayID(atIndex: index), current: previous, latest: head))
        guard force || head != previous else {
            return PassResult(
                status: MarketplaceStatus(
                    id: displayID(atIndex: index), current: previous, latest: head),
                event: nil)
        }
        let fetched = try await fetch(entry: entry)
        let catalog = try materialize(entry: entry, commit: fetched)
        try entry.cache.installUnderWriterLock(
            snapshotAt: catalog.staged, sha: fetched, ref: entry.source.isPinned ? nil : entry.ref)
        let installedID = catalog.resolved.name ?? entry.key
        serve(atIndex: index, sha: fetched, displayID: installedID, catalogVersion: catalog.resolved.version)
        record(
            diagnostics: catalog.diagnostics + duplicateDisplayIDDiagnostics(installedID, atIndex: index),
            atIndex: index)
        try save(record: stateRecord(of: entry, sha: fetched, catalog: catalog.resolved, displayID: installedID),
            forFolder: entry.cache.folderName)
        let event = MarketplaceEvent.updated(id: installedID, from: previous, to: fetched)
        eventSubscribers.publish(event)
        updateSubscribers.publish(())
        return PassResult(
            status: MarketplaceStatus(id: installedID, current: fetched, latest: head), event: event)
    }

    /// Fetches the commit of one marketplace, and stops the fetch when it
    /// takes longer than the fetch timeout of the policy.
    ///
    /// The package has no timeout of its own: with no
    /// ``MarketplacePolicy/fetchTimeout`` the fetch runs until it ends, or
    /// until ``stop()`` cancels it (marketplace.md §5.1).
    ///
    /// - Parameter entry: The marketplace to fetch.
    /// - Returns: The 40-hex SHA of the fetched commit.
    /// - Throws: ``GitTransportError``, or ``MarketplaceTimeoutError`` when
    ///   the fetch took longer than the timeout.
    private func fetch(entry: PreparedSource) async throws -> String {
        let revision = entry.source.sha ?? entry.ref ?? Self.defaultRef
        let transport = self.transport
        let credentials = policy.credentials
        let repository = entry.cache.repositoryDirectory
        let url = entry.url
        guard let timeout = policy.fetchTimeout else {
            return try await transport.fetch(
                url: url, revision: revision, intoBareRepository: repository,
                credentials: credentials)
        }
        let clock = self.clock
        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                try await transport.fetch(
                    url: url, revision: revision, intoBareRepository: repository,
                    credentials: credentials)
            }
            group.addTask {
                try await clock.sleep(for: timeout)
                return nil
            }
            while let first = try await group.next() {
                group.cancelAll()
                guard let sha = first else {
                    throw MarketplaceTimeoutError()
                }
                return sha
            }
            throw GitTransportError.cancelled
        }
    }

    /// Reads the commit that one marketplace must hold.
    ///
    /// - Parameter entry: The marketplace.
    /// - Returns: The pinned commit, else the commit that the remote head
    ///   names.
    /// - Throws: ``GitTransportError``.
    private func remoteHead(of entry: PreparedSource) async throws -> String {
        if let pinned = entry.source.sha {
            return pinned
        }
        return try await transport.remoteHead(
            url: entry.url, ref: entry.ref ?? Self.defaultRef, credentials: policy.credentials)
    }

    /// What one materialize step made.
    private struct Materialized {
        /// The staged snapshot folder, which the install then moves.
        let staged: URL

        /// The selected skills of the commit.
        let resolved: ResolvedCatalog

        /// The findings of the resolve and of the write.
        let diagnostics: [MarketplaceDiagnostic]
    }

    /// Reads the catalog of one fetched commit and writes the selected skills
    /// into a staged folder (marketplace.md §7.3 steps 2 to 4).
    ///
    /// - Parameters:
    ///   - entry: The marketplace.
    ///   - commit: The fetched commit.
    /// - Returns: The staged folder, the selected skills, and the findings.
    /// - Throws: ``SnapshotError``, ``CatalogFileSourceError``, or the error
    ///   of a read or of a write.
    private func materialize(entry: PreparedSource, commit: String) throws -> Materialized {
        let source = try GitTreeFileSource(
            repositoryURL: entry.cache.repositoryDirectory, commit: commit, rootPath: entry.source.path)
        let resolved = CatalogResolver.resolve(from: source, selection: entry.source.select)
        let staged = entry.cache.snapshotsDirectory
            .appendingPathComponent(commit + Self.stagedSnapshotSuffix, isDirectory: true)
        // A staged folder that an interrupted sync left behind is not an error.
        try? FileManager.default.removeItem(at: staged)
        let report = try SnapshotWriter.write(
            catalog: resolved, from: source, to: staged, limits: policy.snapshotLimits)
        return Materialized(
            staged: staged, resolved: resolved, diagnostics: resolved.diagnostics + report.diagnostics)
    }

    /// Records a failed sync, and keeps the snapshot that `current` names
    /// (marketplace.md §7.5).
    ///
    /// The text of the event is the description of the error. No error of the
    /// transport, of the cache, or of the writer holds a credential.
    ///
    /// - Parameters:
    ///   - index: The marketplace that failed.
    ///   - error: Why the sync failed.
    /// - Returns: ``MarketplaceEvent/failed(id:error:keptVersion:)``.
    private func failure(atIndex index: Int, error: any Error) -> MarketplaceEvent {
        let id = displayID(atIndex: index)
        let text = Self.text(of: error)
        let event = MarketplaceEvent.failed(
            id: id, error: text, keptVersion: prepared[index].cache.currentSha())
        record(
            diagnostics: [
                MarketplaceDiagnostic(
                    severity: .error, marketplaceID: id,
                    message: "The marketplace is not updated: \(text) The store keeps the snapshot it has.")
            ],
            atIndex: index)
        eventSubscribers.publish(event)
        return event
    }

    /// Records a failed pass and gives what its caller reads.
    ///
    /// - Parameters:
    ///   - index: The marketplace that failed.
    ///   - error: Why the pass failed.
    ///   - current: The commit that `current` named before the pass.
    /// - Returns: The status of the failure, and
    ///   ``MarketplaceEvent/failed(id:error:keptVersion:)``.
    private func failureResult(atIndex index: Int, error: any Error, current: String?) -> PassResult {
        let event = failure(atIndex: index, error: error)
        return PassResult(
            status: MarketplaceStatus(
                id: displayID(atIndex: index), current: current, latest: nil,
                error: Self.text(of: error)),
            event: event)
    }

    /// The text of one error, for an event and for a diagnostic.
    ///
    /// No error of the transport, of the cache, or of the writer holds a
    /// credential.
    ///
    /// - Parameter error: The error of a pass.
    /// - Returns: The text.
    private static func text(of error: any Error) -> String {
        String(describing: error)
    }

    // MARK: - The served layers

    /// Replaces what the store serves for one marketplace, and takes a shared
    /// lock on the new snapshot.
    ///
    /// The lease of the snapshot before this one is released here, outside the
    /// lock, thus the next cleanup can delete that folder.
    ///
    /// - Parameters:
    ///   - index: The marketplace.
    ///   - sha: The commit of the new snapshot.
    ///   - displayID: The display id: the catalog `name`, else the pre-fetch
    ///     key.
    ///   - catalogVersion: The `version` field of the catalog, or `nil`.
    private func serve(atIndex index: Int, sha: String, displayID: String, catalogVersion: String?) {
        let entry = prepared[index]
        let lease = try? entry.cache.leaseCurrentSnapshot()
        let superseded = served.withLock { layers -> SnapshotLease? in
            layers[index].layer.provenance = MarketplaceProvenance(
                id: displayID, url: entry.source.url, sha: sha, catalogVersion: catalogVersion)
            let previous = layers[index].lease
            layers[index].lease = lease
            return previous
        }
        superseded?.releaseNow()
    }

    /// The display id of one marketplace.
    ///
    /// - Parameter index: The marketplace.
    /// - Returns: The catalog `name` of the snapshot it serves, else the
    ///   pre-fetch key.
    private func displayID(atIndex index: Int) -> String {
        served.withLock { $0[index].layer.provenance.id }
    }

    /// Makes one layer for each git source from what the cache already holds.
    ///
    /// Every source gets a layer, also before its first install: the root of a
    /// layer is a construction-time invariant of `SkillsRegistry`, thus the
    /// list must not grow when the first snapshot arrives.
    ///
    /// - Parameters:
    ///   - prepared: The git sources, in list order.
    ///   - state: The state file of the cache.
    /// - Returns: One served marketplace for each source, in list order.
    private static func servedFromCache(
        prepared: [PreparedSource], state: MarketplaceState
    ) -> [ServedMarketplace] {
        prepared.map { entry in
            let stored = state.marketplaces[entry.cache.folderName]
            let sha = entry.cache.currentSha()
            let layer = MarketplaceLayer(
                layer: DotfolderStack.Layer(source: .marketplace, root: entry.cache.currentLink),
                provenance: MarketplaceProvenance(
                    id: stored?.displayID ?? entry.key, url: entry.source.url, sha: sha,
                    catalogVersion: sha == nil ? nil : stored?.catalogVersion),
                grants: entry.source.grants)
            return ServedMarketplace(layer: layer, lease: try? entry.cache.leaseCurrentSnapshot())
        }
    }

    // MARK: - Diagnostics

    /// Replaces the findings of one marketplace.
    ///
    /// - Parameters:
    ///   - diagnostics: The findings of the sync that just ran.
    ///   - index: The marketplace.
    private func record(diagnostics: [MarketplaceDiagnostic], atIndex index: Int) {
        sourceDiagnostics.withLock { $0[index] = diagnostics }
    }

    /// Makes the finding for a display id that more than one marketplace uses
    /// (marketplace.md §5.3).
    ///
    /// Each source keeps its own layer and its own cache folder. Only the name
    /// that a row shows is the same, thus the finding is a warning.
    ///
    /// - Parameters:
    ///   - displayID: The display id that the marketplace now has.
    ///   - index: The marketplace that just synced.
    /// - Returns: One warning, or no finding when the id is unique.
    private func duplicateDisplayIDDiagnostics(
        _ displayID: String, atIndex index: Int
    ) -> [MarketplaceDiagnostic] {
        let others = served.withLock { layers in
            layers.indices.filter { $0 != index && layers[$0].layer.provenance.id == displayID }
        }
        guard !others.isEmpty else {
            return []
        }
        let urls = others.map { #""\#(prepared[$0].source.url)""# }.joined(separator: ", ")
        return [
            MarketplaceDiagnostic(
                severity: .warning, marketplaceID: displayID,
                message: #"""
                    More than one source gives the display id "\#(displayID)": this source and \#(urls). \
                    Each source keeps its own layer. Set a different alias to tell them apart.
                    """#)
        ]
    }

    // MARK: - The state file

    /// Makes the state record of one marketplace after an install.
    ///
    /// - Parameters:
    ///   - entry: The marketplace.
    ///   - sha: The commit of the new snapshot.
    ///   - catalog: The catalog of that commit.
    ///   - displayID: The display id of the marketplace.
    /// - Returns: The record to write.
    private func stateRecord(
        of entry: PreparedSource, sha: String, catalog: ResolvedCatalog, displayID: String
    ) -> MarketplaceStateRecord {
        let now = Date()
        return MarketplaceStateRecord(
            url: entry.source.url, ref: entry.ref, pinnedSha: entry.source.sha, currentSha: sha,
            catalogVersion: catalog.version, displayID: displayID, lastChecked: now, lastUpdated: now)
    }

    /// Writes the record of one marketplace into `state.json`.
    ///
    /// - Parameters:
    ///   - record: The record to write.
    ///   - folder: The cache folder name, which is the key of the record.
    /// - Throws: The error of the file read or of the file write.
    private func save(record: MarketplaceStateRecord, forFolder folder: String) throws {
        let file = MarketplaceCache.stateFile(inCacheDirectory: cacheDirectory)
        var state = (try? MarketplaceState.load(from: file)) ?? MarketplaceState()
        state.marketplaces[folder] = record
        try state.save(to: file)
    }
}

/// The git sources of one source list, and what the store could not prepare.
///
/// The work runs before `self` is whole, thus it lives outside the actor.
private struct Preparation {
    /// The git sources that the store serves, in list order.
    var sources: [MarketplaceStore.PreparedSource] = []

    /// One finding for each source that gets no layer.
    var diagnostics: [MarketplaceDiagnostic] = []

    /// The cache directory that every prepared source writes into.
    private let cacheDirectory: URL

    /// Prepares no source, for a list that the store refuses.
    init() {
        cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    /// Prepares every git source of a list.
    ///
    /// - Parameters:
    ///   - sources: The sources, in list order. Their pre-fetch keys are
    ///     already checked.
    ///   - cacheDirectory: The cache directory of the store.
    init(sources: [MarketplaceSource], cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        for source in sources {
            add(source: source)
        }
    }

    /// Prepares one source.
    ///
    /// - Parameter source: The source to prepare.
    private mutating func add(source: MarketplaceSource) {
        guard let key = try? MarketplaceIdentity.preFetchKey(for: source),
            let location = try? MarketplaceLocation(source: source)
        else {
            return
        }
        guard case .git(let url, let ref) = location else {
            diagnostics.append(
                MarketplaceDiagnostic(
                    severity: .advisory, marketplaceID: key,
                    message:
                        #"The source "\#(source.url)" names a local folder. This version serves git sources, thus the folder gets no layer."#
                ))
            return
        }
        sources.append(
            MarketplaceStore.PreparedSource(
                source: source, key: key, url: url, ref: source.isPinned ? source.ref : ref,
                cache: MarketplaceCache(
                    root: cacheDirectory,
                    folderName: MarketplaceIdentity.cacheFolderName(key: key, normalizedURL: url))))
    }
}
