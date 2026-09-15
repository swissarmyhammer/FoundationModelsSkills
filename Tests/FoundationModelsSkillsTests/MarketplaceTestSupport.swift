import Foundation
import FoundationModelsExtras
import Synchronization

@testable import FoundationModelsSkills

/// Records each URL that a credential provider gets.
///
/// `CredentialGateTests` and `GitTransportTests` both prove that a credential
/// provider is asked one time, and with which URL. Thus the recorder is here,
/// and not in one of the two suites.
actor CredentialRequestRecorder {
    /// The URL of each request, in order.
    private(set) var requestedURLs: [URL] = []

    /// Records one request.
    ///
    /// - Parameter url: The URL that the provider got.
    func record(url: URL) {
        requestedURLs.append(url)
    }

    /// Makes a provider that records each request and gives `credential`.
    ///
    /// - Parameter credential: The credential that the provider gives.
    /// - Returns: The provider.
    nonisolated func provider(giving credential: MarketplaceCredential) -> @Sendable (URL) async -> MarketplaceCredential? {
        { url in
            await self.record(url: url)
            return credential
        }
    }
}

/// The shared file helpers of the marketplace tests. `MarketplaceCatalogTests`
/// and `MarketplaceConfigTests` both write text files into a temporary folder.
enum MarketplaceTestSupport {
    /// Makes a new temporary folder and writes a tree of text files into it.
    ///
    /// - Parameter files: The text of each file, keyed by its path in the
    ///   folder. The default is no file.
    /// - Returns: The new folder.
    /// - Throws: The error of a folder or file write.
    static func makeTempDirectory(withFiles files: [String: String] = [:]) throws -> URL {
        let root = try WatcherTestSupport.makeTempDirectory()
        for (path, text) in files {
            try writeFile(text: text, to: root.appendingPathComponent(path))
        }
        return root
    }

    /// Writes text to a file, and makes the folder of the file first.
    ///
    /// - Parameters:
    ///   - text: The text of the file.
    ///   - file: The file to write.
    /// - Throws: The error of the folder or the file write.
    static func writeFile(text: String, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Makes one marketplace layer over a root.
    ///
    /// `MarketplaceRegistryTests` and `MarketplaceGrantsTests` both build a
    /// layer this way, thus the helper is here.
    ///
    /// - Parameters:
    ///   - root: The stable layer root of the marketplace.
    ///   - id: The display id of the marketplace.
    ///   - sha: The commit of the snapshot.
    ///   - grants: What the host lets the skills of the marketplace run. The
    ///     default is `MarketplaceGrants.none`.
    ///   - catalogVersion: The `version` field of the catalog, or `nil` for
    ///     a catalog with no version. The default is
    ///     ``defaultCatalogVersion``.
    /// - Returns: The layer.
    static func makeMarketplaceLayer(
        root: URL, id: String, sha: String, grants: MarketplaceGrants = .none,
        catalogVersion: String? = defaultCatalogVersion
    ) -> MarketplaceLayer {
        MarketplaceLayer(
            layer: DotfolderStack.Layer(source: .marketplace, root: root),
            provenance: MarketplaceProvenance(
                id: id, url: "https://example.invalid/\(id).git", sha: sha,
                catalogVersion: catalogVersion),
            grants: grants)
    }

    /// The `version` field ``makeMarketplaceLayer(root:id:sha:grants:catalogVersion:)``
    /// gives a catalog when the caller names none.
    static let defaultCatalogVersion = "1.0.0"
}

/// A ``GitTransport`` that counts the calls of the store, records the
/// credential that each fetch received, and then does the real libgit2 work.
///
/// A pure double would put no object in the bare repository, thus the store
/// would have no tree to read. The recorder wraps ``LibGit2Transport``
/// instead, so a store test sees real snapshots and still counts the calls.
actor RecordingGitTransport: GitTransport {
    /// The transport that does the work.
    private let base = LibGit2Transport()

    /// How many times the store asked for a remote head.
    private(set) var remoteHeadCount = 0

    /// How many times the store fetched.
    private(set) var fetchCount = 0

    /// The credential that the provider of each fetch gave, in call order.
    /// An entry is `nil` when the fetch got no provider.
    private(set) var fetchCredentials: [MarketplaceCredential?] = []

    func remoteHead(
        url: String, ref: String, credentials: (@Sendable (URL) async -> MarketplaceCredential?)?
    ) async throws -> String {
        remoteHeadCount += 1
        return try await base.remoteHead(url: url, ref: ref, credentials: credentials)
    }

    func fetch(
        url: String, revision: String, intoBareRepository repositoryURL: URL,
        credentials: (@Sendable (URL) async -> MarketplaceCredential?)?
    ) async throws -> String {
        fetchCount += 1
        fetchCredentials.append(await Self.credential(from: credentials, forURL: url))
        return try await base.fetch(
            url: url, revision: revision, intoBareRepository: repositoryURL, credentials: credentials)
    }

    /// Asks a credentials provider for the credential of one source.
    ///
    /// - Parameters:
    ///   - credentials: The provider of the call, or `nil` when the call got
    ///     none.
    ///   - url: The git URL of the remote.
    /// - Returns: The credential, or `nil` when there is no provider or the
    ///   provider gives none.
    private static func credential(
        from credentials: (@Sendable (URL) async -> MarketplaceCredential?)?, forURL url: String
    ) async -> MarketplaceCredential? {
        guard let credentials, let requestURL = URL(string: url) else {
            return nil
        }
        return await credentials(requestURL)
    }
}

/// Tells whether a shared lock holds one snapshot folder (marketplace.md
/// §7.6).
///
/// `MarketplaceCacheTests` proves the lease itself, and
/// `MarketplaceStoreTests` proves which snapshot the store leases. Thus the
/// probe is here, and not in one of the two suites.
enum SnapshotLockProbe {
    /// Whether a second open of one folder cannot take the exclusive lock.
    ///
    /// A `flock(2)` lock belongs to the open file and not to the process, thus
    /// a second open in this process sees the shared lock of a lease.
    ///
    /// - Parameter directory: The snapshot folder to test.
    /// - Returns: `true` when a lock holds the folder. A folder that does not
    ///   open gives `false`.
    static func isLocked(directory: URL) -> Bool {
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY)
        if descriptor < 0 {
            return false
        }
        defer { close(descriptor) }
        return flock(descriptor, LOCK_EX | LOCK_NB) != 0
    }
}

