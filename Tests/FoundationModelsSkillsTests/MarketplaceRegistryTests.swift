import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Tests for the marketplace half of `SkillsRegistry` (marketplace.md §4.1,
/// §4.2, §7.4, §9.1): marketplace layers sit below the local stack, so a
/// local skill always wins and the last marketplace wins among themselves;
/// a diagnostic carries the marketplace it came from; the shadow advisory
/// names the marketplace that lost; and one provider update rebuilds the
/// catalog one time, also for a `watch: false` registry.
struct MarketplaceRegistryTests {
    /// How long a test waits for an expected `onReload` publication before
    /// it treats the absence as a failure (mirrors
    /// `SkillsRegistryReloadTests.expectedSignalTimeout`).
    private static let expectedSignalTimeout: Duration = .seconds(10)

    /// How long a test waits, after an expected publication arrived, to
    /// confirm that no *second* publication follows it (mirrors
    /// `SkillsRegistryReloadTests.noFurtherSignalWindow`).
    private static let noFurtherSignalWindow: Duration = .seconds(1)

    /// The id of the skill every precedence test writes into each layer.
    private static let sharedSkillID = "commit"

    // MARK: - Precedence (§4.1)

    @Test func aLocalSkillWinsOverEveryMarketplaceCopyOfTheSameID() throws {
        let fixture = try Fixture(localBody: "local body")
        let registry = fixture.makeRegistry()

        let body = try registry.call(id: Self.sharedSkillID)
        #expect(body.contains("local body"))
    }

    @Test func theLastMarketplaceWinsWhenNoLocalCopyExists() throws {
        let fixture = try Fixture(localBody: nil)
        let registry = fixture.makeRegistry()

        let body = try registry.call(id: Self.sharedSkillID)
        #expect(body.contains("second marketplace body"))
    }

    @Test func reversingTheProviderOrderMakesTheOtherMarketplaceWin() throws {
        let fixture = try Fixture(localBody: nil, reversedMarketplaceOrder: true)
        let registry = fixture.makeRegistry()

        let body = try registry.call(id: Self.sharedSkillID)
        #expect(body.contains("first marketplace body"))
    }

    // MARK: - Shadow message (§9.1)

    @Test func theShadowMessageNamesEachMarketplaceThatLost() throws {
        let fixture = try Fixture(localBody: "local body")
        let registry = fixture.makeRegistry()

        let shadow = try #require(
            registry.diagnostics.first { $0.skillID == Self.sharedSkillID && $0.message.contains("shadows") })
        #expect(shadow.message.contains("from marketplace `first-marketplace`"))
        #expect(shadow.message.contains("from marketplace `second-marketplace`"))
        #expect(shadow.message.contains(fixture.localRoot.appendingPathComponent(Self.sharedSkillID).path))
    }

    // MARK: - Provenance (§9.1)

    @Test func aMarketplaceSkillCarriesItsMarketplaceProvenanceInEveryDiagnostic() throws {
        let fixture = try Fixture(localBody: nil)
        let registry = fixture.makeRegistry()

        let diagnostic = try #require(registry.diagnostics.first { $0.skillID == Self.sharedSkillID })
        let marketplace = try #require(diagnostic.provenance.marketplace)
        #expect(marketplace.id == "second-marketplace")
        #expect(marketplace.sha == "sha-second-1")
    }

    @Test func aLocalWinnersDiagnosticCarriesNoMarketplaceProvenance() throws {
        let fixture = try Fixture(localBody: "local body")
        let registry = fixture.makeRegistry()

        let diagnostic = try #require(registry.diagnostics.first { $0.skillID == Self.sharedSkillID })
        #expect(diagnostic.provenance.marketplace == nil)
    }

    // MARK: - Reload on a provider update (§7.4)

    @Test func aProviderUpdateRebuildsOnceAndCarriesTheNewShaEvenWithoutWatching() async throws {
        let fixture = try Fixture(localBody: nil)
        let registry = fixture.makeRegistry()
        let bodyBefore = try registry.call(id: Self.sharedSkillID)
        #expect(bodyBefore.contains("second marketplace body"))

        let stream = try #require(
            registry.onReload, "a marketplace-backed registry publishes reloads even with watch: false")
        let tally = ReloadTestSupport.EventTally()
        let subscription = ReloadTestSupport.tally(stream, into: tally)
        defer { subscription.cancel() }

        try fixture.publishSecondMarketplaceUpdate(body: "second marketplace body v2", sha: "sha-second-2")
        await ReloadTestSupport.expectExactlyOneEvent(
            countGetter: { await tally.count }, since: 0,
            signalTimeout: Self.expectedSignalTimeout, settleWindow: Self.noFurtherSignalWindow)

        let bodyAfter = try registry.call(id: Self.sharedSkillID)
        #expect(bodyAfter.contains("second marketplace body v2"))
        let diagnostic = try #require(registry.diagnostics.first { $0.skillID == Self.sharedSkillID })
        #expect(diagnostic.provenance.marketplace?.sha == "sha-second-2")
    }

    // MARK: - Fixture

    /// Two marketplace roots and one local project root, each holding the
    /// same skill id, plus the provider the registry is built over.
    ///
    /// Every marketplace copy carries an empty `compatibility:`, which draws
    /// the advisory the provenance assertions read: a well-formed skill
    /// raises no diagnostic at all, thus there would be nothing to carry
    /// provenance on.
    private struct Fixture {
        /// The root of the marketplace the provider lists first.
        let firstRoot: URL
        /// The root of the marketplace the provider lists second.
        let secondRoot: URL
        /// The root of the local project layer.
        let localRoot: URL
        /// The provider the registry subscribes to.
        let provider: FakeMarketplaceProvider

        /// Writes the three roots and builds the provider.
        ///
        /// - Parameters:
        ///   - localBody: The body of the local copy of the shared skill, or
        ///     `nil` to leave the local root without that skill.
        ///   - reversedMarketplaceOrder: Whether the provider lists the
        ///     second root first. The default is `false`.
        /// - Throws: The error of a folder or file write.
        init(localBody: String?, reversedMarketplaceOrder: Bool = false) throws {
            firstRoot = try MarketplaceTestSupport.makeTempDirectory()
            secondRoot = try MarketplaceTestSupport.makeTempDirectory()
            localRoot = try MarketplaceTestSupport.makeTempDirectory()

            try Fixture.writeSharedSkill(in: firstRoot, body: "first marketplace body")
            try Fixture.writeSharedSkill(in: secondRoot, body: "second marketplace body")
            if let localBody {
                try ReloadTestSupport.writeSkillFile(
                    id: MarketplaceRegistryTests.sharedSkillID, in: localRoot, body: localBody)
            }

            let first = Fixture.makeLayer(root: firstRoot, id: "first-marketplace", sha: "sha-first-1")
            let second = Fixture.makeLayer(root: secondRoot, id: "second-marketplace", sha: "sha-second-1")
            provider = FakeMarketplaceProvider(
                layers: reversedMarketplaceOrder ? [second, first] : [first, second])
        }

        /// Builds a registry over the provider and a stack whose only layer
        /// is the local project root.
        ///
        /// - Returns: The registry, with watching off.
        func makeRegistry() -> SkillsRegistry {
            var stack = DotfolderStack(name: "skills", workingDirectory: localRoot, environment: [:])
            stack.layers = [DotfolderStack.Layer(source: .project, root: localRoot)]
            return SkillsRegistry(marketplaces: provider, stack: stack)
        }

        /// Rewrites the shared skill in the second marketplace root and
        /// publishes one provider update carrying a new SHA.
        ///
        /// - Parameters:
        ///   - body: The new body of the shared skill.
        ///   - sha: The new commit of that marketplace.
        /// - Throws: The error of a folder or file write.
        func publishSecondMarketplaceUpdate(body: String, sha: String) throws {
            try Fixture.writeSharedSkill(in: secondRoot, body: body)
            let first = Fixture.makeLayer(root: firstRoot, id: "first-marketplace", sha: "sha-first-1")
            let second = Fixture.makeLayer(root: secondRoot, id: "second-marketplace", sha: sha)
            provider.publish(layers: [first, second])
        }

        /// Writes the shared skill, with an empty `compatibility:` so that
        /// the skill always draws one advisory diagnostic.
        ///
        /// - Parameters:
        ///   - root: The layer root to write under.
        ///   - body: The body of the skill.
        /// - Throws: The error of a folder or file write.
        private static func writeSharedSkill(in root: URL, body: String) throws {
            try ReloadTestSupport.writeSkillFile(
                id: MarketplaceRegistryTests.sharedSkillID, in: root,
                extraFrontmatter: "compatibility: \"\"\n", body: body)
        }

        /// Makes one marketplace layer over a root.
        ///
        /// - Parameters:
        ///   - root: The stable layer root of the marketplace.
        ///   - id: The display id of the marketplace.
        ///   - sha: The commit of the snapshot.
        /// - Returns: The layer.
        private static func makeLayer(root: URL, id: String, sha: String) -> MarketplaceLayer {
            MarketplaceLayer(
                layer: DotfolderStack.Layer(source: .marketplace, root: root),
                provenance: MarketplaceProvenance(
                    id: id, url: "https://example.invalid/\(id).git", sha: sha, catalogVersion: "1.0.0"))
        }
    }

    /// A provider whose layer list the test replaces, and which publishes one
    /// update for each replacement.
    ///
    /// `@unchecked Sendable`: `layers` is only ever read or written while
    /// `lock` is held, and every other stored property is an immutable `let`.
    private final class FakeMarketplaceProvider: MarketplaceLayerProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var layers: [MarketplaceLayer]
        private let continuation: AsyncStream<Void>.Continuation

        let layerUpdates: AsyncStream<Void>

        /// Creates a provider over one starting layer list.
        ///
        /// - Parameter layers: The starting layers, lowest precedence first.
        init(layers: [MarketplaceLayer]) {
            self.layers = layers
            let made = AsyncStream<Void>.makeStream()
            layerUpdates = made.stream
            continuation = made.continuation
        }

        /// Gives the current layers, lowest precedence first.
        ///
        /// - Returns: The layers.
        func marketplaceLayers() -> [MarketplaceLayer] {
            lock.withLock { layers }
        }

        /// Replaces the layers and publishes one update.
        ///
        /// - Parameter layers: The new layers, lowest precedence first.
        func publish(layers: [MarketplaceLayer]) {
            lock.withLock { self.layers = layers }
            continuation.yield()
        }
    }
}
