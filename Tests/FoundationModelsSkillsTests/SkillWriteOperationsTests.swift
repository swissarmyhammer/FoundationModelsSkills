import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsSkills

/// Tests for the write operations of the `skills` tool: `add skill`,
/// `edit skill` and `remove skill`, each with the `layer` option.
///
/// Each test calls `SkillsCatalogTool.call(arguments:)`, as a model does. The
/// registry has a user layer and a project layer in temporary folders, lowest
/// precedence first. The test then reads the files on disk and the plain-text
/// answer of the tool.
struct SkillWriteOperationsTests {
    // MARK: - Constants

    /// The name of the skill that a test writes. `WriteFixture` reads it
    /// too, thus it is `fileprivate`.
    fileprivate static let skillName = "new-skill"

    /// The file name of the skill file.
    private static let skillFileName = "SKILL.md"

    /// The path of a file of a skill that is not the skill file.
    private static let referencePath = "references/guide.md"

    /// The text of a file of a skill that is not the skill file.
    private static let referenceText = "Guide text.\n"

    /// A layer value that is not `user` and not `project`.
    private static let badLayer = "global"

    /// The exact guide text of the `layer` field. The `agents` tool (AG-9)
    /// uses the same words with `.agents` in place of `.skills`.
    private static let layerGuideText =
        "Optional. Where to write: user (the user folder, for all projects) or project "
        + "(the .skills folder of this project). Leave it out for user."

    /// The name of the `layer` field of the schema.
    private static let layerFieldName = "layer"

    /// The value of the `project` layer.
    private static let projectLayer = "project"

    // MARK: - add skill

