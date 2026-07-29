import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Testing

/// Tests for `SkillSearchAgent`, the thin `MetadataSearcher<SkillMetadata>`
/// wrapper (plan.md §7, §7.1, §13; decision #26): seeding filters to the
/// model-visible subset, a keyword query over the fixture catalog ranks the
/// expected ids, cosine joins fusion once an embedder is wired up, and
/// `update(items:)` makes a catalog change's new id searchable while
/// dropping a removed one and filtering out a model-hidden one -- all
/// driven through a REAL `MetadataSearcher` in `.retrieval` mode, GPU-free.
struct SkillSearchAgentTests {
    // MARK: - Fixture roots (mirrors SkillsRegistryTests)

    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    // MARK: - `TextEmbedding` test double (plan.md §13)

    /// A deterministic `TextEmbedding` test double: returns a caller-
    /// supplied vector for each registered text, falling back to an
    /// all-zero vector for any text not explicitly registered.
    ///
    /// Replicates `FoundationModelsMetadataRegistry`'s own test-target-local
    /// `FakeEmbedder` (not importable from this package's test target),
    /// minus its call-counting -- unused by this task's cases, which only
    /// need deterministic vectors to prove cosine joins fusion through
    /// `SkillSearchAgent`.
    private struct FakeEmbedder: TextEmbedding {
        let dimension: Int
        let vectorsByText: [String: [Float]]

        func embed(_ texts: [String]) async throws -> [[Float]] {
            texts.map { vectorsByText[$0] ?? [Float](repeating: 0, count: dimension) }
        }
    }

    // MARK: - Seeding filters to the model-visible subset

    @Test func seedingIncludesModelVisibleLintButExcludesModelHiddenDeploy() async throws {
        let registry = SkillsRegistry(roots: [Self.projectSkillsRoot])
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        let agent = SkillSearchAgent(searcher: searcher)

        let lintMatches = try await agent.search(query: "lint", limit: 10)
        #expect(lintMatches.contains { $0.id == "lint" })

        let deployMatches = try await agent.search(query: "deploy", limit: 10)
        #expect(!deployMatches.contains { $0.id == "deploy" })
    }

    // MARK: - Keyword query ranking

    @Test func keywordQueryOverTheFixtureCatalogRanksCommitFirstWithTheExpectedTotal() async throws {
        let registry = SkillsRegistry(roots: [Self.projectSkillsRoot])
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        let agent = SkillSearchAgent(searcher: searcher)

        let matches = try await agent.search(query: "commit", limit: 10)

        #expect(matches.map(\.id) == ["commit"])
    }

    // MARK: - Cosine wiring via `FakeEmbedder`

    @Test func semanticQueryWithNoKeywordOverlapSurfacesTheEmbeddedMatch() async throws {
        let alpha = SkillMetadata(
            id: "alpha", description: "Handles repository snapshot creation.", isModelVisible: true)
        let beta = SkillMetadata(
            id: "beta", description: "Reports current working tree status.", isModelVisible: true)
        let query = "save my work"

        let embedder = FakeEmbedder(
            dimension: 2,
            vectorsByText: [
                query: [1, 0],
                alpha.renderBlock(): [1, 0],
                beta.renderBlock(): [0, 1],
            ])

        let searcher = await MetadataSearcher(items: [alpha, beta], embedder: embedder)
        let agent = SkillSearchAgent(searcher: searcher)

        let matches = try await agent.search(query: query, limit: 5)
        #expect(matches.first?.id == "alpha")
    }

    // MARK: - Surface-aware `update(items:)` (^49at4v3)

    @Test func aUserSurfaceAgentKeepsDeployAndDropsLintAfterUpdate() async throws {
        // `deploy` is model-hidden (`disable-model-invocation: true`) but
        // user-invocable; `lint` is the reverse (`user-invocable: false`,
        // fully model-visible). A user-surface agent's `update(items:)`
        // must therefore keep `deploy` and drop `lint` -- the opposite of
        // the default model-surface filter.
        let deploy = SkillMetadata(id: "deploy", description: "Deploys the app.", isModelVisible: false)
        let lint = SkillMetadata(id: "lint", description: "Lints the code.", isModelVisible: true)
        let searcher = MetadataSearcher(items: [SkillMetadata]())
        let userVisibleIDs: Set<String> = ["deploy"]
        let agent = SkillSearchAgent(searcher: searcher, visibilityPredicate: { userVisibleIDs.contains($0.id) })

        await agent.update(items: [deploy, lint])

        let deployMatches = try await agent.search(query: "deploy", limit: 10)
        #expect(deployMatches.map(\.id) == ["deploy"])
        let lintMatches = try await agent.search(query: "lint", limit: 10)
        #expect(lintMatches.isEmpty)
    }

    @Test func aModelSurfaceAgentKeepsLintAndDropsDeployAfterUpdate() async throws {
        // The default filter (no `visibilityPredicate` supplied) is the
        // model surface -- the mirror image of the user-surface case above.
        let deploy = SkillMetadata(id: "deploy", description: "Deploys the app.", isModelVisible: false)
        let lint = SkillMetadata(id: "lint", description: "Lints the code.", isModelVisible: true)
        let searcher = MetadataSearcher(items: [SkillMetadata]())
        let agent = SkillSearchAgent(searcher: searcher)

        await agent.update(items: [deploy, lint])

        let lintMatches = try await agent.search(query: "lint", limit: 10)
        #expect(lintMatches.map(\.id) == ["lint"])
        let deployMatches = try await agent.search(query: "deploy", limit: 10)
        #expect(deployMatches.isEmpty)
    }

    // MARK: - `update(items:)` round trip

    @Test func updateItemsMakesANewIdSearchableAndDropsARemovedIdWhileFilteringModelHidden() async throws {
        let alpha = SkillMetadata(id: "alpha", description: "Handles alpha workflow tasks.", isModelVisible: true)
        let beta = SkillMetadata(id: "beta", description: "Handles beta workflow tasks.", isModelVisible: false)
        let gamma = SkillMetadata(id: "gamma", description: "Handles gamma workflow tasks.", isModelVisible: true)

        let searcher = MetadataSearcher(items: [alpha])
        let agent = SkillSearchAgent(searcher: searcher)

        let before = try await agent.search(query: "alpha", limit: 10)
        #expect(before.map(\.id) == ["alpha"])

        // Catalog change: `alpha` removed, model-hidden `beta` and
        // model-visible `gamma` added -- `update(items:)` receives the
        // FULL, unfiltered set, mirroring a real registry reload.
        await agent.update(items: [beta, gamma])

        let afterAlpha = try await agent.search(query: "alpha", limit: 10)
        #expect(afterAlpha.isEmpty)

        let afterGamma = try await agent.search(query: "gamma", limit: 10)
        #expect(afterGamma.map(\.id) == ["gamma"])

        let afterBeta = try await agent.search(query: "beta", limit: 10)
        #expect(afterBeta.isEmpty)
    }
}
