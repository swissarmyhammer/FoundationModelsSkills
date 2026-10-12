import Foundation
import FoundationModels
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the answer of `use skill` through the fused `skills` tool.
///
/// The model reads the answer as the procedure to follow. Thus the answer is
/// the rendered body of the skill as plain text: no JSON object, no `body`
/// key, no `id` key, and no escape sequences. When the skill has files other
/// than `SKILL.md`, a plain-text list of the files and the calls that read
/// them follow the body. An error is a plain sentence.
///
/// Each alias of `use skill` gives the same answer. Thus each test runs once
/// for each op spelling in `useSkillOps`.
struct UseSkillPlainTextTests {
    // MARK: - Constants

    /// Each op spelling of the `use skill` operation that a model can write:
    /// the canonical op and its `call`, `invoke`, and `get` aliases.
    private static let useSkillOps = ["use skill", "skill_call", "skill_invoke", "skill_get"]

    /// The fixture skill with one named argument and a body of more than
    /// one line, thus JSON would escape its line breaks.
    private static let commitSkillID = "commit"

    /// The value of the argument of `commitSkillID`.
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
        let renderedBody = try await registry.call(id: Self.commitSkillID, arguments: [Self.commitMessage])

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
        let renderedBody = try await registry.call(id: Self.commitSkillID, arguments: [Self.commitMessage])

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
    func aCallWithNoArgumentsGivesTheRenderedBodyWithTheArgumentEmpty(op: String) async throws {
        let registry = Self.makeFixtureRegistry()
        let tool = try Self.makeTool(registry: registry)
        let renderedBody = try await registry.call(id: Self.commitSkillID, arguments: [])

        let answer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": op, "id": Self.commitSkillID]))

        #expect(answer == renderedBody)
        #expect(answer.contains("using the message: \n"))
    }

    // MARK: - The list of the files of the skill follows the body

    /// The fixture skill with one asset, two references and one script.
    private static let releaseNotesSkillID = "release-notes"

    /// The exact relative path of each file that the body of `release-notes`
    /// names.
    private static let releaseNotesBodyPaths = ["references/changelog.md", "scripts/build.sh", "assets/logo.bin"]

    /// The name of the deleted design document that the body must not name.
    private static let deletedPlanDocument = "plan.md"

    /// A line of `references/style.md`, the reference that the body of
    /// `release-notes` includes.
    private static let includedStyleLine = "Write one line for each change."

    /// The text of the include tag, which the render replaces.
    private static let includeTagText = "{% include"

    /// The first line of the list of the files.
    private static let filesHeading = "Files of this skill:"

    /// The text that follows the body of `release-notes` under a host policy
    /// that permits scripts: the four rows in path order, the read call and
    /// the run call.
    private static let releaseNotesFilesText = """
        Files of this skill:
        - assets/logo.bin (asset)
        - references/changelog.md (reference)
        - references/style.md (reference)
        - scripts/build.sh (script)

        To read a file, call the `skills` tool with {"op": "read resource", "id": "release-notes", "path": "<path>"}. \
        Give the path as it is in this list.
        To run a script, call the `skills` tool with {"op": "run script", "id": "release-notes", "path": "scripts/<name>"}.
        """

    /// The text that follows the body of `release-notes` when the host policy
    /// disables scripts: the same rows and the read call, with no run call.
    private static let releaseNotesFilesTextWithNoRunCall = """
        Files of this skill:
        - assets/logo.bin (asset)
        - references/changelog.md (reference)
        - references/style.md (reference)
        - scripts/build.sh (script)

        To read a file, call the `skills` tool with {"op": "read resource", "id": "release-notes", "path": "<path>"}. \
        Give the path as it is in this list.
        """

    /// The id of the skill that each temporary-layer test writes.
    private static let generatedSkillID = "generated"

    /// The path of the one reference of the skill with no script.
    private static let generatedReferencePath = "references/guide.md"

    /// The text that follows the body of a skill whose one file other than
    /// `SKILL.md` is `generatedReferencePath`.
    private static let generatedReferenceFilesText = """
        Files of this skill:
        - references/guide.md (reference)

        To read a file, call the `skills` tool with {"op": "read resource", "id": "generated", "path": "<path>"}. \
        Give the path as it is in this list.
        """

    /// The text between the body and the list of the files.
    ///
    /// The body of each fixture skill ends with a line break, thus one more
    /// line break makes the one blank line between the body and the list.
    private static let bodySeparator = "\n"

    /// The number of rows that the list gives at most.
    private static let rowLimit = 100

    /// The number of files of the skill that the row-limit test writes.
    private static let manyFileCount = 102

    @Test func useSkillOfReleaseNotesGivesTheBodyThenTheFilesAndTheCalls() async throws {
        let registry = Self.makeFixtureRegistry()
        let tool = try Self.makeTool(registry: registry)
        let renderedBody = try await registry.call(id: Self.releaseNotesSkillID, arguments: [])

        let answer = try await tool.call(arguments: Self.useArguments(id: Self.releaseNotesSkillID))

        #expect(renderedBody.hasSuffix("\n"))
        #expect(answer == renderedBody + Self.bodySeparator + Self.releaseNotesFilesText)
    }

    @Test func useSkillOfReleaseNotesGivesTheIncludedReferenceTextThenTheFourFileRows() async throws {
        let answer = try await Self.useAnswer(id: Self.releaseNotesSkillID, registry: Self.makeFixtureRegistry())

        let includedLine = try #require(answer.range(of: Self.includedStyleLine))
        let heading = try #require(answer.range(of: Self.filesHeading))
        #expect(includedLine.upperBound < heading.lowerBound)
        #expect(!answer.contains(Self.includeTagText))
        #expect(answer.hasSuffix(Self.releaseNotesFilesText))
    }

