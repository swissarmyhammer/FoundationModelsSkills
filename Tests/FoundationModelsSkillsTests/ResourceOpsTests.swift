import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the Layer-4 resource operations (plan.md §7.3).
///
/// `list resource`/`read resource` dispatched through the fused `skills`
/// `OperationTool`, over both the static `release-notes` fixture and
/// temp-directory fixtures generated for the confinement and cap matrices.
struct ResourceOpsTests {
    // MARK: - Fixture root (mirrors SkillOperationsTests)

    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    /// Builds a `SkillsToolContext` over `roots`.
    ///
    /// Wraps a real, GPU-free `.retrieval`-mode `MetadataSearcher` standing
    /// in for the stub-searcher context the sibling op tests use -- resource
    /// ops never dispatch through it, but `SkillsToolContext` still requires
    /// one.
    ///
    /// - Parameter roots: The registry roots to build over. Defaults to the
    ///   §11 fixture library.
    /// - Returns: The assembled context.
    private static func makeContext(roots: [URL] = [Self.projectSkillsRoot]) -> SkillsToolContext {
        let registry = SkillsRegistry(roots: roots)
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        return SkillsToolContext(registry: registry, searchAgent: SkillSearchAgent(searcher: searcher))
    }

    /// Builds the fused `skills` tool over `makeContext(roots:)`.
    private static func makeTool(roots: [URL] = [Self.projectSkillsRoot]) throws -> OperationTool<SkillsToolContext> {
        try SkillsTool.make(context: Self.makeContext(roots: roots))
    }

    /// Whether `json` is a corrective outcome -- a bare JSON string (plan.md
    /// §7: "corrective messages stay plain strings"), never a `{...}`
    /// object, which is what every successful `Encodable` result serializes
    /// as instead.
    ///
    /// - Parameter json: A dispatch result's raw JSON text.
    /// - Returns: Whether `json` is a corrective (a JSON string literal).
    private static func isCorrective(_ json: String) -> Bool {
        json.hasPrefix("\"")
    }

    // MARK: - Listing snapshot (§7.3)

    @Test func listResourceOverReleaseNotesReturnsSortedKindedRowsWithRealTotal() async throws {
        let tool = try Self.makeTool()
        let arguments = GeneratedContent(properties: ["op": "list resource", "id": "release-notes"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"total\":3"))
        #expect(!json.contains("\"path\":\"SKILL.md\""))
        #expect(json.contains("\"kind\":\"asset\",\"path\":\"assets\\/logo.bin\""))
        #expect(json.contains("\"kind\":\"reference\",\"path\":\"references\\/changelog.md\""))
        #expect(json.contains("\"kind\":\"script\",\"path\":\"scripts\\/build.sh\""))
        #expect(json.contains("\"executable\":true"))
    }

    @Test func listResourceOnAnUnknownIDDrawsACorrective() async throws {
        let tool = try Self.makeTool()
        let arguments = GeneratedContent(properties: ["op": "list resource", "id": "nonexistent"])

        let json = try await tool.call(arguments: arguments)

        #expect(Self.isCorrective(json))
        #expect(json.contains("not currently usable"))
    }

    // MARK: - Paging (§7.3)

    @Test func readResourcePagesA700LineReferenceInTwoCallsWithCorrectTotalLines() async throws {
        let tool = try Self.makeTool()

        let firstArguments = GeneratedContent(
            properties: ["op": "read resource", "id": "release-notes", "path": "references/changelog.md"])
        let firstJSON = try await tool.call(arguments: firstArguments)
        #expect(firstJSON.contains("\"start\":1"))
        #expect(firstJSON.contains("\"end\":500"))
        #expect(firstJSON.contains("\"totalLines\":700"))
        #expect(firstJSON.contains("Changelog line 1\\n"))
        #expect(!firstJSON.contains("Changelog line 501"))

        let secondArguments = GeneratedContent(
            properties: [
                "op": "read resource", "id": "release-notes", "path": "references/changelog.md", "start": 501,
            ])
        let secondJSON = try await tool.call(arguments: secondArguments)
        #expect(secondJSON.contains("\"start\":501"))
        #expect(secondJSON.contains("\"end\":700"))
        #expect(secondJSON.contains("\"totalLines\":700"))
        #expect(secondJSON.contains("Changelog line 700"))
        #expect(!secondJSON.contains("Changelog line 500\\n"))
    }

