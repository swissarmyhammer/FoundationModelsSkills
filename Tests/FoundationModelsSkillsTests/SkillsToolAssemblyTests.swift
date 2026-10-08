import Foundation
import FoundationModels
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the one-call `SkillsTool` factories in
/// `Operations/SkillsToolAssembly.swift`.
///
/// Each factory does the four assembly steps a host had to write itself
/// before: read the registry metadata, keep the visible subset, build the
/// `MetadataSearcher`, wrap it in a `SkillSearchAgent`, and give the
/// resulting `SkillsToolContext` to `SkillsTool.make(context:)`. These tests
/// drive the assembled tool through `tool.call(arguments:)`, the same way a
/// model does, thus they show the whole assembly, not only its parts.
///
/// Every case is GPU-free. The selection cases use a `ScriptedLanguageModel`,
/// and the cosine case uses a `PooledEmbedding` double.
struct SkillsToolAssemblyTests {
    // MARK: - Constants

    /// A query with no keyword and no trigram overlap with any fixture
    /// skill.
    ///
    /// The retrieval tier ranks a document only when at least one signal
    /// scores it above zero. Thus this query gives no match at all until an
    /// embedder makes the cosine signal score something.
    private static let cosineOnlyQuery = "xqzjvw"

    /// The fixture skill the cosine and selection doubles both point at.
    private static let alignedSkillID = "commit"

    /// The fixture skill that carries `disable-model-invocation: true`, thus
    /// the default visibility predicate must hide it.
    private static let modelHiddenSkillID = "deploy"

    // MARK: - Retrieval only, no model

