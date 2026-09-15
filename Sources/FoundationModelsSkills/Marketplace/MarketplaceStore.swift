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
    internal init(
        sources: [MarketplaceSource], cacheDirectory: URL, policy: MarketplacePolicy,
        transport: any GitTransport
    ) {
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

    /// Brings every git marketplace to its remote head one time
    /// (marketplace.md §7.5).
    ///
    /// The call fetches, materializes, and swaps `current` for each source
    /// whose remote head differs from the snapshot on the disk. A source that
    /// is already at its head does no fetch.
    public func start() async {
        _ = await update()
    }

    /// Brings one marketplace, or every marketplace, to its remote head.
    ///
    /// - Parameters:
    ///   - id: The pre-fetch key or the display id of one marketplace, or
    ///     `nil` for every marketplace. The default is `nil`.
    ///   - force: Whether to materialize again even when the remote head is
    ///     the snapshot that `current` names. The default is `false`.
    /// - Returns: One event for each marketplace that installed a snapshot or
    ///   failed, in list order. A marketplace that is already at its head
    ///   gives no event.
    @discardableResult
    public func update(_ id: String? = nil, force: Bool = false) async -> [MarketplaceEvent] {
        var events: [MarketplaceEvent] = []
        for index in prepared.indices where names(index: index, id: id) {
            if let event = await sync(atIndex: index, force: force) {
                events.append(event)
            }
        }
        return events
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
    /// - Returns: The event of the sync, or `nil` when nothing changed.
    private func sync(atIndex index: Int, force: Bool) async -> MarketplaceEvent? {
        let entry = prepared[index]
        do {
            try entry.cache.makeFolders()
            return try await entry.cache.withWriterLock {
                try await installHead(ofIndex: index, force: force)
            }
        } catch {
            return failure(atIndex: index, error: error)
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
    /// - Returns: ``MarketplaceEvent/updated(id:from:to:)``, or `nil` when the
    ///   remote head is already the snapshot that `current` names.
    /// - Throws: ``GitTransportError``, ``SnapshotError``,
    ///   ``MarketplaceCacheError``, or the error of a file read or write.
    private func installHead(ofIndex index: Int, force: Bool) async throws -> MarketplaceEvent? {
        let entry = prepared[index]
        let previous = entry.cache.currentSha()
        let head = try await remoteHead(of: entry)
        guard force || head != previous else {
            return nil
        }
        let fetched = try await transport.fetch(
            url: entry.url, revision: entry.source.sha ?? entry.ref ?? Self.defaultRef,
            intoBareRepository: entry.cache.repositoryDirectory, credentials: policy.credentials)
        let catalog = try materialize(entry: entry, commit: fetched)
        try entry.cache.installUnderWriterLock(
            snapshotAt: catalog.staged, sha: fetched, ref: entry.source.isPinned ? nil : entry.ref)
        let displayID = catalog.resolved.name ?? entry.key
        serve(atIndex: index, sha: fetched, displayID: displayID, catalogVersion: catalog.resolved.version)
        record(
            diagnostics: catalog.diagnostics + duplicateDisplayIDDiagnostics(displayID, atIndex: index),
            atIndex: index)
        try save(record: stateRecord(of: entry, sha: fetched, catalog: catalog.resolved, displayID: displayID),
            forFolder: entry.cache.folderName)
        let event = MarketplaceEvent.updated(id: displayID, from: previous, to: fetched)
        eventSubscribers.publish(event)
        updateSubscribers.publish(())
        return event
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
        let text = String(describing: error)
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

    // MARK: - The served layers

    /// Replaces what the store serves for one marketplace, and takes a shared
    /// lock on the new snapshot.
    ///
    /// The lease of the snapshot before this one is released here, thus the
    /// next cleanup can delete that folder.
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
        served.withLock { layers in
            layers[index].layer.provenance = MarketplaceProvenance(
                id: displayID, url: entry.source.url, sha: sha, catalogVersion: catalogVersion)
            layers[index].lease = lease
        }
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
