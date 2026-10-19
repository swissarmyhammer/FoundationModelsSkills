import Foundation
import FoundationModels
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the catalog that the `skills` tool shows the model: the tool
/// description, the plain `id` field of the fused schema, and the texts of
/// the operations.
///
/// A model sees only the name, the description, and the schema of a tool
/// before it plans. These cases show that the description carries the
/// visible skills, and that no model-hidden skill gets into it. The `id`
/// field is a plain string, thus a skill that a reload adds can be loaded in
/// the same session.
struct SkillsCatalogToolTests {
    // MARK: - Constants

    /// The fixture skill that carries `disable-model-invocation: true`, thus
    /// the default visibility predicate must hide it.
    private static let modelHiddenSkillID = "deploy"

    /// The fixed text at the start of the description, word for word from
    /// the card: what a skill is, the rule to load each skill that helps
    /// with the task, and how to read a file of a skill.
    private static let fixedSentences =
        "Skills are procedures for kinds of work. Each one tells you how to do the work and which tools to use.\n"
        + "Read the skills below before you start. If a skill helps with any part of your task, "
        + #"load it now: call this tool with {"op": "use skill", "id": "<id>"}. "#
        + "Load each skill that helps. More than one can apply. "
        + "The answer is the text of the skill. Do the work the way it says. "
        + "Read this list again when the work changes.\n"
        + "A skill can have files, such as references/guide.md. "
        + #"To read one, call the `skills` tool with {"op": "read resource", "id": "<id>", "#
        + #""path": "<path relative to the skill>"}. "#
        + "The answer of `use skill` lists the files of the skill."

    /// The line the description gives when no skill is visible.
    private static let noSkillsLine = "No skills are installed now."

    /// The name of the fused schema field that holds a skill id.
    private static let idFieldName = "id"

    /// The JSON schema type name of a plain string field.
    private static let stringTypeName = "string"

    /// The skill in the root when the tool is made.
    private static let skillBeforeReload = "alpha"

    /// The skill that a reload adds after the tool is made.
    private static let skillAddedByReload = "bravo"

    // MARK: - The description

    @Test func theDescriptionListsEachVisibleSkillWithItsDescriptionAndNoHiddenOne() async throws {
        let registry = Self.makeFixtureRegistry()
        let visible = registry.metadata().filter(\.isModelVisible)

        let tool = try await SkillsTool.make(registry: registry)

        #expect(tool.description.hasPrefix(Self.fixedSentences))
        for entry in visible {
            #expect(tool.description.contains("- \(entry.id): \(entry.description)"))
        }
        #expect(!tool.description.contains("- \(Self.modelHiddenSkillID)"))
    }

    @Test func theCatalogCharacterLimitReachesTheDescription() async throws {
        let registry = Self.makeFixtureRegistry()
        let visibleIDs = registry.metadata().filter(\.isModelVisible).map(\.id)
        let idLineLength = visibleIDs.joined(separator: ", ").count

        let tool = try await SkillsTool.make(registry: registry, catalogCharacterLimit: idLineLength)

        #expect(tool.description.hasSuffix("\n\n" + visibleIDs.joined(separator: ", ")))
    }

    // MARK: - The id field

    @Test func theIDFieldOfTheSchemaIsAPlainStringForAFullCatalog() async throws {
        let registry = Self.makeFixtureRegistry()
        #expect(!registry.metadata().filter(\.isModelVisible).isEmpty, "the catalog must hold a visible skill")

        let tool = try await SkillsTool.make(registry: registry)
        let idProperty = try Self.property(named: Self.idFieldName, in: tool.parameters)

        #expect(idProperty["enum"] == nil, "a fixed enum would refuse a skill that a reload adds")
        #expect(idProperty["type"] as? String == Self.stringTypeName)
        #expect(idProperty["description"] as? String == "The id of the skill to load.")
    }

    // MARK: - A skill that a reload adds

