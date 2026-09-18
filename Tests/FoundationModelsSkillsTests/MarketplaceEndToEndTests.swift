import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Operations
import Testing

/// The one end-to-end marketplace case (marketplace.md §13, the update
/// cycle). It proves that the parts work together, in the same shape as the
/// hot-reload case of plan.md §13.
///
/// The case is hermetic: two ``GitFixtureRepository`` marketplaces over
/// `file://` URLs, read with the real libgit2 transport, thus it needs no
/// network and no `git` binary. The searcher is a real `MetadataSearcher`
/// over the counting ``FakeEmbedder``, thus it needs no GPU.
///
/// The steps are those of the card: one cold start, then one commit, one
/// `check()`, one `update()`, and one failure. Each wait follows an event of
/// the registry, thus the case waits for no fixed time.
struct MarketplaceEndToEndTests {
    /// The number of vector values of the counting embedder. The case
    /// asserts on no vector, thus the shortest usable length is enough.
    private static let embeddingDimension = 2

    /// The display id of marketplace A, which is the `name` field of its
    /// catalog.
    private static let marketplaceAID = "marketplace-a"

    /// The display id of marketplace B.
    private static let marketplaceBID = "marketplace-b"

    /// The id of the skill that only marketplace A holds.
    private static let alphaID = "alpha"

    /// The id of the skill that both marketplace A and the local layer hold.
    private static let betaID = "beta"

    /// The id of the skill that only marketplace B holds.
    private static let gammaID = "gamma"

    /// The id of the skill of marketplace A that proves the untrusted
    /// render.
    private static let untrustedAID = "untrusted-a"

    /// The id of the skill of marketplace B that proves the untrusted
    /// render.
    private static let untrustedBID = "untrusted-b"

    /// The name that each fixture skill includes. The leading `_partials/`
    /// is the redundant form that `DotfolderLoader` also accepts.
    private static let partialName = "_partials/sah-header"

    /// The path of the partial inside the `skills/` folder of a fixture
    /// repository.
    private static let partialTreePath = "skills/\(partialName).md"

    /// The body of each skill that includes the partial.
    private static let includePartialBody = "{% include \"\(partialName)\" %}"

    /// The text of the partial of marketplace A.
    private static let headerFromMarketplaceA = "header from marketplace A"

    /// The text of the partial of marketplace B.
    private static let headerFromMarketplaceB = "header from marketplace B"

    /// The body of `alpha` at the first commit of marketplace A.
    private static let alphaBodyBeforeTheUpdate = "alpha body v1"

    /// The body of `alpha` at the second commit of marketplace A.
    private static let alphaBodyAfterTheUpdate = "alpha body v2"

    /// The body of the local copy of `beta`.
    private static let localBetaBody = "local beta body"

    /// A body of one bare `{% now %}`: a real Stencil tag that
    /// `TemplateEngine.untrustedAllowedTags` does not hold, thus an
    /// untrusted layer rejects it.
    private static let nowTagBody = "{% now %}"

    /// The error text that Extras gives when an untrusted render rejects
    /// ``nowTagBody``.
    private static let nowTagUntrustedRejection = "untrusted rendering does not allow the 'now' tag"

    /// The name of the folder that holds one folder for each snapshot, under
    /// the folder of one marketplace.
    private static let snapshotsDirectoryName = "snapshots"

    // MARK: - The whole cycle, in one scenario

    @Test
    func theMarketplaceCycleFetchesOverridesUpdatesOnceAndKeepsTheLastGoodSnapshot() async throws {
        let fixture = try await Fixture()
        defer { fixture.cancelSubscriptions() }

        try Self.stepOneAfterTheFirstSync(fixture)
        let commits = try await Self.stepTwoCheckAndUpdate(fixture)
        try await Self.stepThreeUnreachableMarketplace(fixture, keeping: commits.second)
    }

    // MARK: - Step 1: what the first sync gives

