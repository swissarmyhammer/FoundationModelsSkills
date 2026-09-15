import Foundation
import FoundationModelsExtras
import Synchronization

/// Owns every marketplace of a host: the source list, the cache on the disk,
/// and the layers that ``SkillsRegistry`` reads (marketplace.md §6.1, §6.2,
/// §7.3, and §7.6).
///
/// ``marketplaceLayers()`` reads only the disk, thus a registry is built with
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
/// Three kinds of source give a layer:
///
/// - A git source, which the store fetches into its cache.
/// - A `file://` source that names a folder and not a `.git` repository. The
///   folder is the layer itself: the store makes no copy, keeps no cache
///   entry, and fetches nothing. A `watch: true` registry watches that root as
///   it watches a local layer (marketplace.md §5.1 and §7.4).
/// - A git source that the read-only seed folder serves, when the cache holds
///   no snapshot of it. The store never writes the seed folder
///   (marketplace.md §7.5).
public actor MarketplaceStore: MarketplaceLayerProviding {
    /// The ref that a source with no branch, tag, or pin follows.
    private static let defaultRef = "HEAD"

    /// The folder of a local marketplace that holds its skill folders, for a
    /// source that names no `path` (marketplace.md §5.1).
    ///
    /// ``Preparation`` reads it, thus it is `fileprivate` and not `private`.
    fileprivate static let localSkillsFolderName = "skills"

    /// The suffix of the staged snapshot folder, before the install renames
    /// it. It is no commit, thus cleanup never reads it as a snapshot.
    private static let stagedSnapshotSuffix = ".tmp"

    /// The git remote of one marketplace, and the cache folder that holds its
    /// snapshots.
    fileprivate struct GitRemote: Sendable {
        /// The normalized git URL of the remote.
        let url: String

        /// The branch or the tag to follow, or `nil` for the remote `HEAD`.
        let ref: String?

        /// The folder of this marketplace in the cache.
        let cache: MarketplaceCache
    }

    /// Where the layer of one marketplace comes from.
    fileprivate enum PreparedKind: Sendable {
        /// A git remote. The store fetches it and installs its snapshots.
        case git(GitRemote)

        /// A folder on this computer, which is the layer root itself. The
        /// store makes no copy and keeps no cache entry (marketplace.md §5.1).
        case local(root: URL)

        /// A git source that the read-only seed folder serves, because the
        /// cache holds no snapshot of it. The store never updates such a
        /// marketplace (marketplace.md §7.5).
        case seed(GitRemote, seed: MarketplaceCache)
    }

    /// One source, with everything that a pass needs and that never changes.
    fileprivate struct PreparedSource: Sendable {
        /// The source, as the host wrote it.
        let source: MarketplaceSource

        /// The pre-fetch key: the alias, else the repository name.
        let key: String

        /// Where the layer of this source comes from.
        let kind: PreparedKind

        /// The cache folder that serves the layer of this source, or `nil` for
        /// a local folder, which is its own layer root.
        var servingCache: MarketplaceCache? {
            switch kind {
            case .git(let remote): remote.cache
            case .seed(_, let seed): seed
            case .local: nil
            }
        }
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

    /// The sources that give a layer, in list order. It is empty when the
    /// source list is refused.
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

    /// The findings of the last pass over each marketplace, one list for each
    /// entry of ``prepared``. A pass replaces its own list, thus repeated
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
            transport: LibGit2Transport(), environment: ProcessInfo.processInfo.environment)
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
    ///   - environment: The environment that names the read-only seed folder
    ///     (marketplace.md §7.5). The default is no variable at all.
    internal init(
        sources: [MarketplaceSource], cacheDirectory: URL, policy: MarketplacePolicy,
        transport: any GitTransport, clock: any Clock<Duration> = ContinuousClock(),
        environment: [String: String] = [:]
    ) {
        self.clock = clock
        let seedDirectory = MarketplaceCache.seedDirectory(environment: environment)
        let identity = MarketplaceIdentity.validate(sources)
        let refused = identity.contains { $0.severity == .error }
        let preparation =
            refused
            ? Preparation()
            : Preparation(
                sources: sources, cacheDirectory: cacheDirectory, policy: policy,
                seedDirectory: seedDirectory)
        prepared = preparation.sources
        listDiagnostics = identity + preparation.diagnostics
        self.cacheDirectory = cacheDirectory
        self.policy = policy
        self.transport = transport
        sourceDiagnostics = Mutex(preparation.sources.map { _ in [] })
        served = Mutex(
            Self.servedFromDisk(
                prepared: preparation.sources, state: Self.state(inDirectory: cacheDirectory),
                seedState: seedDirectory.map(Self.state(inDirectory:)) ?? MarketplaceState()))
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

    /// Reads the state file of one cache directory.
    ///
    /// - Parameter directory: The cache directory, or the seed folder, which
    ///   has the same layout.
    /// - Returns: The state, or an empty state when there is no file.
    private static func state(inDirectory directory: URL) -> MarketplaceState {
        (try? MarketplaceState.load(from: MarketplaceCache.stateFile(inCacheDirectory: directory)))
            ?? MarketplaceState()
    }

    // MARK: - What the registry reads

    /// Gives the marketplace layers, lowest precedence first.
    ///
    /// The root of a git layer is the stable `<cache>/<folder>/current` path,
    /// and the root of a local layer is the folder of the source itself. Thus
    /// a root never changes; only the provenance of the layer does. The call
    /// does no network work and no fetch.
    ///
    /// - Returns: One layer for each source that gives one, in list order.
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

    /// The findings about the source list and about the last pass over each
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
    /// A local folder and a seed entry need no network at all.
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
    /// - Returns: One status for each source, in list order. A local folder
    ///   has no remote, thus its status names no commit.
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
    /// §8.3). A local folder needs no update, and a marketplace that the seed
    /// folder serves is never updated (marketplace.md §7.5).
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

    /// Does the work of one pass, as the kind of the source needs it.
    ///
    /// - Parameters:
    ///   - kind: What the pass does.
    ///   - index: The marketplace.
    /// - Returns: What the pass gave.
    private func runPass(_ kind: PassKind, atIndex index: Int) async -> PassResult {
        switch prepared[index].kind {
        case .git(let remote):
            return await gitPass(kind, remote: remote, atIndex: index)
        case .seed(let remote, let seed):
            return await seedPass(kind, remote: remote, seed: seed, atIndex: index)
        case .local:
            return localPass(atIndex: index)
        }
    }

    /// Runs one pass over a git marketplace.
    ///
    /// - Parameters:
    ///   - kind: What the pass does.
    ///   - remote: The remote of the marketplace.
    ///   - index: The marketplace.
    /// - Returns: What the pass gave.
    private func gitPass(
        _ kind: PassKind, remote: GitRemote, atIndex index: Int
    ) async -> PassResult {
        switch kind {
        case .check:
            return await checkHead(remote: remote, current: remote.cache.currentSha(), atIndex: index)
        case .update(let force):
            return await sync(remote: remote, atIndex: index, force: force)
        }
    }

    /// Runs one pass over a marketplace that the read-only seed folder serves
    /// (marketplace.md §7.5).
    ///
    /// A check reads the remote head and writes nothing, thus it runs as it
    /// does for a git marketplace. An update would write, thus it does nothing
    /// and gives one finding.
    ///
    /// - Parameters:
    ///   - kind: What the pass does.
    ///   - remote: The remote of the marketplace.
    ///   - seed: The folder of the marketplace in the seed folder.
    ///   - index: The marketplace.
    /// - Returns: What the pass gave.
    private func seedPass(
        _ kind: PassKind, remote: GitRemote, seed: MarketplaceCache, atIndex index: Int
    ) async -> PassResult {
        switch kind {
        case .check:
            return await checkHead(remote: remote, current: seed.currentSha(), atIndex: index)
        case .update:
            return refuseSeedUpdate(atIndex: index, seed: seed)
        }
    }

    /// Gives what a pass over a local folder knows, with no work at all.
    ///
    /// The folder is the layer itself, thus there is nothing to fetch and
    /// nothing to install (marketplace.md §5.1).
    ///
    /// - Parameter index: The marketplace.
    /// - Returns: The status of the folder, and no event.
    private func localPass(atIndex index: Int) -> PassResult {
        PassResult(
            status: MarketplaceStatus(id: displayID(atIndex: index), current: nil, latest: nil),
            event: nil)
    }

    /// Records that the store does not update a marketplace that the
    /// read-only seed folder serves (marketplace.md §7.5).
    ///
    /// - Parameters:
    ///   - index: The marketplace.
    ///   - seed: The folder of the marketplace in the seed folder.
    /// - Returns: The status of the seed snapshot, and no event.
    private func refuseSeedUpdate(atIndex index: Int, seed: MarketplaceCache) -> PassResult {
        let id = displayID(atIndex: index)
        record(
            diagnostics: [
                MarketplaceDiagnostic(
                    severity: .advisory, marketplaceID: id,
                    message: """
                        The read-only seed folder serves this marketplace. The store never updates a seed \
                        entry, thus this update changes nothing.
                        """)
            ],
            atIndex: index)
        return PassResult(
            status: MarketplaceStatus(id: id, current: seed.currentSha(), latest: nil), event: nil)
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
    /// - Parameters:
    ///   - remote: The remote of the marketplace.
    ///   - current: The commit that the store serves now.
    ///   - index: The marketplace to check.
    /// - Returns: The status, and
    ///   ``MarketplaceEvent/updateAvailable(id:from:to:)`` when the head
    ///   differs from the snapshot.
    private func checkHead(
        remote: GitRemote, current: String?, atIndex index: Int
    ) async -> PassResult {
        do {
            let latest = try await remoteHead(of: remote, pinnedSha: prepared[index].source.sha)
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
    ///   - remote: The remote of the marketplace.
    ///   - index: The marketplace to sync.
    ///   - force: Whether to materialize again even with no remote change.
    /// - Returns: The status, and the event of the sync when something
    ///   changed or the sync failed.
    private func sync(remote: GitRemote, atIndex index: Int, force: Bool) async -> PassResult {
        let current = remote.cache.currentSha()
        do {
            try remote.cache.makeFolders()
            return try await remote.cache.withWriterLock {
                try await installHead(remote: remote, ofIndex: index, force: force)
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
    ///   - remote: The remote of the marketplace.
    ///   - index: The marketplace to sync.
    ///   - force: Whether to materialize again even with no remote change.
    /// - Returns: The status, and ``MarketplaceEvent/updated(id:from:to:)``.
    ///   The event is `nil` when the remote head is already the snapshot that
    ///   `current` names.
    /// - Throws: ``GitTransportError``, ``MarketplaceTimeoutError``,
    ///   ``SnapshotError``, ``MarketplaceCacheError``, or the error of a file
    ///   read or write.
    private func installHead(
        remote: GitRemote, ofIndex index: Int, force: Bool
    ) async throws -> PassResult {
        let source = prepared[index].source
        let previous = remote.cache.currentSha()
        let head = try await remoteHead(of: remote, pinnedSha: source.sha)
        eventSubscribers.publish(
            .checked(id: displayID(atIndex: index), current: previous, latest: head))
        guard force || head != previous else {
            return PassResult(
                status: MarketplaceStatus(
                    id: displayID(atIndex: index), current: previous, latest: head),
                event: nil)
        }
        let fetched = try await fetch(remote: remote, source: source)
        let catalog = try materialize(remote: remote, source: source, commit: fetched)
        try remote.cache.installUnderWriterLock(
            snapshotAt: catalog.staged, sha: fetched, ref: source.isPinned ? nil : remote.ref)
        let installedID = catalog.resolved.name ?? prepared[index].key
        serve(
            atIndex: index, cache: remote.cache, sha: fetched, displayID: installedID,
            catalogVersion: catalog.resolved.version)
        record(
            diagnostics: catalog.diagnostics + duplicateDisplayIDDiagnostics(installedID, atIndex: index),
            atIndex: index)
        try save(
            record: stateRecord(
                remote: remote, source: source, sha: fetched, catalog: catalog.resolved,
                displayID: installedID),
            forFolder: remote.cache.folderName)
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
    /// - Parameters:
    ///   - remote: The remote of the marketplace to fetch.
    ///   - source: The source, as the host wrote it.
    /// - Returns: The 40-hex SHA of the fetched commit.
    /// - Throws: ``GitTransportError``, or ``MarketplaceTimeoutError`` when
    ///   the fetch took longer than the timeout.
    private func fetch(remote: GitRemote, source: MarketplaceSource) async throws -> String {
        let revision = source.sha ?? remote.ref ?? Self.defaultRef
        let transport = self.transport
        let credentials = policy.credentials
        let repository = remote.cache.repositoryDirectory
        let url = remote.url
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
    /// - Parameters:
    ///   - remote: The remote of the marketplace.
    ///   - pinnedSha: The commit that the source pins, or `nil`.
    /// - Returns: The pinned commit, else the commit that the remote head
    ///   names.
    /// - Throws: ``GitTransportError``.
    private func remoteHead(of remote: GitRemote, pinnedSha: String?) async throws -> String {
        if let pinnedSha {
            return pinnedSha
        }
        return try await transport.remoteHead(
            url: remote.url, ref: remote.ref ?? Self.defaultRef, credentials: policy.credentials)
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
    ///   - remote: The remote of the marketplace.
    ///   - source: The source, as the host wrote it.
    ///   - commit: The fetched commit.
    /// - Returns: The staged folder, the selected skills, and the findings.
    /// - Throws: ``SnapshotError``, ``CatalogFileSourceError``, or the error
    ///   of a read or of a write.
    private func materialize(
        remote: GitRemote, source: MarketplaceSource, commit: String
    ) throws -> Materialized {
        let files = try GitTreeFileSource(
            repositoryURL: remote.cache.repositoryDirectory, commit: commit, rootPath: source.path)
        let resolved = CatalogResolver.resolve(from: files, selection: source.select)
        let staged = remote.cache.snapshotsDirectory
            .appendingPathComponent(commit + Self.stagedSnapshotSuffix, isDirectory: true)
        // A staged folder that an interrupted sync left behind is not an error.
        try? FileManager.default.removeItem(at: staged)
        let report = try SnapshotWriter.write(
            catalog: resolved, from: files, to: staged, limits: policy.snapshotLimits)
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
            id: id, error: text, keptVersion: prepared[index].servingCache?.currentSha())
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
    ///   - cache: The cache folder of the marketplace.
    ///   - sha: The commit of the new snapshot.
    ///   - displayID: The display id: the catalog `name`, else the pre-fetch
    ///     key.
    ///   - catalogVersion: The `version` field of the catalog, or `nil`.
    private func serve(
        atIndex index: Int, cache: MarketplaceCache, sha: String, displayID: String,
        catalogVersion: String?
    ) {
        let url = prepared[index].source.url
        let lease = try? cache.leaseCurrentSnapshot()
        let superseded = served.withLock { layers -> SnapshotLease? in
            layers[index].layer.provenance = MarketplaceProvenance(
                id: displayID, url: url, sha: sha, catalogVersion: catalogVersion)
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

    /// Makes one layer for each source from what the disk already holds.
    ///
    /// Every source gets a layer, also before its first install: the root of a
    /// layer is a construction-time invariant of `SkillsRegistry`, thus the
    /// list must not grow when the first snapshot arrives.
    ///
    /// - Parameters:
    ///   - prepared: The sources, in list order.
    ///   - state: The state file of the cache directory.
    ///   - seedState: The state file of the read-only seed folder.
    /// - Returns: One served marketplace for each source, in list order.
    private static func servedFromDisk(
        prepared: [PreparedSource], state: MarketplaceState, seedState: MarketplaceState
    ) -> [ServedMarketplace] {
        prepared.map { entry in
            switch entry.kind {
            case .git(let remote):
                return servedFromCache(entry: entry, cache: remote.cache, state: state, leased: true)
            case .seed(_, let seed):
                // The seed folder is read only: the store never cleans it up,
                // thus it needs no lease on a snapshot of it.
                return servedFromCache(entry: entry, cache: seed, state: seedState, leased: false)
            case .local(let root):
                return ServedMarketplace(
                    layer: MarketplaceLayer(
                        layer: DotfolderStack.Layer(source: .marketplace, root: root),
                        provenance: MarketplaceProvenance(id: entry.key, url: entry.source.url),
                        grants: entry.source.grants, isWatchable: true),
                    lease: nil)
            }
        }
    }

    /// Makes the layer of one marketplace from a folder in the cache layout.
    ///
    /// - Parameters:
    ///   - entry: The source of the marketplace.
    ///   - cache: The folder of the marketplace, in the cache or in the seed
    ///     folder.
    ///   - state: The state file that belongs to that folder.
    ///   - leased: Whether the store takes a shared lock on the snapshot.
    /// - Returns: The served marketplace.
    private static func servedFromCache(
        entry: PreparedSource, cache: MarketplaceCache, state: MarketplaceState, leased: Bool
    ) -> ServedMarketplace {
        let stored = state.marketplaces[cache.folderName]
        let sha = cache.currentSha()
        let layer = MarketplaceLayer(
            layer: DotfolderStack.Layer(source: .marketplace, root: cache.currentLink),
            provenance: MarketplaceProvenance(
                id: stored?.displayID ?? entry.key, url: entry.source.url, sha: sha,
                catalogVersion: sha == nil ? nil : stored?.catalogVersion),
            grants: entry.source.grants)
        return ServedMarketplace(layer: layer, lease: leased ? try? cache.leaseCurrentSnapshot() : nil)
    }

    // MARK: - Diagnostics

    /// Replaces the findings of one marketplace.
    ///
    /// - Parameters:
    ///   - diagnostics: The findings of the pass that just ran.
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
    ///   - remote: The remote of the marketplace.
    ///   - source: The source, as the host wrote it.
    ///   - sha: The commit of the new snapshot.
    ///   - catalog: The catalog of that commit.
    ///   - displayID: The display id of the marketplace.
    /// - Returns: The record to write.
    private func stateRecord(
        remote: GitRemote, source: MarketplaceSource, sha: String, catalog: ResolvedCatalog,
        displayID: String
    ) -> MarketplaceStateRecord {
        let now = Date()
        return MarketplaceStateRecord(
            url: source.url, ref: remote.ref, pinnedSha: source.sha, currentSha: sha,
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

/// The sources of one source list that give a layer, and what the store could
/// not prepare.
///
/// The work runs before `self` is whole, thus it lives outside the actor.
private struct Preparation {
    /// The sources that the store serves, in list order.
    var sources: [MarketplaceStore.PreparedSource] = []

    /// One finding for each source that gets no layer, and for each field that
    /// the store ignores.
    var diagnostics: [MarketplaceDiagnostic] = []

    /// The cache directory that every git source writes into.
    private let cacheDirectory: URL

    /// The allowlist and the blocklist that every source must pass.
    private let policy: MarketplacePolicy

    /// The read-only seed folder, or `nil` when the environment names none.
    private let seedDirectory: URL?

    /// Prepares no source, for a list that the store refuses.
    init() {
        cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        policy = MarketplacePolicy()
        seedDirectory = nil
    }

    /// Prepares every source of a list.
    ///
    /// - Parameters:
    ///   - sources: The sources, in list order. Their pre-fetch keys are
    ///     already checked.
    ///   - cacheDirectory: The cache directory of the store.
    ///   - policy: What the host lets the store do. Its allowlist and its
    ///     blocklist run here, before any source reaches the disk or the
    ///     network.
    ///   - seedDirectory: The read-only seed folder, or `nil` for none.
    init(
        sources: [MarketplaceSource], cacheDirectory: URL, policy: MarketplacePolicy,
        seedDirectory: URL?
    ) {
        self.cacheDirectory = cacheDirectory
        self.policy = policy
        self.seedDirectory = seedDirectory
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
        // The policy runs before anything touches the disk or the network
        // (marketplace.md §6.7 and §10 item 2). A refused source gets no
        // cache folder and no layer, whatever form its URL has.
        if let refusal = policy.refusal(forNormalizedURL: location.normalizedURL) {
            diagnostics.append(Self.refusalDiagnostic(for: refusal, ofSource: source, key: key))
            return
        }
        switch location {
        case .local(let folder):
            addLocal(source: source, key: key, folder: folder)
        case .git(let url, let ref):
            addGit(source: source, key: key, url: url, ref: ref)
        }
    }

    /// Prepares a source that names a folder on this computer
    /// (marketplace.md §5.1).
    ///
    /// The layer root is `<folder>/<path>`, and the `path` field of the source
    /// names it. A source with no `path` reads the `skills` folder, which is
    /// the layout of a marketplace repository.
    ///
    /// - Parameters:
    ///   - source: The source, as the host wrote it.
    ///   - key: The pre-fetch key of the source.
    ///   - folder: The folder that the URL names.
    private mutating func addLocal(source: MarketplaceSource, key: String, folder: URL) {
        let wanted = source.path ?? MarketplaceStore.localSkillsFolderName
        guard let path = CatalogPath.normalized(path: wanted) else {
            diagnostics.append(
                MarketplaceDiagnostic(
                    severity: .error, marketplaceID: key,
                    message:
                        #"The source "\#(source.url)" has the path "\#(wanted)", which is not a relative path inside the folder. It gets no layer."#
                ))
            return
        }
        if source.select != .all {
            diagnostics.append(
                MarketplaceDiagnostic(
                    severity: .warning, marketplaceID: key,
                    message:
                        #"The source "\#(source.url)" names a folder on this computer, thus the store reads that folder as it is. A "select" field needs a catalog of a fetched commit, thus the store ignores it here."#
                ))
        }
        sources.append(
            MarketplaceStore.PreparedSource(
                source: source, key: key,
                kind: .local(root: folder.appendingPathComponent(path, isDirectory: true))))
    }

    /// Prepares a git source, and serves it from the read-only seed folder
    /// when the cache holds no snapshot of it (marketplace.md §7.5).
    ///
    /// - Parameters:
    ///   - source: The source, as the host wrote it.
    ///   - key: The pre-fetch key of the source.
    ///   - url: The normalized git URL.
    ///   - ref: The branch or the tag of the URL, or `nil`.
    private mutating func addGit(source: MarketplaceSource, key: String, url: String, ref: String?) {
        let folderName = MarketplaceIdentity.cacheFolderName(key: key, normalizedURL: url)
        let remote = MarketplaceStore.GitRemote(
            url: url, ref: source.isPinned ? source.ref : ref,
            cache: MarketplaceCache(root: cacheDirectory, folderName: folderName))
        sources.append(
            MarketplaceStore.PreparedSource(
                source: source, key: key, kind: kind(ofRemote: remote, folderName: folderName)))
    }

    /// Tells whether the read-only seed folder serves one git marketplace
    /// (marketplace.md §7.5).
    ///
    /// The seed folder has the layout of a cache directory. It serves a
    /// marketplace only when the cache of the store holds no snapshot of it,
    /// thus an installed snapshot always wins over the seed.
    ///
    /// - Parameters:
    ///   - remote: The remote of the marketplace.
    ///   - folderName: The cache folder name of the marketplace.
    /// - Returns: The seed kind when the seed folder holds a snapshot and the
    ///   cache holds none, else the git kind.
    private func kind(
        ofRemote remote: MarketplaceStore.GitRemote, folderName: String
    ) -> MarketplaceStore.PreparedKind {
        guard remote.cache.currentSha() == nil, let seedDirectory else {
            return .git(remote)
        }
        let seed = MarketplaceCache(root: seedDirectory, folderName: folderName)
        return seed.currentSha() == nil ? .git(remote) : .seed(remote, seed: seed)
    }

    /// Makes the finding for a source that the policy refuses
    /// (marketplace.md §6.7).
    ///
    /// The message names the source and the pattern, thus a host reads which
    /// rule stopped which marketplace. It holds no credential: the parser
    /// refuses a URL that carries one.
    ///
    /// - Parameters:
    ///   - refusal: Why the policy refuses the source.
    ///   - source: The source, as the host wrote it.
    ///   - key: The pre-fetch key of the source.
    /// - Returns: One error diagnostic.
    private static func refusalDiagnostic(
        for refusal: MarketplacePolicy.SourceRefusal, ofSource source: MarketplaceSource,
        key: String
    ) -> MarketplaceDiagnostic {
        let reason =
            switch refusal {
            case .blocked(let pattern):
                #"it matches the blocked \#(pattern)"#
            case .notAllowed:
                "it matches no allowed source pattern"
            }
        return MarketplaceDiagnostic(
            severity: .error, marketplaceID: key,
            message: #"The host policy refuses the source "\#(source.url)": \#(reason). It gets no layer."#)
    }
}