    @Test func aSkillThatAReloadAddsAfterTheToolIsMadeLoadsThroughTheTool() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: Self.skillBeforeReload, in: root)
        let registry = SkillsRegistry(roots: [root], watch: true)
        let tool = try await SkillsTool.make(registry: registry)
        let tally = ReloadTestSupport.EventTally()
        let subscription = ReloadTestSupport.tally(registry.onReload, into: tally)
        defer { subscription.cancel() }

        try ReloadTestSupport.writeSkillFile(id: Self.skillAddedByReload, in: root)
        await ReloadTestSupport.expectExactlyOneEvent(tally)
        let idProperty = try Self.property(named: Self.idFieldName, in: tool.parameters)
        let answer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "use skill", "id": Self.skillAddedByReload]))

        #expect((idProperty["enum"] as? [String])?.contains(Self.skillAddedByReload) ?? true)
        #expect(answer == (try await registry.call(id: Self.skillAddedByReload)))
    }

    @Test func theSchemaKeepsTheOpEnumAndEveryField() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())

        let properties = try Self.properties(in: tool.parameters)
        let opProperty = try Self.property(named: OperationKeys.opFieldName, in: tool.parameters)
        let fieldNames = Set(tool.operations.flatMap { $0.parameters.map(\.name) })

        #expect(opProperty["enum"] as? [String] == tool.operations.map(\.opString))
        #expect(Set(properties.keys) == fieldNames.union([OperationKeys.opFieldName]))
    }

    // MARK: - No visible skill

    @Test func withNoVisibleSkillTheToolStandsWithThePlainIDAndTheNoSkillsLine() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let tool = try await SkillsTool.make(registry: SkillsRegistry(roots: [root]))
        let idProperty = try Self.property(named: Self.idFieldName, in: tool.parameters)

        #expect(tool.description.hasSuffix(Self.noSkillsLine))
        #expect(idProperty["enum"] == nil)
        #expect(idProperty["type"] as? String == Self.stringTypeName)
    }

    // MARK: - The tool still works

    @Test func theToolDispatchesAUseCallForAVisibleID() async throws {
        let registry = Self.makeFixtureRegistry()
        let tool = try await SkillsTool.make(registry: registry)

        let answer = try await tool.call(arguments: GeneratedContent(properties: ["op": "use skill", "id": "lint"]))

        #expect(answer == (try await registry.call(id: "lint")))
    }

    // MARK: - The operation texts

    @Test func theOperationTextsSayWhatTheModelGets() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())
        let descriptions = Dictionary(uniqueKeysWithValues: tool.operations.map { ($0.opString, $0.description) })

        #expect(descriptions["use skill"] == "Load the instructions of a skill. Follow them.")
        #expect(
            descriptions["search skill"]
                == "Find the skills for the kind of work that you will do next, for example explore code, "
                + "find callers, or run tests. Search by the kind of work, not by the topic of the task.")
        #expect(descriptions["list skill"] == "List each skill with its description.")
    }

    // MARK: - Fixtures

    /// Builds a registry over the `Examples/skill-library` fixture stack.
    ///
    /// - Returns: The registry the cases hand to a factory.
    private static func makeFixtureRegistry() -> SkillsRegistry {
        SkillsRegistry(stack: FixtureLibrary.stack())
    }

    /// Reads the top-level properties of `schema` from its JSON form.
    ///
    /// - Parameter schema: The fused schema of the tool.
    /// - Returns: Each property schema, by name.
    /// - Throws: An encode error, or a `#require` failure when the JSON has
    ///   no `properties` object.
    private static func properties(in schema: GenerationSchema) throws -> [String: Any] {
        let data = try JSONEncoder().encode(schema)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["properties"] as? [String: Any])
    }

    /// Reads one property schema of `schema`.
    ///
    /// - Parameters:
    ///   - name: The property name.
    ///   - schema: The fused schema of the tool.
    /// - Returns: The JSON object of the property.
    /// - Throws: A `#require` failure when the schema has no such property.
    private static func property(named name: String, in schema: GenerationSchema) throws -> [String: Any] {
        try #require(try properties(in: schema)[name] as? [String: Any])
    }
}