    /// Proves the four claims of the first sync: `alpha` comes from
    /// marketplace A and renders A's partial, `gamma` renders B's partial,
    /// the local `beta` wins and its shadow message names marketplace A, and
    /// every marketplace skill renders untrusted.
    ///
    /// - Parameter fixture: The started fixture.
    /// - Throws: The error of a render.
    private static func stepOneAfterTheFirstSync(_ fixture: Fixture) throws {
        let listing = fixture.registry.commandListing()

        let alphaRow = try #require(listing.first { $0.id == alphaID })
        #expect(alphaRow.source?.hasPrefix("\(marketplaceAID)@") == true)
        #expect(try fixture.registry.call(id: alphaID).contains(headerFromMarketplaceA))
        #expect(try fixture.registry.call(id: alphaID).contains(alphaBodyBeforeTheUpdate))

        let gammaRow = try #require(listing.first { $0.id == gammaID })
        #expect(gammaRow.source?.hasPrefix("\(marketplaceBID)@") == true)
        #expect(try fixture.registry.call(id: gammaID).contains(headerFromMarketplaceB))

        let betaRow = try #require(listing.first { $0.id == betaID })
        #expect(betaRow.source == nil, "the local copy of beta must win over the copy of marketplace A")
        #expect(try fixture.registry.call(id: betaID).contains(localBetaBody))

        let shadow = try #require(
            fixture.registry.diagnostics.first { $0.skillID == betaID && $0.message.contains("shadows") })
        #expect(shadow.message.contains("from marketplace `\(marketplaceAID)`"))