    @Test func addSkillWithNoLayerWritesTheUserLayer() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }

        _ = try await fixture.call(Self.addArguments())

        #expect(fixture.fileExists(Self.skillFileName, in: .user))
    }

    @Test func addSkillWithTheProjectLayerWritesTheProjectLayer() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }

        _ = try await fixture.call(Self.addArguments(layer: Self.projectLayer))

        #expect(fixture.fileExists(Self.skillFileName, in: .project))
    }

    @Test func addSkillWritesTheGivenContent() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }

        _ = try await fixture.call(Self.addArguments())

        #expect(try fixture.text(of: Self.skillFileName, in: .user) == Self.markdown())
    }

    @Test func addSkillAnswersOneSentenceThatNamesTheSkillTheLayerAndThePath() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }

        let answer = try await fixture.call(Self.addArguments())

        let path = fixture.url(of: Self.skillFileName, in: .user).path
        #expect(answer == "Added the skill `\(Self.skillName)` to the user layer: `\(path)`.")
    }

    @Test func addSkillWithABadLayerGivesACorrectiveThatNamesUserAndProject() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }

        let answer = try await fixture.call(Self.addArguments(layer: Self.badLayer))

        #expect(
            answer == "The layer `\(Self.badLayer)` is not valid. Give `user` or `project`, or leave it out for `user`.")
    }

    @Test func addSkillWithABadLayerWritesNothing() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }

        _ = try await fixture.call(Self.addArguments(layer: Self.badLayer))

        #expect(fixture.allFiles().isEmpty)
    }

    @Test func addSkillOfAFolderThatTheLayerHoldsGivesTheCorrectiveOfTheWriterAsPlainText() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        _ = try await fixture.call(Self.addArguments())

        let answer = try await fixture.call(Self.addArguments())

        #expect(answer.hasPrefix("The skill `\(Self.skillName)` is already in the user layer."))
    }

    @Test func useSkillAfterAddSkillGivesTheBodyOfTheNewSkill() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        _ = try await fixture.call(Self.addArguments())

        let answer = try await fixture.call(
            GeneratedContent(properties: ["op": "use skill", "id": Self.skillName]))

        #expect(answer.contains(Self.body))
    }

    // MARK: - edit skill

    @Test func editSkillWithNoPathWritesTheSkillFileOfTheUserLayer() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        _ = try await fixture.call(Self.addArguments())

        _ = try await fixture.call(Self.editArguments(content: Self.markdown(descriptionSuffix: "after")))

        #expect(try fixture.text(of: Self.skillFileName, in: .user) == Self.markdown(descriptionSuffix: "after"))
    }

    @Test func editSkillWithAPathAndTheProjectLayerWritesThatFileOfTheProjectLayer() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        _ = try await fixture.call(Self.addArguments(layer: Self.projectLayer))

        _ = try await fixture.call(
            Self.editArguments(path: Self.referencePath, content: Self.referenceText, layer: Self.projectLayer))

        #expect(try fixture.text(of: Self.referencePath, in: .project) == Self.referenceText)
    }

    @Test func editSkillAnswersOneSentenceThatNamesTheSkillTheLayerAndThePath() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        _ = try await fixture.call(Self.addArguments())

        let answer = try await fixture.call(
            Self.editArguments(path: Self.referencePath, content: Self.referenceText))

        let path = fixture.url(of: Self.referencePath, in: .user).path
        #expect(answer == "Edited the skill `\(Self.skillName)` in the user layer: `\(path)`.")
    }

    @Test func editSkillWithABadLayerGivesACorrectiveThatNamesUserAndProject() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        _ = try await fixture.call(Self.addArguments())

        let answer = try await fixture.call(
            Self.editArguments(path: Self.referencePath, content: Self.referenceText, layer: Self.badLayer))

        #expect(
            answer == "The layer `\(Self.badLayer)` is not valid. Give `user` or `project`, or leave it out for `user`.")
    }

    @Test func editSkillWithABadLayerWritesNothing() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        _ = try await fixture.call(Self.addArguments())

        _ = try await fixture.call(
            Self.editArguments(path: Self.referencePath, content: Self.referenceText, layer: Self.badLayer))

        #expect(!fixture.fileExists(Self.referencePath, in: .user))
    }

    // MARK: - remove skill

    @Test func removeSkillWithNoLayerDeletesTheFolderOfTheUserLayer() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        _ = try await fixture.call(Self.addArguments())

        _ = try await fixture.call(Self.removeArguments())

        #expect(!fixture.folderExists(in: .user))
    }

    @Test func removeSkillWithTheProjectLayerDeletesTheFolderOfTheProjectLayer() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        _ = try await fixture.call(Self.addArguments(layer: Self.projectLayer))

        _ = try await fixture.call(Self.removeArguments(layer: Self.projectLayer))

        #expect(!fixture.folderExists(in: .project))
    }

    @Test func removeSkillAnswersOneSentenceThatNamesTheSkillTheLayerAndThePath() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        _ = try await fixture.call(Self.addArguments())

        let answer = try await fixture.call(Self.removeArguments())

        let path = fixture.folderURL(in: .user).path
        #expect(answer == "Removed the skill `\(Self.skillName)` from the user layer: `\(path)`.")
    }

    @Test func removeSkillWithABadLayerGivesACorrectiveThatNamesUserAndProject() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        _ = try await fixture.call(Self.addArguments())

        let answer = try await fixture.call(Self.removeArguments(layer: Self.badLayer))

        #expect(
            answer == "The layer `\(Self.badLayer)` is not valid. Give `user` or `project`, or leave it out for `user`.")
    }

    @Test func removeSkillWithABadLayerKeepsTheFolder() async throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        _ = try await fixture.call(Self.addArguments())

        _ = try await fixture.call(Self.removeArguments(layer: Self.badLayer))

        #expect(fixture.folderExists(in: .user))
    }

    // MARK: - The schema

    @Test func theLayerFieldOfTheSchemaHasTheGuideTextOfTheAgentsTool() throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }

        let layerProperty = try Self.property(named: Self.layerFieldName, in: fixture.tool.parameters)

        #expect(layerProperty["description"] as? String == Self.layerGuideText)
    }

    @Test(arguments: ["add skill", "edit skill", "remove skill"])
    func eachWriteOperationDeclaresTheLayerParameterWithTheGuideText(op: String) throws {
        let fixture = try WriteFixture()
        defer { fixture.remove() }
        let operation = try #require(fixture.tool.operations.first { $0.opString == op })

        let layer = try #require(operation.parameters.first { $0.name == Self.layerFieldName })

        #expect(layer.description == Self.layerGuideText && !layer.required)
    }

    // MARK: - Helpers

    /// The body of the skill file that `markdown(descriptionSuffix:)` gives.
    private static let body = "Body text for \(skillName)."

    /// A valid skill file of `skillName`.
    ///
    /// - Parameter descriptionSuffix: Text at the end of the description, so
    ///   two versions of the file differ.
    /// - Returns: The text of the skill file.
    private static func markdown(descriptionSuffix: String = "") -> String {
        ReloadTestSupport.skillFileContents(id: skillName, descriptionSuffix: descriptionSuffix)
    }

    /// The payload of an `add skill` call of `skillName`.
    ///
    /// - Parameter layer: The `layer` value, or `nil` to leave it out.
    /// - Returns: The payload.
    private static func addArguments(layer: String? = nil) -> GeneratedContent {
        payload(op: "add skill", fields: [("content", markdown())], layer: layer)
    }

    /// The payload of an `edit skill` call of `skillName`.
    ///
    /// - Parameters:
    ///   - path: The `path` value, or `nil` to leave it out.
    ///   - content: The `content` value.
    ///   - layer: The `layer` value, or `nil` to leave it out.
    /// - Returns: The payload.
    private static func editArguments(path: String? = nil, content: String, layer: String? = nil) -> GeneratedContent {
        payload(op: "edit skill", fields: [("content", content)] + (path.map { [("path", $0)] } ?? []), layer: layer)
    }

    /// The payload of a `remove skill` call of `skillName`.
    ///
    /// - Parameter layer: The `layer` value, or `nil` to leave it out.
    /// - Returns: The payload.
    private static func removeArguments(layer: String? = nil) -> GeneratedContent {
        payload(op: "remove skill", fields: [], layer: layer)
    }

    /// A payload with `op`, the `id` of `skillName`, `fields`, and `layer`
    /// when it is not `nil`.
    ///
    /// - Parameters:
    ///   - op: The op string.
    ///   - fields: The other string fields of the payload.
    ///   - layer: The `layer` value, or `nil` to leave it out.
    /// - Returns: The payload.
    private static func payload(op: String, fields: [(String, String)], layer: String?) -> GeneratedContent {
        let layerField = layer.map { [(layerFieldName, $0)] } ?? []
        let properties: [(String, any ConvertibleToGeneratedContent)] =
            ([("op", op), ("id", skillName)] + fields + layerField).map { ($0.0, $0.1) }
        return GeneratedContent(properties: properties, uniquingKeysWith: { _, new in new })
    }

    /// Reads one property schema of `schema` from its JSON form.
    ///
    /// - Parameters:
    ///   - name: The property name.
    ///   - schema: The fused schema of the tool.
    /// - Returns: The JSON object of the property.
    /// - Throws: An encode error, or a `#require` failure when the schema has
    ///   no such property.
    private static func property(named name: String, in schema: GenerationSchema) throws -> [String: Any] {
        let data = try JSONEncoder().encode(schema)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        return try #require(properties[name] as? [String: Any])
    }
}

