import Foundation
import FoundationModelsExtras
import Marketplace
import MarketplaceFixtures
import Synchronization

@testable import FoundationModelsSkills

/// The shared helpers of the marketplace tests of this package.
///
/// The marketplace itself, and every fixture that drives it, belong to
/// `FoundationModelsExtras`: `GitFixtureRepository`, `RecordingGitTransport`,
/// `GatedGitTransport`, `ManualClock`, `MarketplaceEventLog`, `TestSignal`
/// and `MarketplaceStoreFixture` all come from its `MarketplaceFixtures`
/// product. This file defines none of them. It holds what only a skill test
/// needs: a folder of skill files, and a marketplace layer that names one.
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
    /// `MarketplaceRegistryTests` and `RunScriptTests` both build a layer
    /// this way, thus the helper is here.
    ///
    /// - Parameters:
    ///   - root: The stable layer root of the marketplace.
    ///   - id: The display id of the marketplace.
    ///   - sha: The commit of the snapshot.
    ///   - catalogVersion: The `version` field of the catalog, or `nil` for
    ///     a catalog with no version. The default is
    ///     ``defaultCatalogVersion``.
    /// - Returns: The layer.
    static func makeMarketplaceLayer(
        root: URL, id: String, sha: String, catalogVersion: String? = defaultCatalogVersion
    ) -> MarketplaceLayer {
        MarketplaceLayer(
            layer: DotfolderStack.Layer(source: .marketplace, root: root),
            provenance: MarketplaceProvenance(
                id: id, url: "https://example.invalid/\(id).git", sha: sha,
                catalogVersion: catalogVersion))
    }

    /// The `version` field ``makeMarketplaceLayer(root:id:sha:catalogVersion:)``
    /// gives a catalog when the caller names none.
    static let defaultCatalogVersion = "1.0.0"

    /// The skill id that a fixture repository holds.
    static let fixtureSkillID = "alpha"

    /// Makes the tree of one fixture commit: one skill under `skills`.
    ///
    /// `MarketplaceLocalSourceTests` builds this tree in more than one case,
    /// thus the helper is here.
    ///
    /// - Parameter body: The body of the skill.
    /// - Returns: The tree, one entry for each path.
    static func skillTree(body: String) -> [String: GitFixtureRepository.Entry] {
        [
            "skills/\(fixtureSkillID)/SKILL.md":
                .file(ReloadTestSupport.skillFileContents(id: fixtureSkillID, body: body))
        ]
    }
}

extension MarketplaceStoreFixture {
    /// The dotfolder name of the stack that ``makeRegistry(watch:)`` builds.
    private var dotfolderName: String { "skills" }

    /// Makes a registry over the layers of the store and one empty local
    /// project layer.
    ///
    /// The fixture of `MarketplaceFixtures` knows the store alone, because
    /// that package knows no skill and no registry. This is the one call
    /// that a registry test of this package adds to it.
    ///
    /// - Parameter watch: Whether the registry watches every layer root. The
    ///   default is `false`.
    /// - Returns: The registry.
    func makeRegistry(watch: Bool = false) -> SkillsRegistry {
        var stack = DotfolderStack(
            name: dotfolderName, workingDirectory: localRoot,
            environment: [:])
        stack.layers = [DotfolderStack.Layer(source: .project, root: localRoot)]
        return SkillsRegistry(marketplaces: store, stack: stack, watch: watch)
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