/// One ``MarketplaceStore`` over a temporary cache, plus the empty local
/// layer root that a registry test puts above its marketplace layers.
///
/// The fixture removes every folder that it made when it is released, thus a
/// store test leaves nothing behind.
final class MarketplaceStoreFixture {
    /// The cache directory of the store.
    let cacheDirectory: URL

    /// The root of the one local layer of ``makeRegistry()``.
    let localRoot: URL

    /// The store under test.
    let store: MarketplaceStore

    /// Whether the fixture made ``cacheDirectory`` and thus removes it.
    private let ownsCacheDirectory: Bool

    /// Makes a store over a temporary cache.
    ///
    /// - Parameters:
    ///   - sources: The marketplace sources, in list order.
    ///   - cacheDirectory: The cache directory to share with another store,
    ///     or `nil` for a new temporary one. The default is `nil`.
    ///   - policy: The policy of the store. The default is
    ///     `MarketplacePolicy()`.
    ///   - transport: The git transport, or `nil` for the real
    ///     ``LibGit2Transport``. The default is `nil`.
    /// - Throws: The error of a folder write.
    init(
        sources: [MarketplaceSource], cacheDirectory: URL? = nil,
        policy: MarketplacePolicy = MarketplacePolicy(), transport: (any GitTransport)? = nil
    ) throws {
        ownsCacheDirectory = cacheDirectory == nil
        self.cacheDirectory = try cacheDirectory ?? WatcherTestSupport.makeTempDirectory()
        localRoot = try WatcherTestSupport.makeTempDirectory()
        store = MarketplaceStore(
            sources: sources, cacheDirectory: self.cacheDirectory, policy: policy,
            transport: transport ?? LibGit2Transport())
    }

    deinit {
        try? FileManager.default.removeItem(at: localRoot)
        if ownsCacheDirectory {
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
    }

    /// Makes a registry over the layers of the store and one empty local
    /// project layer.
    ///
    /// - Returns: The registry, with watching off.
    func makeRegistry() -> SkillsRegistry {
        var stack = DotfolderStack(name: "skills", workingDirectory: localRoot, environment: [:])
        stack.layers = [DotfolderStack.Layer(source: .project, root: localRoot)]
        return SkillsRegistry(marketplaces: store, stack: stack)
    }
}

/// A provider whose layer list the test replaces, and which publishes one
/// update for each replacement.
///
/// Every stored property is an immutable `let` of a `Sendable` type: the
/// mutable layer list lives inside a `Mutex`, which gives the class a
/// plain `Sendable` conformance the compiler checks.
final class FakeMarketplaceProvider: MarketplaceLayerProviding, Sendable {
    private let layers: Mutex<[MarketplaceLayer]>
    private let continuation: AsyncStream<Void>.Continuation

    let layerUpdates: AsyncStream<Void>

    /// Creates a provider over one starting layer list.
    ///
    /// - Parameter layers: The starting layers, lowest precedence first.
    init(layers: [MarketplaceLayer]) {
        self.layers = Mutex(layers)
        let made = AsyncStream<Void>.makeStream()
        layerUpdates = made.stream
        continuation = made.continuation
    }

    /// Gives the current layers, lowest precedence first.
    ///
    /// - Returns: The layers.
    func marketplaceLayers() -> [MarketplaceLayer] {
        layers.withLock { $0 }
    }

    /// Replaces the layers and publishes one update.
    ///
    /// - Parameter layers: The new layers, lowest precedence first.
    func publish(layers: [MarketplaceLayer]) {
        self.layers.withLock { $0 = layers }
        continuation.yield()
    }
}