/// A user layer and a project layer in temporary folders, a registry over
/// them, and the `skills` tool over that registry.
private struct WriteFixture {
    /// The source of each layer, lowest precedence first.
    private static let sources: [DotfolderStack.Source] = [.user, .project]

    /// The root of each layer, in the order of `sources`.
    let directories: [URL]

    /// The registry over the layers.
    let registry: SkillsRegistry

    /// The tool under test.
    let tool: SkillsCatalogTool

    /// Makes one temporary folder for each layer, a registry over them, and
    /// the tool.
    ///
    /// - Throws: Whatever `LayerFixtureSupport.makeLayerDirectories(count:)`
    ///   or `SkillsTool.make(context:)` throws.
    init() throws {
        directories = try LayerFixtureSupport.makeLayerDirectories(count: Self.sources.count)
        registry = SkillsRegistry(
            layers: zip(Self.sources, directories).map { DotfolderStack.Layer(source: $0, root: $1) })
        tool = try SkillsTool.make(context: ResourceTestSupport.makeContext(registry: registry))
    }

    /// Removes each layer folder.
    func remove() {
        LayerFixtureSupport.removeDirectories(directories)
    }

    /// Calls the tool as a model does.
    ///
    /// - Parameter arguments: The payload.
    /// - Returns: The answer that the model reads.
    /// - Throws: Whatever `SkillsCatalogTool.call(arguments:)` throws.
    func call(_ arguments: GeneratedContent) async throws -> String {
        try await tool.call(arguments: arguments)
    }

    /// The folder of the test skill in the layer of `source`.
    ///
    /// - Parameter source: The source of the layer.
    /// - Returns: The URL of the folder.
    func folderURL(in source: DotfolderStack.Source) -> URL {
        let index = Self.sources.firstIndex(of: source) ?? Self.sources.startIndex
        return directories[index].appendingPathComponent(SkillWriteOperationsTests.skillName, isDirectory: true)
    }

    /// The file `path` of the test skill in the layer of `source`.
    ///
    /// - Parameters:
    ///   - path: The path of the file, relative to the skill folder.
    ///   - source: The source of the layer.
    /// - Returns: The URL of the file.
    func url(of path: String, in source: DotfolderStack.Source) -> URL {
        folderURL(in: source).appendingPathComponent(path)
    }

    /// Whether the file `path` of the test skill is in the layer of `source`.
    ///
    /// - Parameters:
    ///   - path: The path of the file, relative to the skill folder.
    ///   - source: The source of the layer.
    /// - Returns: `true` when the file exists.
    func fileExists(_ path: String, in source: DotfolderStack.Source) -> Bool {
        FileManager.default.fileExists(atPath: url(of: path, in: source).path)
    }

    /// Whether the folder of the test skill is in the layer of `source`.
    ///
    /// - Parameter source: The source of the layer.
    /// - Returns: `true` when the folder exists.
    func folderExists(in source: DotfolderStack.Source) -> Bool {
        FileManager.default.fileExists(atPath: folderURL(in: source).path)
    }

    /// The text of the file `path` of the test skill in the layer of
    /// `source`.
    ///
    /// - Parameters:
    ///   - path: The path of the file, relative to the skill folder.
    ///   - source: The source of the layer.
    /// - Returns: The text of the file.
    /// - Throws: Whatever `String(contentsOf:encoding:)` throws.
    func text(of path: String, in source: DotfolderStack.Source) throws -> String {
        try String(contentsOf: url(of: path, in: source), encoding: .utf8)
    }

    /// Every path below each layer root, sorted.
    ///
    /// - Returns: The sorted paths.
    func allFiles() -> [String] {
        directories.flatMap { FileManager.default.subpaths(atPath: $0.path) ?? [] }.sorted()
    }
}