    @Test func readResourceReadsTheExecutableScriptVerbatim() async throws {
        let tool = try Self.makeTool()
        let arguments = GeneratedContent(
            properties: ["op": "read resource", "id": "release-notes", "path": "scripts/build.sh"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"start\":1"))
        #expect(json.contains("#!\\/bin\\/sh"))
        #expect(json.contains("building release notes"))
    }

    // MARK: - Binary corrective (§7.3)

    @Test func readResourceOnABinaryAssetDrawsTheNonUTF8CorrectiveWithItsByteSize() async throws {
        let tool = try Self.makeTool()
        let assetURL = Self.projectSkillsRoot
            .appendingPathComponent("release-notes/assets/logo.bin")
        let byteSize = try #require(
            FileManager.default.attributesOfItem(atPath: assetURL.path)[.size] as? Int)

        let arguments = GeneratedContent(
            properties: ["op": "read resource", "id": "release-notes", "path": "assets/logo.bin"])
        let json = try await tool.call(arguments: arguments)

        #expect(Self.isCorrective(json))
        #expect(json.contains("not valid UTF-8"))
        #expect(json.contains("\(byteSize) bytes"))
    }

    // MARK: - Confinement matrix (plan.md §13)

    @Test func readResourceRejectsDotDotTraversal() async throws {
        let tool = try Self.makeTool()
        let arguments = GeneratedContent(
            properties: ["op": "read resource", "id": "release-notes", "path": "../deploy/SKILL.md"])

        let json = try await tool.call(arguments: arguments)

        #expect(Self.isCorrective(json))
        #expect(json.contains("not accessible"))
    }

    @Test func readResourceRejectsAnAbsolutePath() async throws {
        let tool = try Self.makeTool()
        let arguments = GeneratedContent(
            properties: ["op": "read resource", "id": "release-notes", "path": "/etc/passwd"])

        let json = try await tool.call(arguments: arguments)

        #expect(Self.isCorrective(json))
        #expect(json.contains("not accessible"))
    }

    @Test func readResourceRejectsASymlinkEscapingTheSkillDirectory() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDirectory = try Self.writeMinimalSkillFile(id: "escaper", in: root)
        let outsideFile = root.appendingPathComponent("secret.txt")
        try "top secret".write(to: outsideFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: skillDirectory.appendingPathComponent("escape-link"), withDestinationURL: outsideFile)

        let tool = try Self.makeTool(roots: [root])
        let arguments = GeneratedContent(
            properties: ["op": "read resource", "id": "escaper", "path": "escape-link"])

        let json = try await tool.call(arguments: arguments)

        #expect(Self.isCorrective(json))
        #expect(json.contains("not accessible"))
    }

    @Test func listResourceSkipsASymlinkEscapingTheSkillDirectory() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDirectory = try Self.writeMinimalSkillFile(id: "escaper", in: root)
        let outsideFile = root.appendingPathComponent("secret.txt")
        try "top secret".write(to: outsideFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: skillDirectory.appendingPathComponent("escape-link"), withDestinationURL: outsideFile)

        let tool = try Self.makeTool(roots: [root])
        let arguments = GeneratedContent(properties: ["op": "list resource", "id": "escaper"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"total\":0"))
        #expect(!json.contains("escape-link"))
    }

    // MARK: - >100-file cap (over a generated temp skill)

    @Test func listResourceCapsAt100RowsWithTheRealTotalOverAGeneratedTempSkill() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDirectory = try Self.writeMinimalSkillFile(id: "many-files", in: root)
        for index in 1...150 {
            let name = String(format: "file-%03d.txt", index)
            try "content \(index)".write(
                to: skillDirectory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let tool = try Self.makeTool(roots: [root])
        let arguments = GeneratedContent(properties: ["op": "list resource", "id": "many-files"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"total\":150"))
        #expect(!json.contains("\"total\":100"))
    }

    // MARK: - Surface visibility (plan.md §7.2/§7.3, ^kb2t82c)

    /// Builds a context whose `visibilityPredicate` mirrors `SkillsCLI`'s
    /// own private `makeContext(registry:)`: the user-facing subset
    /// (`registry.commandListing()`'s ids), not the model-facing default.
    ///
    /// `SkillsCLI` only exposes this predicate indirectly, through
    /// `makeDriver(registry:)`'s CLI string-argument dispatch path -- but
    /// resource ops take an `id` (and, for `read`/`run`, a `path`) rather
    /// than a CLI verb, so this builds the equivalent context directly for
    /// `SkillsTool.make(context:)` dispatch.
    ///
    /// - Parameter roots: The registry roots to build over. Defaults to the
    ///   §11 fixture library.
    /// - Returns: The assembled user-surface context.
    private static func makeUserSurfaceContext(roots: [URL] = [Self.projectSkillsRoot]) -> SkillsToolContext {
        let registry = SkillsRegistry(roots: roots)
        let userVisibleIDs = Set(registry.commandListing().map(\.id))
        let isUserVisible: @Sendable (SkillMetadata) -> Bool = { userVisibleIDs.contains($0.id) }
        let searcher = MetadataSearcher(items: registry.metadata().filter(isUserVisible))
        return SkillsToolContext(
            registry: registry,
            searchAgent: SkillSearchAgent(searcher: searcher, visibilityPredicate: isUserVisible),
            visibilityPredicate: isUserVisible)
    }

    @Test func listResourceOnTheModelSurfaceReachesLintButRefusesDeploy() async throws {
        // `lint` (`user-invocable: false`) is model-only; `deploy`
        // (`disable-model-invocation: true`) is user-only -- the model
        // surface must see exactly the opposite of the CLI/user surface
        // below.
        let tool = try SkillsTool.make(context: Self.makeContext())

        let lintJSON = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "list resource", "id": "lint"]))
        let deployJSON = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "list resource", "id": "deploy"]))

        #expect(!Self.isCorrective(lintJSON))
        #expect(Self.isCorrective(deployJSON))
        #expect(deployJSON.contains("not currently usable"))
    }

    @Test func listResourceOnTheUserSurfaceReachesDeployButRefusesLint() async throws {
        let tool = try SkillsTool.make(context: Self.makeUserSurfaceContext())

        let deployJSON = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "list resource", "id": "deploy"]))
        let lintJSON = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "list resource", "id": "lint"]))

        #expect(!Self.isCorrective(deployJSON))
        #expect(Self.isCorrective(lintJSON))
        #expect(lintJSON.contains("not currently usable"))
    }

    @Test func readResourceOnTheModelSurfaceRefusesDeployWithACorrectiveNamingOnlyModelVisibleIDs() async throws {
        // Symmetric to `listResourceOnTheModelSurfaceReachesLintButRefusesDeploy`,
        // for `ReadResource` on the opposite surface: `deploy` is user-only,
        // so the model surface must refuse it.
        let tool = try SkillsTool.make(context: Self.makeContext())

        let json = try await tool.call(
            arguments: GeneratedContent(
                properties: ["op": "read resource", "id": "deploy", "path": "SKILL.md"]))

        #expect(Self.isCorrective(json))
        let usableIDsList = try #require(json.components(separatedBy: "Currently usable ids: ").last)
        #expect(usableIDsList.contains("lint"))
        #expect(!usableIDsList.contains("deploy"))
    }

    @Test func readResourceOnTheUserSurfaceRefusesLintWithACorrectiveNamingOnlyUserVisibleIDs() async throws {
        // Proves `ReadResource` (not just `ListResource`) honors the same
        // surface predicate, and that the corrective's "currently usable
        // ids" list reflects this surface's own visible set.
        let tool = try SkillsTool.make(context: Self.makeUserSurfaceContext())

        let json = try await tool.call(
            arguments: GeneratedContent(
                properties: ["op": "read resource", "id": "lint", "path": "SKILL.md"]))

        #expect(Self.isCorrective(json))
        let usableIDsList = try #require(json.components(separatedBy: "Currently usable ids: ").last)
        #expect(usableIDsList.contains("deploy"))
        #expect(!usableIDsList.contains("lint"))
    }

    // MARK: - Fixture helpers

    /// Writes a minimal, always-valid `id/SKILL.md` under `directory`,
    /// creating the skill's own subdirectory first.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and the
    ///     frontmatter's `name:` field.
    ///   - directory: The root to write under.
    /// - Returns: The created skill directory.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    @discardableResult
    private static func writeMinimalSkillFile(id: String, in directory: URL) throws -> URL {
        let skillDirectory = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try "---\nname: \(id)\ndescription: resource-ops fixture.\n---\nBody text for \(id).\n"
            .write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return skillDirectory
    }
}
