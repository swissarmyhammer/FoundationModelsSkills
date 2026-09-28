import FoundationModelsMetadataRegistry
import Logging
import Testing

@testable import FoundationModelsSkills

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

    /// A model-visible skill that the `update(items:)` and fallback cases
    /// start from.
    private static let alphaSkill = SkillMetadata(
        id: "alpha", description: "Handles alpha workflow tasks.", isModelVisible: true)

    /// A model-visible skill that the `update(items:)` and fallback cases add.
    private static let gammaSkill = SkillMetadata(
        id: "gamma", description: "Handles gamma workflow tasks.", isModelVisible: true)

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
        let alpha = Self.alphaSkill
        let beta = SkillMetadata(id: "beta", description: "Handles beta workflow tasks.", isModelVisible: false)
        let gamma = Self.gammaSkill

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

    // MARK: - Retrieval fallback

    /// Shows that a searcher failure goes to the caller when the agent has
    /// no retrieval fallback.
    ///
    /// A searcher in `.selection` mode with no selection tier throws
    /// `SelectionTierUnavailable` on each search, with no session and no
    /// model. Thus it is the failing searcher of these cases.
    @Test func anAgentWithNoRetrievalFallbackGivesTheSearcherFailureToTheCaller() async throws {
        let alpha = Self.alphaSkill
        let agent = SkillSearchAgent(searcher: MetadataSearcher(items: [alpha], mode: .selection))

        await #expect(throws: SelectionTierUnavailable.self) {
            try await agent.search(query: "alpha", limit: 10)
        }
    }

    /// Shows that the retrieval fallback ranks the query when the searcher
    /// fails, and that `update(items:)` reaches the fallback too.
    ///
    /// Both searchers start over `alpha`. The update adds `gamma`, and only
    /// the fallback can rank a search, thus a `gamma` match proves that the
    /// update reached the fallback.
    @Test func theRetrievalFallbackRanksTheQueryWhenTheSearcherFailsAndFollowsUpdates() async throws {
        let alpha = Self.alphaSkill
        let gamma = Self.gammaSkill
        let agent = SkillSearchAgent(
            searcher: MetadataSearcher(items: [alpha], mode: .selection),
            retrievalFallback: MetadataSearcher(items: [alpha], mode: .retrieval))

        let before = try await agent.search(query: "alpha", limit: 10)
        await agent.update(items: [alpha, gamma])
        let after = try await agent.search(query: "gamma", limit: 10)

        #expect(before.map(\.id) == ["alpha"])
        #expect(after.map(\.id) == ["gamma"])
    }

    // MARK: - Which tier gave the answer

    /// Shows that an answer of a searcher in `.retrieval` mode does not
    /// claim the selection tier.
    @Test func aRetrievalRankIsNotASelection() async throws {
        let agent = SkillSearchAgent(searcher: MetadataSearcher(items: [Self.alphaSkill], mode: .retrieval))

        let answer = try await agent.answer(query: "alpha", limit: 10)

        #expect(answer.matches.map(\.id) == ["alpha"])
        #expect(!answer.isSelection)
    }

    /// Shows that an answer of the retrieval fallback does not claim the
    /// selection tier, although the wrapped searcher is in `.selection`
    /// mode.
    @Test func aRetrievalFallbackAnswerIsNotASelection() async throws {
        let agent = SkillSearchAgent(
            searcher: MetadataSearcher(items: [Self.alphaSkill], mode: .selection),
            retrievalFallback: MetadataSearcher(items: [Self.alphaSkill], mode: .retrieval))

        let answer = try await agent.answer(query: "alpha", limit: 10)

        #expect(answer.matches.map(\.id) == ["alpha"])
        #expect(!answer.isSelection)
    }

    // MARK: - The log record of a fallback

    /// Shows that a fallback writes one log record, and that the record holds
    /// the error type and no content.
    ///
    /// The error description and the query both hold `contentMarker`. The
    /// description of a selection error can hold the query or the model
    /// response, thus the record must hold neither: a fixed message, and the
    /// error type in the metadata.
    @Test func aFallbackLogsOneRecordWithTheErrorTypeAndNoContent() async throws {
        let recorder = Recorder<LogRecord>()
        let agent = SkillSearchAgent(
            searcher: MetadataSearcher(
                items: [Self.alphaSkill], mode: .selection,
                selection: SelectionConfig(model: { _ in ContentThrowingSession() })),
            retrievalFallback: MetadataSearcher(items: [Self.alphaSkill], mode: .retrieval),
            visibilityPredicate: { $0.isModelVisible },
            logger: Logger(label: SkillsTracing.LoggerLabel.search) { _ in
                RecordingLogHandler(recorder: recorder)
            })

        let answer = try await agent.answer(query: "alpha \(Self.contentMarker)", limit: 10)

        let records = recorder.recorded
        #expect(answer.matches.map(\.id) == ["alpha"])
        #expect(records.count == 1)
        #expect(
            records.first?.metadata[SkillsTracing.MetadataKey.errorType]
                == .string(String(reflecting: ContentThrowingSession.ContentError.self)))
        #expect(records.allSatisfy { !$0.holds(Self.contentMarker) })
    }

    /// The text that the error description and the query of the fallback case
    /// hold, and that no log record may hold.
    private static let contentMarker = "QUERY-AND-RESPONSE-CONTENT-7f3c"

    /// An `AgentSession` double whose every call throws an error, and whose
    /// error description holds `contentMarker`, as the description of a
    /// selection error can hold the query or the model response.
    private struct ContentThrowingSession: AgentSession {
        /// The error every call of this double throws.
        struct ContentError: Error, CustomStringConvertible {
            /// The description of the error: the content marker.
            var description: String {
                "the model answered: \(SkillSearchAgentTests.contentMarker)"
            }
        }

        func respond(to prompt: String) async throws -> String {
            throw ContentError()
        }
    }

    /// One log record that `RecordingLogHandler` recorded.
    private struct LogRecord: Sendable {
        /// The message of the record.
        let message: String

        /// The merged metadata of the record: the handler metadata and the
        /// metadata of the call.
        let metadata: Logger.Metadata

        /// The description of the error that the event carried, or `nil` when
        /// it carried no error. A backend can write that description, thus it
        /// is content too.
        let errorDescription: String?

        /// Tells whether the message, a metadata value or the error of the
        /// event holds `text`.
        ///
        /// - Parameter text: The text to find.
        /// - Returns: `true` when the message, the description of a metadata
        ///   value, or the description of the error holds `text`.
        func holds(_ text: String) -> Bool {
            message.contains(text)
                || metadata.values.contains { $0.description.contains(text) }
                || errorDescription?.contains(text) == true
        }
    }

    /// A `LogHandler` that gives each log record to a `Recorder`.
    private struct RecordingLogHandler: LogHandler {
        /// Where each record goes.
        let recorder: Recorder<LogRecord>

        var metadata: Logger.Metadata = [:]

        var logLevel: Logger.Level = .trace

        subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get { metadata[key] }
            set { metadata[key] = newValue }
        }

        func log(event: LogEvent) {
            let merged = metadata.merging(event.metadata ?? [:]) { _, call in call }
            recorder.record(
                LogRecord(
                    message: event.message.description, metadata: merged,
                    errorDescription: event.error.map { String(describing: $0) }))
        }
    }
}
