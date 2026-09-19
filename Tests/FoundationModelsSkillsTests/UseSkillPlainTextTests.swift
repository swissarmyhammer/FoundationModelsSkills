import Foundation
import FoundationModels
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the answer of `use skill` through the fused `skills` tool.
///
/// The model reads the answer as the procedure to follow. Thus the answer is
/// the rendered body of the skill as plain text: no JSON object, no `body`
/// key, no `id` key, and no escape sequences. An error is a plain sentence.
///
/// Each alias of `use skill` gives the same answer. Thus each test runs once
/// for each op spelling in `useSkillOps`.
struct UseSkillPlainTextTests {
    // MARK: - Constants

    /// Each op spelling of the `use skill` operation that a model can write:
    /// the canonical op and its `call`, `invoke`, and `get` aliases.
    private static let useSkillOps = ["use skill", "skill_call", "skill_invoke", "skill_get"]

    /// The fixture skill with one required argument and a body of more than
    /// one line, thus JSON would escape its line breaks.
    private static let commitSkillID = "commit"

    /// The value of the required argument of `commitSkillID`.
    private static let commitMessage = "fix parser"

    /// An id that no fixture skill has.
    private static let unknownSkillID = "totally-made-up"

    /// The key that the old JSON answer used for the rendered body.
    private static let bodyKey = #""body":"#

    /// The key that the old JSON answer used for the skill id.
    private static let idKey = #""id":"#

    // MARK: - The answer is the rendered body

    @Test(arguments: useSkillOps)
    func theAnswerIsTheRenderedBodyCharacterForCharacter(op: String) async throws {
        let registry = Self.makeFixtureRegistry()
        let tool = try Self.makeTool(registry: registry)
        let renderedBody = try registry.call(id: Self.commitSkillID, arguments: [Self.commitMessage])

        let answer = try await tool.call(arguments: Self.useCommitArguments(op: op))

        #expect(answer == renderedBody)
    }

    @Test(arguments: useSkillOps)
    func theAnswerHoldsNoJSONStructureAroundTheBody(op: String) async throws {
        let tool = try Self.makeTool(registry: Self.makeFixtureRegistry())

        let answer = try await tool.call(arguments: Self.useCommitArguments(op: op))

        #expect(!answer.hasPrefix("{"))
        #expect(!answer.hasPrefix("\""))
        #expect(!answer.contains(Self.bodyKey))
        #expect(!answer.contains(Self.idKey))
        #expect(!answer.contains("\\n"))
        #expect(answer.contains("\n"))
    }

    @Test(arguments: useSkillOps)
    func performGivesTheRenderedBodyToo(op: String) async throws {
        let registry = Self.makeFixtureRegistry()
        let tool = try Self.makeTool(registry: registry)
        let renderedBody = try registry.call(id: Self.commitSkillID, arguments: [Self.commitMessage])

        let answer = try await tool.perform(Self.useCommitArguments(op: op))

        #expect(answer == renderedBody)
    }

    // MARK: - An error is a plain sentence

    @Test(arguments: useSkillOps)
    func anUnknownIDGivesAPlainSentenceThatNamesTheValidIDs(op: String) async throws {
        let registry = Self.makeFixtureRegistry()
        let tool = try Self.makeTool(registry: registry)
        let validIDs = registry.metadata().filter(\.isModelVisible).map(\.id).sorted()

        let answer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": op, "id": Self.unknownSkillID]))

        #expect(
            answer
                == "The skill id `\(Self.unknownSkillID)` is not currently usable. "
                + "Currently usable ids: \(validIDs.joined(separator: ", ")).")
    }

    @Test(arguments: useSkillOps)
    func aMissingRequiredArgumentGivesAPlainSentence(op: String) async throws {
        let tool = try Self.makeTool(registry: Self.makeFixtureRegistry())

        let answer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": op, "id": Self.commitSkillID]))

        #expect(answer == "Missing required argument `message` for this skill.")
    }

    // MARK: - Fixtures

    /// Builds a registry over the `project/.skills` fixture root.
    ///
    /// - Returns: The registry that the tool and the expected body share.
    private static func makeFixtureRegistry() -> SkillsRegistry {
        SkillsRegistry(roots: [FixtureLibrary.url(relativePath: "project/.skills")])
    }

    /// Builds the fused `skills` tool over `registry`, with the model-facing
    /// visibility predicate.
    ///
    /// - Parameter registry: The registry the tool dispatches against.
    /// - Returns: The fused tool.
    /// - Throws: Whatever `SkillsTool.make(context:)` throws.
    private static func makeTool(registry: SkillsRegistry) throws -> SkillsCatalogTool {
        try SkillsTool.make(context: FixtureLibrary.makeSkillsToolContext(registry: registry))
    }

    /// The payload that loads `commitSkillID` with `commitMessage`.
    ///
    /// - Parameter op: The op spelling to send.
    /// - Returns: The payload.
    private static func useCommitArguments(op: String) -> GeneratedContent {
        GeneratedContent(properties: ["op": op, "id": commitSkillID, "arguments": [commitMessage]])
    }
}