    @Test func theNoModelFactoryRanksTheFixtureCatalogWithNoModel() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())

        let ids = try await Self.searchIDs(through: tool, query: Self.alignedSkillID)

        #expect(ids.first == Self.alignedSkillID)
    }

    // MARK: - The injected model backs selection

    @Test func theInjectedModelIsTheOneThatBacksSelection() async throws {
        let model = ScriptedLanguageModel(Self.selectionAnswer)

        let tool = try await SkillsTool.make(
            registry: Self.makeFixtureRegistry(), model: model)
        let ids = try await Self.searchIDs(through: tool, query: Self.anyQuery)

        #expect(model.calls.count == 1)
        #expect(ids == [Self.alignedSkillID])
    }

    // MARK: - The candidates are the visible skills

    /// Shows that the instructions of the selection session name each
    /// visible skill as a candidate, and do not name the model-hidden skill.
    @Test func theSelectionInstructionsNameOnlyTheVisibleCandidates() async throws {
        let registry = Self.makeFixtureRegistry()
        let visibleIDs = registry.metadata().filter(\.isModelVisible).map(\.id)
        let model = ScriptedLanguageModel(Self.selectionAnswer)

        let tool = try await SkillsTool.make(registry: registry, model: model)
        _ = try await Self.searchIDs(through: tool, query: Self.anyQuery)

        let call = try #require(model.calls.first)
        let instructions = try #require(call.instructions)
        #expect(model.calls.count == 1)
        for id in visibleIDs {
            #expect(instructions.contains(Self.candidateLine(for: id)))
        }
        #expect(!instructions.contains(Self.candidateLine(for: Self.modelHiddenSkillID)))
    }

    // MARK: - One bad answer does not fail the call

    /// Shows that a selection answer with the wrong shape gives the
    /// retrieval rank, not a failed `skills` call.
    ///
    /// The model answers `[commit]`: the correct skill, in the shape a small
    /// model wrote in the SWE-bench run, not `{"ids": ["commit"]}`. The
    /// decode of that answer throws. The search must then give the same rank
    /// as the keyword-only factory, and the model must have been asked, or
    /// the case proves nothing about the fallback.
    @Test func aBareIDListAnswerGivesTheRetrievalRankNotAFailedCall() async throws {
        let registry = Self.makeFixtureRegistry()
        let model = ScriptedLanguageModel(Self.bareIDListAnswer)

        let selectionTool = try await SkillsTool.make(registry: registry, model: model)
        let retrievalTool = try await SkillsTool.make(registry: registry)
        let fallbackIDs = try await Self.searchIDs(through: selectionTool, query: Self.keywordQuery)
        let retrievalIDs = try await Self.searchIDs(through: retrievalTool, query: Self.keywordQuery)

        #expect(model.calls.count == 1)
        #expect(fallbackIDs.first == Self.alignedSkillID)
        #expect(fallbackIDs == retrievalIDs)
    }

    /// Shows that a model that fails for another reason also gives the
    /// retrieval rank, not a failed `skills` call.
    @Test func aModelThatThrowsGivesTheRetrievalRankNotAFailedCall() async throws {
        let registry = Self.makeFixtureRegistry()

        let selectionTool = try await SkillsTool.make(
            registry: registry, model: ScriptedLanguageModel.failing)
        let retrievalTool = try await SkillsTool.make(registry: registry)
        let fallbackIDs = try await Self.searchIDs(through: selectionTool, query: Self.keywordQuery)
        let retrievalIDs = try await Self.searchIDs(through: retrievalTool, query: Self.keywordQuery)

        #expect(fallbackIDs.first == Self.alignedSkillID)
        #expect(fallbackIDs == retrievalIDs)
    }

    // MARK: - The result tells the model what to do next

    /// Shows that the answer names the exact `skills` call that loads the
    /// first match: the op of `use skill` and the id of the match.
    @Test func theAnswerNamesTheUseCallOfTheFirstMatch() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())

        let answer = try await Self.searchText(through: tool, query: Self.keywordQuery)

        let firstID = try #require(
            SkillLineReader.ids(in: answer).first, "the query must give a match, or this case proves nothing")
        #expect(answer.contains(#"For example: {"op": "\#(Self.useSkillOp)", "id": "\#(firstID)"}"#))
    }

    /// Shows that the call the answer names, sent back to the tool, gives
    /// the body of that skill.
    @Test func theUseCallOfAMatchResolvesToUseSkillForThatID() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())

        let answer = try await Self.searchText(through: tool, query: Self.noArgumentSkillID)
        let firstID = try #require(SkillLineReader.ids(in: answer).first)
        let loaded = try await Self.use(through: tool, op: Self.useSkillOp, id: firstID)

        #expect(firstID == Self.noArgumentSkillID)
        #expect(loaded == (try await Self.makeFixtureRegistry().call(id: Self.noArgumentSkillID)))
    }

    /// Shows that a result with a match tells the model to load each skill
    /// that helps with its task.
    @Test func aRetrievalResultWithAMatchCarriesTheLoadInstruction() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())

        let answer = try await Self.searchText(through: tool, query: Self.keywordQuery)

        #expect(answer.hasSuffix(Self.loadInstructionLastLine))
    }

    /// Shows that a first match the selection tier chose comes back as a
    /// line, and that the answer holds no body, although `use skill` renders
    /// that skill with no argument.
    @Test func aSelectionAnswerGivesTheChosenLineAndNoBody() async throws {
        let model = ScriptedLanguageModel(Self.idsAnswer(for: Self.noArgumentSkillID))
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry(), model: model)

        let answer = try await Self.searchText(through: tool, query: Self.anyQuery)
        let body = try await Self.use(through: tool, op: Self.useSkillOp, id: Self.noArgumentSkillID)

        #expect(SkillLineReader.ids(in: answer) == [Self.noArgumentSkillID])
        #expect(!answer.contains(body))
        #expect(answer.hasSuffix(Self.loadInstructionLastLine))
    }

    /// Shows that an answer of the retrieval fallback gives the retrieval
    /// rank and the load instruction.
    @Test func aRetrievalFallbackAnswerGivesTheLoadInstruction() async throws {
        let model = ScriptedLanguageModel(Self.bareIDListAnswer)
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry(), model: model)

        let answer = try await Self.searchText(through: tool, query: Self.keywordQuery)

        #expect(model.calls.count == 1)
        #expect(SkillLineReader.ids(in: answer).first == Self.alignedSkillID)
        #expect(answer.hasSuffix(Self.loadInstructionLastLine))
    }

    // MARK: - An empty catalog asks the model nothing

    /// Shows that `search skill` over a stack with no skill answers a
    /// corrective, and that it does not send a prompt to the model.
    ///
    /// The factory builds the searcher in `.auto` mode with a selection
    /// tier, thus the search takes the selection branch, as in production.
    /// The model answers prose, as the real model did when it got an empty
    /// candidate list. If the search reached the model, the decode of that
    /// prose would throw, and the call would fail.
    @Test func searchOverAnEmptyStackAnswersACorrectiveAndSendsNoPrompt() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ScriptedLanguageModel(Self.proseAnswer)

        let tool = try await SkillsTool.make(registry: SkillsRegistry(roots: [root]), model: model)
        let answer = try await Self.searchText(through: tool, query: Self.anyQuery)

        #expect(answer == "No skills are available.")
        #expect(model.calls.count == 0)
    }

    // MARK: - The embedder reaches the searcher

    /// Shows that a non-`nil` `embedder` reaches the searcher, and that its
    /// cosine signal is non-zero in a match.
    ///
    /// The proof is a pair. `cosineOnlyQuery` has no keyword and no trigram
    /// overlap, thus the same factory with no embedder gives no match. The
    /// same factory with the double gives exactly the aligned skill. Only
    /// the cosine signal can make that difference, thus the `embedder:`
    /// parameter the `async` signature exists for is honored.
    @Test func theEmbedderReachesTheSearcherAndItsCosineSignalRanksAMatch() async throws {
        let registry = Self.makeFixtureRegistry()
        let embedder = AxisAlignedEmbedder(
            alignedMarkers: [Self.alignedSkillID, Self.cosineOnlyQuery])

        let withoutEmbedder = try await SkillsTool.make(registry: registry)
        let withEmbedder = try await SkillsTool.make(registry: registry, embedder: embedder)
        let keywordOnlyIDs = try await Self.searchIDs(through: withoutEmbedder, query: Self.cosineOnlyQuery)
        let cosineIDs = try await Self.searchIDs(through: withEmbedder, query: Self.cosineOnlyQuery)

        #expect(keywordOnlyIDs.isEmpty)
        #expect(cosineIDs == [Self.alignedSkillID])
    }

    // MARK: - The default visibility predicate

    @Test func theDefaultVisibilityPredicateKeepsAModelHiddenSkillOutOfTheResults() async throws {
        let registry = Self.makeFixtureRegistry()
        #expect(
            registry.metadata().contains { $0.id == Self.modelHiddenSkillID },
            "the fixture catalog must still carry the model-hidden skill, or this case proves nothing")

        let tool = try await SkillsTool.make(registry: registry)
        let ids = try await Self.searchIDs(through: tool, query: Self.modelHiddenSkillID)

        #expect(!ids.contains(Self.modelHiddenSkillID))
    }

    // MARK: - The operation surface does not change

    /// The operations of the fused tool, in the order `SkillsTool.make`
    /// lists them. The marketplace does not change the model surface.
    private static let expectedOperationNames = [
        "search skill", "list skill", "use skill", "list resource", "read resource", "run script",
    ]

    /// The parameter names of each operation of the fused tool, keyed by the
    /// operation name.
    private static let expectedParameterNames: [String: [String]] = [
        "search skill": ["query", "limit"],
        "list skill": ["filter"],
        "use skill": ["id", "arguments"],
        "list resource": ["id"],
        "read resource": ["id", "path", "start", "end"],
        "run script": ["id", "path", "arguments", "timeout"],
    ]

    @Test func theMarketplaceSourceTextLeavesTheOperationNamesAndParametersAlone() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())

        #expect(tool.operations.map(\.opString) == Self.expectedOperationNames)
        let parameterNames = Dictionary(
            uniqueKeysWithValues: tool.operations.map { ($0.opString, $0.parameters.map(\.name)) })
        #expect(parameterNames == Self.expectedParameterNames)
    }

    // MARK: - Fixture assembly

    /// Builds a registry over the `Examples/skill-library` fixture stack.
    ///
    /// - Returns: The registry every case in this suite hands to a factory.
    private static func makeFixtureRegistry() -> SkillsRegistry {
        SkillsRegistry(stack: FixtureLibrary.stack())
    }

    /// The answer the selection cases give to their `ScriptedLanguageModel`:
    /// the selection tier reads it as the ids it must return.
    private static let selectionAnswer = idsAnswer(for: alignedSkillID)

    /// Makes a selection answer that chooses one skill.
    ///
    /// - Parameter id: The id of the skill the answer chooses.
    /// - Returns: The answer in the `{"ids": [String]}` shape the selection
    ///   tier decodes.
    private static func idsAnswer(for id: String) -> String {
        #"{"ids":["\#(id)"]}"#
    }

    /// A fixture skill that declares no parameter and references no
    /// argument, thus `use skill` renders its body with no argument at all.
    private static let noArgumentSkillID = "lint"

    /// The op of the `use skill` operation, as a model writes it.
    private static let useSkillOp = "use skill"

    /// The last line of the load instruction of an answer with a match.
    private static let loadInstructionLastLine =
        "If a skill in this list helps with any part of your task, load it now, and do the work "
        + "the way it says. Load each skill that helps. More than one can apply. Search again "
        + "when the work changes."

    /// A prose answer that is not JSON: the shape the real model gave when
    /// the selection prompt held no candidate.
    private static let proseAnswer = "There are no candidates to choose from."

    /// A bare list of the correct id, with no quotes and no `ids` object: the
    /// shape a small model gave in the SWE-bench run, which does not decode.
    private static let bareIDListAnswer = "[\(alignedSkillID)]"

    /// A query whose keywords rank `alignedSkillID` first in the retrieval
    /// tier, as `ReadmeExampleTests` and the `skills-demo` CLI case show.
    private static let keywordQuery = "commit my changes"

    /// A query for the cases whose selection double answers the same ids for
    /// every prompt, thus the words of the query do not matter.
    private static let anyQuery = "anything at all"

    // MARK: - Reading the instructions back

    /// The line that holds `id` in the `<candidate>` block of the selection
    /// instructions.
    ///
    /// - Parameter id: The id of the candidate.
    /// - Returns: The `id:` line of that candidate, with its newlines.
    private static func candidateLine(for id: String) -> String {
        "\nid: \(id)\n"
    }

    // MARK: - Dispatch

    /// Dispatches one `search skill` operation through `tool` and gives back
    /// the ranked ids.
    ///
    /// Follows the dispatch pattern in `SkillOperationsTests`, and reads the
    /// ids from the plain lines of the answer, in rank order.
    ///
    /// - Parameters:
    ///   - tool: The assembled `skills` tool to dispatch through.
    ///   - query: The search query.
    /// - Returns: The matching skill ids, best first.
    /// - Throws: Whatever `SkillsCatalogTool.call(arguments:)` throws.
    private static func searchIDs(
        through tool: SkillsCatalogTool, query: String
    ) async throws -> [String] {
        SkillLineReader.ids(in: try await searchText(through: tool, query: query))
    }

    /// Dispatches one `search skill` operation through `tool` and gives back
    /// the plain text of the answer.
    ///
    /// - Parameters:
    ///   - tool: The assembled `skills` tool to dispatch through.
    ///   - query: The search query.
    /// - Returns: The text the tool gives the model.
    /// - Throws: Whatever `SkillsCatalogTool.call(arguments:)` throws.
    private static func searchText(
        through tool: SkillsCatalogTool, query: String
    ) async throws -> String {
        try await tool.call(arguments: GeneratedContent(properties: ["op": "search skill", "query": query]))
    }

    /// Dispatches one `use` call through `tool`, as a model sends it, and
    /// gives back the answer: the rendered body as plain text.
    ///
    /// - Parameters:
    ///   - tool: The assembled `skills` tool to dispatch through.
    ///   - op: The op of the call.
    ///   - id: The id of the skill to use.
    /// - Returns: The text the tool gives the model.
    /// - Throws: Whatever `SkillsCatalogTool.call(arguments:)` throws.
    private static func use(
        through tool: SkillsCatalogTool, op: String, id: String
    ) async throws -> String {
        try await tool.call(arguments: GeneratedContent(properties: ["op": op, "id": id]))
    }

    // MARK: - PooledEmbedding double

    /// A deterministic `PooledEmbedding` double with two axes.
    ///
    /// A text that holds one of `alignedMarkers` embeds to `alignedVector`.
    /// Every other text embeds to `orthogonalVector`. The two vectors are
    /// orthogonal, thus the cosine similarity between an aligned query and
    /// an aligned item is `1`, and the similarity between an aligned query
    /// and every other item is `0`. A score of `0` does not rank, thus the
    /// aligned item is the only match the cosine signal can give.
    private struct AxisAlignedEmbedder: PooledEmbedding {
        /// The vector every text that holds an aligned marker embeds to.
        private static let alignedVector: [Float] = [1, 0]

        /// The vector every other text embeds to.
        private static let orthogonalVector: [Float] = [0, 1]

        /// The texts that embed to `alignedVector`. A text counts as aligned
        /// when it holds one of these as a substring.
        let alignedMarkers: [String]

        func embed(texts: [String]) async throws -> [[Float]] {
            texts.map { text in
                let isAligned = alignedMarkers.contains { text.contains($0) }
                return isAligned ? Self.alignedVector : Self.orthogonalVector
            }
        }
    }
}
