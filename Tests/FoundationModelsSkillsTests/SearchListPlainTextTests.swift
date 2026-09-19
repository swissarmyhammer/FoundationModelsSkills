import FoundationModels
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the answers of `search skill` and `list skill` through the fused
/// `skills` tool.
///
/// A model reads each answer as plain text. The answer gives one line for
/// each skill, `- <id>: <description>`, and then the load instruction. The
/// instruction names the exact `use skill` call. The answer holds no JSON
/// object, no `use` field, no `next` field, and no body.
struct SearchListPlainTextTests {
    // MARK: - Constants

    /// Each op spelling of the `search skill` operation that a model can
    /// write: the canonical op and its `find` and `discover` aliases.
    private static let searchSkillOps = ["search skill", "skill_find", "skill_discover"]

    /// The ids the selection double chooses, in its rank order. The order is
    /// not the catalog order, thus a case that keeps it shows the rank order.
    private static let selectedIDs = ["lint", "commit"]

    /// A query for the cases whose selection double answers the same ids for
    /// every prompt, thus the words of the query do not matter.
    private static let anyQuery = "check my code before I commit"

    /// A query with no keyword and no trigram overlap with any fixture
    /// skill, thus the retrieval tier gives no match.
    private static let noMatchQuery = "xqzjvw"

    /// A `list skill` filter that no fixture id or description holds.
    private static let noMatchFilter = "no-such-skill-exists"

    /// The fixture skill with no required argument: `use skill` renders its
    /// body with no argument at all.
    private static let noArgumentSkillID = "lint"

    /// The answer of a search with no match, word for word from the card.
    private static let noMatchAnswer = "No skill matches this search."

    /// The answer of a filtered list with no match.
    private static let noFilterMatchAnswer = "No skill matches this filter."

    /// The use rule of the tool description, word for word from the card.
    private static let descriptionUseRule =
        #"When a task matches a skill below, load it: call this tool with {"op": "use skill", "id": "<id>"}. "#
        + "The answer is the text of the skill. Do the work the way it says."

    /// The first sentence of the tool description, which does not change.
    private static let descriptionPurpose =
        "Skills are procedures for kinds of work. Each one tells you how to do the work and which tools to use."

    // MARK: - search skill with matches

    @Test(arguments: searchSkillOps)
    func aSearchWithMatchesGivesTheQueryLineTheRankedLinesAndTheLoadInstruction(op: String) async throws {
        let registry = Self.makeFixtureRegistry()
        let tool = try await Self.makeSelectionTool(registry: registry)

        let answer = try await tool.call(arguments: GeneratedContent(properties: ["op": op, "query": Self.anyQuery]))

        #expect(
            answer
                == "Skills that match \"\(Self.anyQuery)\":\n\n"
                + Self.skillLines(ids: Self.selectedIDs, in: registry) + "\n\n"
                + Self.loadInstruction(exampleID: Self.selectedIDs[0]))
    }

    @Test func performGivesTheSameSearchText() async throws {
        let tool = try await Self.makeSelectionTool(registry: Self.makeFixtureRegistry())
        let arguments = GeneratedContent(properties: ["op": "search skill", "query": Self.anyQuery])

        let performed = try await tool.perform(arguments)
        let called = try await tool.call(arguments: arguments)

        #expect(performed == called)
    }

    @Test func theSearchResultHoldsNoBodyAndNoJSON() async throws {
        let registry = Self.makeFixtureRegistry()
        let tool = try await Self.makeSelectionTool(registry: registry)
        let body = try registry.call(id: Self.noArgumentSkillID)

        let answer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "search skill", "query": Self.anyQuery]))

        #expect(!answer.contains(body))
        #expect(!answer.hasPrefix("{"))
        #expect(!answer.hasPrefix("\""))
        #expect(!answer.contains(#""matches""#))
        #expect(!answer.contains(#""next""#))
        #expect(!answer.contains(#""use""#))
        #expect(!answer.contains(#""body""#))
        #expect(!answer.contains("\\n"))
    }

    // MARK: - search skill with no match

    @Test func aSearchWithNoMatchGivesOneLine() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())

        let answer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "search skill", "query": Self.noMatchQuery]))

        #expect(answer == Self.noMatchAnswer)
    }

    // MARK: - list skill

    @Test func listSkillGivesThePlainLinesAndTheLoadInstruction() async throws {
        let registry = Self.makeFixtureRegistry()
        let tool = try await SkillsTool.make(registry: registry)
        let visibleIDs = registry.metadata().filter(\.isModelVisible).map(\.id)

        let answer = try await tool.call(arguments: GeneratedContent(properties: ["op": "list skill"]))

        #expect(
            answer
                == Self.skillLines(ids: visibleIDs, in: registry) + "\n\n"
                + Self.loadInstruction(exampleID: visibleIDs[0]))
    }

    @Test func aFilteredListWithNoMatchGivesOneLine() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())

        let answer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "list skill", "filter": Self.noMatchFilter]))

        #expect(answer == Self.noFilterMatchAnswer)
    }

    // MARK: - The tool description

    @Test func theToolDescriptionHoldsTheNewUseRuleWordForWord() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())

        #expect(tool.description.hasPrefix(Self.descriptionPurpose + "\n" + Self.descriptionUseRule + "\n\n"))
    }

    // MARK: - Fixtures

    /// Builds a registry over the `Examples/skill-library` fixture stack.
    ///
    /// - Returns: The registry that the tool and the expected text share.
    private static func makeFixtureRegistry() -> SkillsRegistry {
        SkillsRegistry(stack: FixtureLibrary.stack())
    }

    /// Builds the fused tool with a selection double that chooses
    /// `selectedIDs` for every query.
    ///
    /// - Parameter registry: The registry the tool dispatches against.
    /// - Returns: The fused tool.
    /// - Throws: Whatever `SkillsTool.make(registry:session:)` throws.
    private static func makeSelectionTool(registry: SkillsRegistry) async throws -> SkillsCatalogTool {
        let session = FixedAnswerSession(answer: #"{"ids":["\#(selectedIDs.joined(separator: #"",""#))"]}"#)
        return try await SkillsTool.make(registry: registry, session: { _ in session })
    }

    /// The expected line of each skill in `ids`, in the order of `ids`.
    ///
    /// - Parameters:
    ///   - ids: The skill ids, in the order the answer must give them.
    ///   - registry: The registry that holds the description of each id.
    /// - Returns: One `- <id>: <description>` line for each id.
    private static func skillLines(ids: [String], in registry: SkillsRegistry) -> String {
        let descriptions = Dictionary(uniqueKeysWithValues: registry.metadata().map { ($0.id, $0.description) })
        return ids.map { "- \($0): \(descriptions[$0] ?? "")" }.joined(separator: "\n")
    }

    /// The four lines of the load instruction, word for word from the card.
    ///
    /// - Parameter exampleID: The id of the first skill of the answer.
    /// - Returns: The instruction.
    private static func loadInstruction(exampleID: String) -> String {
        #"To load a skill, call the `skills` tool with {"op": "use skill", "id": "<id>"}."# + "\n"
            + #"For example: {"op": "use skill", "id": "\#(exampleID)"}"# + "\n"
            + "The answer is the text of the skill: the steps of the work and the tools to use.\n"
            + "If a skill in this list fits your task, load it now, and do the work the way it says."
    }

    /// An `AgentSession` double that gives one fixed answer for each prompt.
    private struct FixedAnswerSession: AgentSession {
        /// The text each `respond(to:)` call gives back.
        let answer: String

        func respond(to prompt: String) async throws -> String {
            answer
        }
    }
}