        for id in [untrustedAID, untrustedBID] {
            let error = try #require(throws: TemplateEngineError.self) {
                try fixture.registry.call(id: id)
            }
            #expect(
                error.description.contains(nowTagUntrustedRejection),
                "every marketplace skill must render untrusted, thus the 'now' tag of \(id) must be rejected")
        }
    }

    // MARK: - Step 2: the check and the update cycle

    /// Commits a new `alpha` body to marketplace A, proves that `check()`
    /// reports the update, and proves that one `update()` gives exactly one
    /// reload, exactly one searcher `update(items:)`, the new body, and one
    /// previous snapshot beside the new one.
    ///
    /// - Parameter fixture: The started fixture.
    /// - Returns: The first and the second commit of marketplace A.
    /// - Throws: The error of a fixture commit or of a tool dispatch.
    private static func stepTwoCheckAndUpdate(_ fixture: Fixture) async throws
        -> (first: String, second: String)
    {
        let first = fixture.firstCommitOfMarketplaceA
        let second = try fixture.marketplaceA.commit(
            files: fixture.treeOfMarketplaceA(alphaBody: alphaBodyAfterTheUpdate))

        let statuses = await fixture.store.check()
        let status = try #require(statuses.first { $0.id == marketplaceAID })
        #expect(status.current == first)
        #expect(status.latest == second)
        #expect(status.updateAvailable)
        #expect(
            await fixture.events.waitForEvent(where: { $0 == .updateAvailable(id: marketplaceAID, from: first, to: second) })
                == .updateAvailable(id: marketplaceAID, from: first, to: second))

        let events = await fixture.store.update()
        #expect(events == [.updated(id: marketplaceAID, from: first, to: second)])
        await ReloadTestSupport.expectExactlyOneEvent(fixture.reloads)
        await ReloadTestSupport.expectExactlyOneEvent(fixture.searcherUpdates)

        let useJSON = try await fixture.tool.call(
            arguments: GeneratedContent(properties: ["op": "use skill", "id": alphaID]))
        #expect(useJSON.contains(alphaBodyAfterTheUpdate))
        #expect(!useJSON.contains(alphaBodyBeforeTheUpdate))

        #expect(try Set(fixture.snapshotCommitsOfMarketplaceA()) == [first, second])
        return (first: first, second: second)
    }

    // MARK: - Step 3: an unreachable marketplace

    /// Moves the repository of marketplace A away, and proves that the next
    /// `update()` reports the failure with the commit that it kept, and that
    /// `alpha` still renders from that kept snapshot.
    ///
    /// - Parameters:
    ///   - fixture: The started fixture.
    ///   - keptCommit: The commit that the store must keep.
    /// - Throws: The error of the move or of a render.
    private static func stepThreeUnreachableMarketplace(_ fixture: Fixture, keeping keptCommit: String) async throws {
        try fixture.moveMarketplaceAAway()

        let events = await fixture.store.update()

        #expect(events == [.failed(id: marketplaceAID, error: failureText(ofFirst: events), keptVersion: keptCommit)])
        let movedDirectoryName = fixture.marketplaceA.directory.lastPathComponent
        #expect(
            failureText(ofFirst: events).contains(movedDirectoryName),
            "the event says the libgit2 message, which names the path that failed; got: \(failureText(ofFirst: events))")
        let failureDiagnostics = fixture.store.diagnostics.filter {
            $0.severity == .error && $0.marketplaceID == marketplaceAID
        }
        #expect(
            failureDiagnostics.contains { $0.message.contains(movedDirectoryName) },
            "the diagnostic says the libgit2 message, not only `unreachable`; got: \(failureDiagnostics)")
        #expect(fixture.store.marketplaceLayers().first?.provenance.sha == keptCommit)
        #expect(try fixture.registry.call(id: alphaID).contains(alphaBodyAfterTheUpdate))
    }

    /// The text of the first ``MarketplaceEvent/failed(id:error:keptVersion:)``
    /// of a list.
    ///
    /// The case asserts on the whole event, and the text of a transport
    /// failure belongs to libgit2. Reading it back keeps the assertion on
    /// the id and on the kept commit, which are the two fields of the
    /// contract.
    ///
    /// - Parameter events: The events of one update.
    /// - Returns: The text, or the empty string when the first event is no
    ///   failure.
    private static func failureText(ofFirst events: [MarketplaceEvent]) -> String {
        if case .failed(_, let error, _) = events.first {
            return error
        }
        return ""
    }

    // MARK: - Fixture

    /// Two fixture marketplaces, one local `user` layer, the store over
    /// both, and the registry, the search agent, and the fused tool that
    /// read them.
    ///
    /// The subscriptions start after ``MarketplaceStore/start()``, thus each
    /// tally counts only what the update cycle publishes.
    private final class Fixture {
        /// Marketplace A, which ships `alpha`, `beta`, and one untrusted
        /// skill.
        let marketplaceA: GitFixtureRepository

        /// Marketplace B, which ships `gamma` and one untrusted skill.
        ///
        /// No later step reads the field: it holds the repository alive,
        /// because the fixture removes the folder of the repository when it
        /// is released.
        // periphery:ignore
        let marketplaceB: GitFixtureRepository

        /// The first commit of ``marketplaceA``.
        let firstCommitOfMarketplaceA: String

        /// The store over both marketplaces, and its temporary cache.
        let cache: MarketplaceStoreFixture

        /// The registry over the marketplace layers and the local layer.
        let registry: SkillsRegistry

        /// The fused `skills` tool over ``registry``.
        let tool: SkillsCatalogTool

        /// Counts each `onReload` publication of ``registry``.
        let reloads = ReloadTestSupport.EventTally()

        /// Counts each forwarded `SkillSearchAgent.update(items:)` call.
        let searcherUpdates = ReloadTestSupport.EventTally()

        /// Records each event of the store.
        let events = MarketplaceEventLog()

        /// The task of each subscription that ``cancelSubscriptions()``
        /// ends.
        private let subscriptions: [Task<Void, Never>]

        /// The store of ``cache``.
        var store: MarketplaceStore { cache.store }

        /// Builds both marketplaces and the local layer, starts the store,
        /// and then builds the registry, the agent, and the tool over it.
        ///
        /// - Throws: The error of a fixture commit, of a file write, or of
        ///   the tool factory.
        init() async throws {
            marketplaceA = try GitFixtureRepository()
            marketplaceB = try GitFixtureRepository()
            firstCommitOfMarketplaceA = try marketplaceA.commit(
                files: Fixture.treeOfMarketplaceA(alphaBody: alphaBodyBeforeTheUpdate))
            try marketplaceB.commit(files: Fixture.treeOfMarketplaceB())

            cache = try MarketplaceStoreFixture(
                sources: [
                    MarketplaceSource(marketplaceA.url, alias: "a"),
                    MarketplaceSource(marketplaceB.url, alias: "b"),
                ])
            try ReloadTestSupport.writeSkillFile(id: betaID, in: cache.localRoot, body: localBetaBody)

            let eventStream = cache.store.events
            let eventTask = events.follow(eventStream)
            await cache.store.start()

            var stack = DotfolderStack(name: "skills", workingDirectory: cache.localRoot, environment: [:])
            stack.layers = [DotfolderStack.Layer(source: .user, root: cache.localRoot)]
            registry = SkillsRegistry(marketplaces: cache.store, stack: stack)

            let searcher = await MetadataSearcher(
                items: registry.metadata().filter(\.isModelVisible),
                weights: Weights(cosine: 0),
                embedder: FakeEmbedder(dimension: embeddingDimension))
            let agent = SkillSearchAgent(searcher: searcher)
            tool = try SkillsTool.make(context: SkillsToolContext(registry: registry, searchAgent: agent))
            subscriptions = [
                eventTask,
                ReloadTestSupport.tally(registry.onReload, into: reloads),
                ReloadTestSupport.forward(registry.onReload, to: agent, recordingInto: searcherUpdates),
            ]
        }

        /// Ends every subscription task.
        func cancelSubscriptions() {
            for subscription in subscriptions {
                subscription.cancel()
            }
        }

        /// The whole tree of marketplace A, with one body for `alpha`.
        ///
        /// - Parameter alphaBody: The body of the `alpha` skill.
        /// - Returns: The tree, one entry for each path.
        func treeOfMarketplaceA(alphaBody: String) -> [String: GitFixtureRepository.Entry] {
            Fixture.treeOfMarketplaceA(alphaBody: alphaBody)
        }

        /// The commits of the snapshots that the folder of marketplace A
        /// holds.
        ///
        /// - Returns: One commit for each snapshot folder.
        /// - Throws: The error of the folder read.
        func snapshotCommitsOfMarketplaceA() throws -> [String] {
            let layer = try #require(
                store.marketplaceLayers().first { $0.provenance.id == marketplaceAID })
            let snapshots = layer.layer.root.deletingLastPathComponent()
                .appendingPathComponent(snapshotsDirectoryName, isDirectory: true)
            return try FileManager.default.contentsOfDirectory(atPath: snapshots.path)
        }

        /// Moves the repository folder of marketplace A, thus its `file://`
        /// URL no longer opens.
        ///
        /// - Throws: The error of the move.
        func moveMarketplaceAAway() throws {
            let away = marketplaceA.directory.deletingLastPathComponent()
                .appendingPathComponent("moved-away.git", isDirectory: true)
            try FileManager.default.moveItem(at: marketplaceA.directory, to: away)
        }

        /// The whole tree of marketplace A: the catalog, the three skills,
        /// and the partial of A.
        ///
        /// - Parameter alphaBody: The body of the `alpha` skill.
        /// - Returns: The tree, one entry for each path.
        private static func treeOfMarketplaceA(alphaBody: String) -> [String: GitFixtureRepository.Entry] {
            tree(
                name: marketplaceAID, header: headerFromMarketplaceA,
                skills: [
                    (id: alphaID, body: "\(includePartialBody)\n\(alphaBody)"),
                    (id: betaID, body: includePartialBody),
                    (id: untrustedAID, body: nowTagBody),
                ])
        }

        /// The whole tree of marketplace B: the catalog, the two skills, and
        /// the partial of B.
        ///
        /// - Returns: The tree, one entry for each path.
        private static func treeOfMarketplaceB() -> [String: GitFixtureRepository.Entry] {
            tree(
                name: marketplaceBID, header: headerFromMarketplaceB,
                skills: [
                    (id: gammaID, body: includePartialBody),
                    (id: untrustedBID, body: nowTagBody),
                ])
        }

        /// One marketplace tree in our own format (marketplace.md §3.2 and
        /// §3.3): a Claude catalog with one plugin, one folder for each
        /// skill under `skills/`, and one partial beside them.
        ///
        /// - Parameters:
        ///   - name: The `name` field of the catalog, which becomes the
        ///     display id of the marketplace.
        ///   - header: The text of the partial of this marketplace.
        ///   - skills: The id and the body of each skill, in catalog order.
        /// - Returns: The tree, one entry for each path.
        private static func tree(
            name: String, header: String, skills: [(id: String, body: String)]
        ) -> [String: GitFixtureRepository.Entry] {
            let paths = skills.lazy.map { #""./skills/\#($0.id)""# }.joined(separator: ", ")
            let catalog = #"""
                {"name": "\#(name)", "plugins": [{"name": "skills", "source": "./", "skills": [\#(paths)]}]}
                """#
            let skillFiles = skills.lazy.map { skill in
                (
                    "skills/\(skill.id)/SKILL.md",
                    GitFixtureRepository.Entry.file(
                        ReloadTestSupport.skillFileContents(id: skill.id, body: skill.body))
                )
            }
            return Dictionary(uniqueKeysWithValues: skillFiles).merging([
                ".claude-plugin/marketplace.json": .file(catalog),
                partialTreePath: .file(header),
            ]) { _, later in later }
        }
    }
}
