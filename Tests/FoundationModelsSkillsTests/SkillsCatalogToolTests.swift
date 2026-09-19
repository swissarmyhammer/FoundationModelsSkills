import Foundation
import FoundationModels
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the catalog that the `skills` tool shows the model: the tool
/// description, the `id` enum of the fused schema, and the texts of the
/// operations.
///
/// A model sees only the name, the description, and the schema of a tool
/// before it plans. These cases show that the description and the schema
/// carry the visible skills, and that no model-hidden skill gets into them.
struct SkillsCatalogToolTests {
    // MARK: - Constants

    /// The fixture skill that carries `disable-model-invocation: true`, thus
    /// the default visibility predicate must hide it.
    private static let modelHiddenSkillID = "deploy"

    /// The two fixed sentences of the description, word for word from the
    /// card.
    private static let fixedSentences =
        "Skills are procedures for kinds of work. Each one tells you how to do the work and which tools to use.\n"
        + "When a task matches a skill below, you must load that skill with `use skill` "
        + "and follow its instructions before you do the work."

    /// The line the description gives when no skill is visible.
    private static let noSkillsLine = "No skills are installed now."

    /// The name of the fused schema field that holds a skill id.
    private static let idFieldName = "id"

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

    // MARK: - The id enum

    @Test func theIDFieldOfTheSchemaIsAnEnumOfTheVisibleIDs() async throws {
        let registry = Self.makeFixtureRegistry()
        let visibleIDs = registry.metadata().filter(\.isModelVisible).map(\.id)

        let tool = try await SkillsTool.make(registry: registry)
        let idProperty = try Self.property(named: Self.idFieldName, in: tool.parameters)

        #expect(idProperty["enum"] as? [String] == visibleIDs)
        #expect(idProperty["description"] as? String == "The id of the skill to load.")
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
        #expect(idProperty["enum"] == nil, "an empty enum admits no value, thus the id stays a plain string")
    }

    // MARK: - The tool still works

    @Test func theToolDispatchesAUseCallForAVisibleID() async throws {
        let registry = Self.makeFixtureRegistry()
        let tool = try await SkillsTool.make(registry: registry)

        let answer = try await tool.call(arguments: GeneratedContent(properties: ["op": "use skill", "id": "lint"]))

        #expect(answer == (try registry.call(id: "lint")))
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
