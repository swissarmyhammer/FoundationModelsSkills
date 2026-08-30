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
/// Every case is GPU-free. The selection cases use an `AgentSession` double,
/// and the cosine case uses a `TextEmbedding` double.
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

    // MARK: - Retrieval only, no session

    @Test func theNoSessionFactoryRanksTheFixtureCatalogWithNoModel() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())

        let ids = try await Self.searchIDs(through: tool, query: Self.alignedSkillID)

        #expect(ids.first == Self.alignedSkillID)
    }

    // MARK: - The injected session backs selection

    @Test func theInjectedSessionFactoryIsTheOneThatBacksSelection() async throws {
        let session = RecordingAgentSession(answer: Self.selectionAnswer)

        let tool = try await SkillsTool.make(
            registry: Self.makeFixtureRegistry(), session: { _ in session })
        let ids = try await Self.searchIDs(through: tool, query: "anything at all")

        #expect(session.respondCallCount == 1)
        #expect(ids == [Self.alignedSkillID])
    }

    @Test func theInjectedLiveSessionIsTheOneThatBacksSelection() async throws {
        let session = RecordingAgentSession(answer: Self.selectionAnswer)

        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry(), session: session)
        let ids = try await Self.searchIDs(through: tool, query: "anything at all")

        #expect(session.respondCallCount == 1)
        #expect(ids == [Self.alignedSkillID])
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

    // MARK: - Fixture assembly

    /// Builds a registry over the `Examples/skill-library` fixture stack.
    ///
    /// - Returns: The registry every case in this suite hands to a factory.
    private static func makeFixtureRegistry() -> SkillsRegistry {
        SkillsRegistry(stack: FixtureLibrary.stack())
    }

    /// The answer both `AgentSession` doubles give: the selection tier reads
    /// it as the ids it must return.
    private static let selectionAnswer = #"{"ids":["\#(alignedSkillID)"]}"#

    // MARK: - Dispatch

    /// Dispatches one `search skill` operation through `tool` and gives back
    /// the ranked ids.
    ///
    /// Follows the dispatch pattern in `SkillOperationsTests`, but decodes
    /// the returned JSON instead of matching text in it. `AnyOperation`
    /// encodes with `JSONEncoder.OutputFormatting.sortedKeys`, thus the key
    /// order in the text does not follow the declaration order, and a
    /// decoded value is the only stable way to read the rank order.
    ///
    /// - Parameters:
    ///   - tool: The assembled `skills` tool to dispatch through.
    ///   - query: The search query.
    /// - Returns: The matching skill ids, best first.
    /// - Throws: Whatever `OperationTool.call(arguments:)` or the JSON
    ///   decode throws.
    private static func searchIDs(
        through tool: OperationTool<SkillsToolContext>, query: String
    ) async throws -> [String] {
        let json = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "search skill", "query": query]))
        let response = try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8))
        return response.matches.map(\.id)
    }

    /// One `search skill` result, as this suite reads it back.
    ///
    /// A decode-side mirror of `SearchSkillResult`, which is `Encodable`
    /// only. It names the one field these cases assert on.
    private struct SearchResponse: Decodable {
        /// One ranked row.
        struct Row: Decodable {
            /// The skill's canonical id.
            let id: String
        }

        /// The ranked rows, best first.
        let matches: [Row]
    }

    // MARK: - AgentSession double

    /// An `AgentSession` double that counts every call and always gives one
    /// fixed answer.
    ///
    /// Different from `HotReloadTests`' own scripted double, which answers
    /// from an ordered list and counts nothing. These cases must show that
    /// the session the host gave to the factory is the session that ran,
    /// thus this double makes its own call count readable.
    ///
    /// Uses the protocol default `fork()`, which gives back `self`. Thus a
    /// forked child records its calls on the same counter.
    ///
    /// `final class ... @unchecked Sendable`: the call count changes across
    /// an `await` boundary, thus `lock` holds it.
    private final class RecordingAgentSession: AgentSession, @unchecked Sendable {
        private let answer: String
        private let lock = NSLock()
        private var calls = 0

        /// Creates a double that gives `answer` for every prompt.
        ///
        /// - Parameter answer: The text every `respond(to:)` call gives
        ///   back. The selection tier reads it as JSON, thus it must carry
        ///   the ids the case expects.
        init(answer: String) {
            self.answer = answer
        }

        /// How many times `respond(to:)` has run.
        var respondCallCount: Int {
            lock.withLock { calls }
        }

        func respond(to prompt: String) async throws -> String {
            lock.withLock { calls += 1 }
            return answer
        }
    }

    // MARK: - TextEmbedding double

    /// A deterministic `TextEmbedding` double with two axes.
    ///
    /// A text that holds one of `alignedMarkers` embeds to `alignedVector`.
    /// Every other text embeds to `orthogonalVector`. The two vectors are
    /// orthogonal, thus the cosine similarity between an aligned query and
    /// an aligned item is `1`, and the similarity between an aligned query
    /// and every other item is `0`. A score of `0` does not rank, thus the
    /// aligned item is the only match the cosine signal can give.
    private struct AxisAlignedEmbedder: TextEmbedding {
        /// The vector every text that holds an aligned marker embeds to.
        private static let alignedVector: [Float] = [1, 0]

        /// The vector every other text embeds to.
        private static let orthogonalVector: [Float] = [0, 1]

        /// The texts that embed to `alignedVector`. A text counts as aligned
        /// when it holds one of these as a substring.
        let alignedMarkers: [String]

        /// The length of every vector this double makes: both
        /// `alignedVector` and `orthogonalVector` hold two elements.
        let dimension = AxisAlignedEmbedder.alignedVector.count

        func embed(_ texts: [String]) async throws -> [[Float]] {
            texts.map { text in
                let isAligned = alignedMarkers.contains { text.contains($0) }
                return isAligned ? Self.alignedVector : Self.orthogonalVector
            }
        }
    }
}