    @Test func theBodyOfReleaseNotesNamesEachFileByItsExactRelativePath() async throws {
        let renderedBody = try await Self.makeFixtureRegistry().call(id: Self.releaseNotesSkillID, arguments: [])

        for path in Self.releaseNotesBodyPaths {
            #expect(renderedBody.contains("`\(path)`"), "the body must name `\(path)`")
        }
        #expect(!renderedBody.contains(Self.deletedPlanDocument))
    }

    @Test func aDisabledScriptPolicyGivesNoRunCall() async throws {
        let registry = SkillsRegistry(
            roots: [ResourceTestSupport.projectSkillsRoot], policy: RenderPolicy(isScriptExecutionDisabled: true))
        let tool = try Self.makeTool(registry: registry)
        let renderedBody = try await registry.call(id: Self.releaseNotesSkillID, arguments: [])

        let answer = try await tool.call(arguments: Self.useArguments(id: Self.releaseNotesSkillID))

        #expect(answer == renderedBody + Self.bodySeparator + Self.releaseNotesFilesTextWithNoRunCall)
    }

    @Test func aSkillWithNoScriptGivesNoRunCall() async throws {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 1)
        defer { LayerFixtureSupport.removeDirectories(directories) }
        try ResourceTestSupport.writeMinimalSkillFile(id: Self.generatedSkillID, in: directories[0])
        try LayerFixtureSupport.writeTextFile(
            at: Self.generatedReferencePath,
            in: directories[0].appendingPathComponent(Self.generatedSkillID, isDirectory: true))
        let registry = SkillsRegistry(roots: directories)

        let answer = try await Self.useAnswer(id: Self.generatedSkillID, registry: registry)

        let renderedBody = try await registry.call(id: Self.generatedSkillID, arguments: [])
        #expect(answer == renderedBody + Self.bodySeparator + Self.generatedReferenceFilesText)
    }

    @Test func aFileThatOnlyALowerLayerHoldsIsInTheList() async throws {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 2)
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let (lower, higher) = (directories[0], directories[1])
        try LayerFixtureSupport.writeTextFile(
            at: Self.generatedReferencePath, in: lower.appendingPathComponent(Self.generatedSkillID, isDirectory: true))
        try ResourceTestSupport.writeMinimalSkillFile(id: Self.generatedSkillID, in: higher)
        let registry = SkillsRegistry(roots: [lower, higher])

        let answer = try await Self.useAnswer(id: Self.generatedSkillID, registry: registry)

        let renderedBody = try await registry.call(id: Self.generatedSkillID, arguments: [])
        #expect(answer == renderedBody + Self.bodySeparator + Self.generatedReferenceFilesText)
    }

    @Test func aSkillWithMoreFilesThanTheLimitListsTheLimitAndCountsTheRest() async throws {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 1)
        defer { LayerFixtureSupport.removeDirectories(directories) }
        try ResourceTestSupport.writeMinimalSkillFile(id: Self.generatedSkillID, in: directories[0])
        let skillDirectory = directories[0].appendingPathComponent(Self.generatedSkillID, isDirectory: true)
        let paths = (0..<Self.manyFileCount).map { String(format: "references/file-%03d.md", $0) }
        for path in paths {
            try LayerFixtureSupport.writeTextFile(at: path, in: skillDirectory)
        }
        let registry = SkillsRegistry(roots: directories)

        let answer = try await Self.useAnswer(id: Self.generatedSkillID, registry: registry)

        let renderedBody = try await registry.call(id: Self.generatedSkillID, arguments: [])
        let rows = paths.prefix(Self.rowLimit).map { "- \($0) (reference)" }
        let expected =
            ["Files of this skill:"] + rows + [
                #"2 more files are not listed. See them with {"op": "list resource", "id": "generated"}."#,
                "",
                #"To read a file, call the `skills` tool with {"op": "read resource", "id": "generated", "#
                    + #""path": "<path>"}. Give the path as it is in this list."#,
            ]
        #expect(answer == renderedBody + Self.bodySeparator + expected.joined(separator: "\n"))
    }

    @Test func theAddedTextHoldsNoTag() async throws {
        let registry = Self.makeFixtureRegistry()
        let renderedBody = try await registry.call(id: Self.releaseNotesSkillID, arguments: [])

        let answer = try await Self.useAnswer(id: Self.releaseNotesSkillID, registry: registry)

        let addedText = try #require(
            answer.hasPrefix(renderedBody) ? String(answer.dropFirst(renderedBody.count)) : nil,
            "the answer must start with the rendered body")
        #expect(!addedText.isEmpty)
        #expect(!addedText.contains("</"))
        #expect(addedText.firstMatch(of: /<(\w+)>[\s\S]*<\/\1>/) == nil)
    }

    // MARK: - Fixtures

    /// Gives the answer of the fused tool to the `use skill` call of `id`.
    ///
    /// - Parameters:
    ///   - id: The skill id to load.
    ///   - registry: The registry the tool dispatches against.
    /// - Returns: The plain-text answer.
    /// - Throws: Whatever `makeTool(registry:)` or `call(arguments:)` throws.
    private static func useAnswer(id: String, registry: SkillsRegistry) async throws -> String {
        try await makeTool(registry: registry).call(arguments: useArguments(id: id))
    }

    /// The payload that loads `id` with no arguments.
    ///
    /// - Parameter id: The skill id to load.
    /// - Returns: The payload.
    private static func useArguments(id: String) -> GeneratedContent {
        GeneratedContent(properties: ["op": useSkillOps[0], "id": id])
    }

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
