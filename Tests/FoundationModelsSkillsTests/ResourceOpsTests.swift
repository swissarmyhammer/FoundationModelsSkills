import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the Layer-4 resource operations.
///
/// `list resource`/`read resource` dispatched through the fused `skills`
/// `OperationTool`, over both the static `release-notes` fixture and
/// temp-directory fixtures generated for the confinement and cap matrices.
struct ResourceOpsTests {
    // MARK: - Fixture root (mirrors SkillOperationsTests)

    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    /// Builds a `SkillsToolContext` over `roots`, via the shared
    /// `ResourceTestSupport.makeContext(roots:policy:)` -- `RunScriptTests`
    /// builds one the identical way, differing only in its `policy`
    /// parameter.
    ///
    /// - Parameter roots: The registry roots to build over. Defaults to the
    ///   fixture library.
    /// - Returns: The assembled context.
    private static func makeContext(roots: [URL] = [Self.projectSkillsRoot]) -> SkillsToolContext {
        ResourceTestSupport.makeContext(roots: roots)
    }

    /// Builds the fused `skills` tool over `makeContext(roots:)`.
    private static func makeTool(roots: [URL] = [Self.projectSkillsRoot]) throws -> SkillsCatalogTool {
        try SkillsTool.make(context: Self.makeContext(roots: roots))
    }

    /// Whether `json` is a corrective outcome -- a bare JSON string
    /// (corrective messages stay plain strings), never a `{...}`
    /// object, which is what every successful `Encodable` result serializes
    /// as instead.
    ///
    /// - Parameter json: A dispatch result's raw JSON text.
    /// - Returns: Whether `json` is a corrective (a JSON string literal).
    private static func isCorrective(_ json: String) -> Bool {
        json.hasPrefix("\"")
    }

    // MARK: - Listing snapshot

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

    // MARK: - Paging

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

    // MARK: - Binary corrective

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

    // MARK: - Large text paging: streaming line scan, bounded memory

    /// The line count of the large text fixture.
    private static let largeFixtureLineCount = 100_000

    /// The byte width of one large-fixture line, its newline included.
    private static let largeFixtureLineWidth = 52

    /// The byte size the large text fixture must reach: 5 MB.
    private static let largeFixtureMinimumByteSize = 5_000_000

    /// The content byte budget one `read resource` call returns, mirrored
    /// from `ReadResource`.
    private static let contentByteBudget = 1_000_000

    /// The byte size of one line in the budget-cut fixture. Three lines of
    /// this size fit the budget; four do not.
    private static let budgetFixtureLineByteSize = 300_000

    /// The line count of the budget-cut fixture.
    private static let budgetFixtureLineCount = 10

    /// The byte size of the single-line fixture: twice the content budget.
    private static let oversizedLineByteSize = 2 * Self.contentByteBudget

    /// The line count of ASCII text that stands before the invalid bytes in
    /// the late-binary fixture. With `lateBinaryPrefixLineWidth`, the prefix
    /// is over the content budget, so the invalid bytes are found after the
    /// first chunk of the scan and after the requested window.
    private static let lateBinaryPrefixLineCount = 12_000

    /// The byte width of one late-binary prefix line, its newline included.
    private static let lateBinaryPrefixLineWidth = 100

    /// The repeat count of the multi-byte sample in the chunk-straddle
    /// fixture. The sample is 9 bytes, so a chunk boundary that is not a
    /// multiple of 9 splits one character.
    private static let multiByteSampleRepeatCount = 30_000

    /// The line count of the chunk-straddle fixture: over the content
    /// budget in total, so the old whole-file read refused it.
    private static let multiByteFixtureLineCount = 5

    /// The label that opens large-fixture line `number`.
    private static func lineLabel(_ number: Int) -> String {
        String(format: "Line %06d", number)
    }

    /// The large text fixture: `largeFixtureLineCount` lines, each one a
    /// label padded with `x` to `largeFixtureLineWidth` bytes with its
    /// newline.
    private static func makeLargeFixtureBytes() -> Data {
        var text = ""
        text.reserveCapacity(Self.largeFixtureLineCount * Self.largeFixtureLineWidth)
        for number in 1...Self.largeFixtureLineCount {
            let label = Self.lineLabel(number)
            let padding = String(repeating: "x", count: Self.largeFixtureLineWidth - 1 - label.count)
            text += label + padding + "\n"
        }
        return Data(text.utf8)
    }

    /// Writes `id/SKILL.md` and one resource file `fileName` that holds
    /// `bytes`, under a fresh temp root.
    ///
    /// - Returns: The temp root. The caller removes it.
    private static func writeSkillWithResource(id: String, fileName: String, bytes: Data) throws -> URL {
        let root = try HotReloadTestSupport.makeTempDirectory()
        let skillDirectory = try ResourceTestSupport.writeMinimalSkillFile(id: id, in: root)
        try bytes.write(to: skillDirectory.appendingPathComponent(fileName))
        return root
    }

    /// Dispatches one `read resource` call over `roots`, from line `start`.
    ///
    /// - Parameters:
    ///   - roots: The registry roots to build over, lowest precedence first.
    ///   - id: The skill id to read from.
    ///   - path: The resource path to read, relative to the skill directory.
    ///   - start: The first line to return. Defaults to the first line of the
    ///     file, which is the default of the operation as well.
    /// - Returns: The raw JSON text of the dispatch.
    private static func readResource(roots: [URL], id: String, path: String, start: Int = 1) async throws -> String {
        let tool = try Self.makeTool(roots: roots)
        let arguments = GeneratedContent(
            properties: ["op": "read resource", "id": id, "path": path, "start": start])
        return try await tool.call(arguments: arguments)
    }

    @Test func readResourceOnAFiveMegabyteTextPagesTheFirstWindow() async throws {
        let bytes = Self.makeLargeFixtureBytes()
        #expect(bytes.count >= Self.largeFixtureMinimumByteSize)
        let root = try Self.writeSkillWithResource(id: "large", fileName: "large.txt", bytes: bytes)
        defer { try? FileManager.default.removeItem(at: root) }

        let json = try await Self.readResource(roots: [root], id: "large", path: "large.txt", start: 1)

        #expect(!Self.isCorrective(json))
        #expect(json.contains("\"start\":1"))
        #expect(json.contains("\"end\":500"))
        #expect(json.contains("\"totalLines\":\(Self.largeFixtureLineCount)"))
        #expect(json.contains(Self.lineLabel(1)))
        #expect(json.contains(Self.lineLabel(500)))
        #expect(!json.contains(Self.lineLabel(501)))
    }

    @Test func readResourceOnAFiveMegabyteTextPagesAMiddleWindow() async throws {
        let root = try Self.writeSkillWithResource(
            id: "large", fileName: "large.txt", bytes: Self.makeLargeFixtureBytes())
        defer { try? FileManager.default.removeItem(at: root) }

        let json = try await Self.readResource(roots: [root], id: "large", path: "large.txt", start: 50_001)

        #expect(json.contains("\"start\":50001"))
        #expect(json.contains("\"end\":50500"))
        #expect(json.contains("\"totalLines\":\(Self.largeFixtureLineCount)"))
        #expect(json.contains(Self.lineLabel(50_001)))
        #expect(json.contains(Self.lineLabel(50_500)))
        #expect(!json.contains(Self.lineLabel(50_000)))
        #expect(!json.contains(Self.lineLabel(50_501)))
    }

    @Test func readResourceOnAFiveMegabyteTextPagesTheLastWindow() async throws {
        let root = try Self.writeSkillWithResource(
            id: "large", fileName: "large.txt", bytes: Self.makeLargeFixtureBytes())
        defer { try? FileManager.default.removeItem(at: root) }

        let json = try await Self.readResource(roots: [root], id: "large", path: "large.txt", start: 99_501)

        #expect(json.contains("\"start\":99501"))
        #expect(json.contains("\"end\":\(Self.largeFixtureLineCount)"))
        #expect(json.contains("\"totalLines\":\(Self.largeFixtureLineCount)"))
        #expect(json.contains(Self.lineLabel(99_501)))
        #expect(json.contains(Self.lineLabel(Self.largeFixtureLineCount)))
        #expect(!json.contains(Self.lineLabel(99_500)))
    }

    @Test func readResourceBeyondTheLastLineReturnsAnEmptyWindowWithTheRealTotal() async throws {
        let root = try Self.writeSkillWithResource(
            id: "large", fileName: "large.txt", bytes: Self.makeLargeFixtureBytes())
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Self.largeFixtureLineCount + 1

        let json = try await Self.readResource(roots: [root], id: "large", path: "large.txt", start: start)

        #expect(!Self.isCorrective(json))
        #expect(json.contains("\"content\":\"\""))
        #expect(json.contains("\"start\":\(start)"))
        #expect(json.contains("\"end\":\(Self.largeFixtureLineCount)"))
        #expect(json.contains("\"totalLines\":\(Self.largeFixtureLineCount)"))
    }

    @Test func readResourceCutsAWindowAtTheContentByteBudgetAndReportsTheLastLineReturned() async throws {
        var bytes = Data()
        for _ in 1...Self.budgetFixtureLineCount {
            bytes.append(Data(repeating: 0x42, count: Self.budgetFixtureLineByteSize - 1))
            bytes.append(0x0A)
        }
        let root = try Self.writeSkillWithResource(id: "wide", fileName: "wide.txt", bytes: bytes)
        defer { try? FileManager.default.removeItem(at: root) }

        let json = try await Self.readResource(roots: [root], id: "wide", path: "wide.txt", start: 1)

        #expect(!Self.isCorrective(json))
        #expect(json.contains("\"start\":1"))
        #expect(json.contains("\"end\":3"))
        #expect(json.contains("\"totalLines\":\(Self.budgetFixtureLineCount)"))
    }

    @Test func readResourceOnASingleOversizedLineDrawsACorrectiveNamingTheLine() async throws {
        let bytes = Data(repeating: 0x41, count: Self.oversizedLineByteSize)
        let root = try Self.writeSkillWithResource(id: "oversized", fileName: "huge.txt", bytes: bytes)
        defer { try? FileManager.default.removeItem(at: root) }

        let json = try await Self.readResource(roots: [root], id: "oversized", path: "huge.txt", start: 1)

        #expect(Self.isCorrective(json))
        #expect(json.contains("exceeding"))
        #expect(json.contains("Line 1 of"))
        #expect(json.contains("\(Self.contentByteBudget)-byte"))
    }

    @Test func readResourceRefusesNonUTF8BytesFoundAfterTheFirstChunkWithTheStatedSize() async throws {
        var bytes = Data()
        for _ in 1...Self.lateBinaryPrefixLineCount {
            bytes.append(Data(repeating: 0x61, count: Self.lateBinaryPrefixLineWidth - 1))
            bytes.append(0x0A)
        }
        #expect(bytes.count > Self.contentByteBudget)
        bytes.append(contentsOf: [0xFF, 0xFE, 0x0A])
        let root = try Self.writeSkillWithResource(id: "late-binary", fileName: "mixed.bin", bytes: bytes)
        defer { try? FileManager.default.removeItem(at: root) }

        let json = try await Self.readResource(roots: [root], id: "late-binary", path: "mixed.bin", start: 1)

        #expect(Self.isCorrective(json))
        #expect(json.contains("not valid UTF-8"))
        #expect(json.contains("\(bytes.count) bytes"))
    }

    @Test func readResourceKeepsMultiByteCharactersThatStraddleReadChunks() async throws {
        let line = String(repeating: "é€😀", count: Self.multiByteSampleRepeatCount)
        let text = Array(repeating: line, count: Self.multiByteFixtureLineCount).joined(separator: "\n")
        #expect(text.utf8.count > Self.contentByteBudget)
        let root = try Self.writeSkillWithResource(id: "wide-chars", fileName: "chars.txt", bytes: Data(text.utf8))
        defer { try? FileManager.default.removeItem(at: root) }

        let json = try await Self.readResource(roots: [root], id: "wide-chars", path: "chars.txt", start: 1)

        #expect(!Self.isCorrective(json))
        #expect(json.contains(line))
        #expect(json.contains("\"totalLines\":\(Self.multiByteFixtureLineCount)"))
    }

    // MARK: - Confinement matrix

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

        let skillDirectory = try ResourceTestSupport.writeMinimalSkillFile(id: "escaper", in: root)
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

        let skillDirectory = try ResourceTestSupport.writeMinimalSkillFile(id: "escaper", in: root)
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

        let skillDirectory = try ResourceTestSupport.writeMinimalSkillFile(id: "many-files", in: root)
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
        // The row-count cap itself was never asserted -- `total: 150` alone
        // doesn't prove `resources` was actually truncated to 100 rather
        // than, say, silently returning all 150. Each row's `"path":` key
        // appears exactly once per row.
        #expect(json.components(separatedBy: "\"path\":").count - 1 == 100)
    }

    // MARK: - Hidden files skipped

    @Test func listResourceSkipsADotfile() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDirectory = try ResourceTestSupport.writeMinimalSkillFile(id: "has-dotfile", in: root)
        try "visible".write(
            to: skillDirectory.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(
            to: skillDirectory.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)

        let tool = try Self.makeTool(roots: [root])
        let arguments = GeneratedContent(properties: ["op": "list resource", "id": "has-dotfile"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"total\":1"))
        #expect(json.contains("\"path\":\"visible.txt\""))
        #expect(!json.contains(".hidden"))
    }

    // MARK: - Surface visibility

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
    ///   fixture library.
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


    // MARK: - The combined view of the layer directories

    /// The id of the skill that the layer directories of the combined-view
    /// tests give.
    private static let overlaySkillID = "overlay-resources"

    /// The path of the script that the lowest layer directory holds.
    private static let reportScriptPath = "scripts/report.sh"

    /// The path of the reference that the lowest layer directory holds. The
    /// shared-path fixture gives a copy of this same path to each of its two
    /// directories.
    private static let rulesReferencePath = "references/rules.md"

    /// The path of the script that the middle layer directory holds.
    private static let lintScriptPath = "scripts/lint.sh"

    /// The path of the reference that the highest layer directory holds.
    private static let houseStyleReferencePath = "references/house-style.md"

    /// The path of a file whose bytes are not UTF-8 text.
    private static let logoAssetPath = "assets/logo.png"

    /// Each resource path of the three-layer fixture. The `SKILL.md` of the
    /// skill is no resource, thus it is not here.
    private static let overlayResourcePaths = [
        Self.reportScriptPath, Self.rulesReferencePath, Self.lintScriptPath, Self.houseStyleReferencePath,
    ]

    /// The one line of the copy of a resource in the lower directory.
    ///
    /// It is shorter than the line of the higher copy, thus the byte count of
    /// a row says which copy the listing took.
    private static let lowerCopyLine = "The lower copy."

    /// The one line of the copy of a resource in the higher directory.
    private static let higherCopyLine = "The higher copy, and it is longer."

    /// The whole text of a file that holds `line`: the line and the newline
    /// that ends it.
    ///
    /// - Parameter line: The one line of the file.
    /// - Returns: The text to write.
    private static func fileText(of line: String) -> String {
        "\(line)\n"
    }

    /// Makes the three layer directories of the example: the lowest holds the
    /// `SKILL.md` of the skill, one script and one reference; the middle holds
    /// one script of its own; the highest holds one reference of its own.
    ///
    /// - Returns: The three layer directories, lowest precedence first.
    /// - Throws: Whatever `ResourceTestSupport` or `LayerFixtureSupport`
    ///   throws.
    private static func makeThreeLayerFixture() throws -> [URL] {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 3)
        try ResourceTestSupport.writeMinimalSkillFile(id: Self.overlaySkillID, in: directories[0])
        try Self.writeResource(at: Self.reportScriptPath, in: directories[0])
        try Self.writeResource(at: Self.rulesReferencePath, in: directories[0])
        try Self.writeResource(at: Self.lintScriptPath, in: directories[1])
        try Self.writeResource(at: Self.houseStyleReferencePath, in: directories[2])
        return directories
    }

    /// Makes two layer directories that each hold a copy of one reference
    /// path, and gives the `SKILL.md` of the skill to the lower one.
    ///
    /// The two copies differ in length and in text, thus a row and a read each
    /// say which copy they took.
    ///
    /// - Returns: The two layer directories, lowest precedence first.
    /// - Throws: Whatever `ResourceTestSupport` or `LayerFixtureSupport`
    ///   throws.
    private static func makeSharedPathFixture() throws -> [URL] {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 2)
        try ResourceTestSupport.writeMinimalSkillFile(id: Self.overlaySkillID, in: directories[0])
        try LayerFixtureSupport.writeTextFile(
            Self.fileText(of: Self.lowerCopyLine), at: Self.layerPath(of: Self.rulesReferencePath),
            in: directories[0])
        try LayerFixtureSupport.writeTextFile(
            Self.fileText(of: Self.higherCopyLine), at: Self.layerPath(of: Self.rulesReferencePath),
            in: directories[1])
        return directories
    }

    /// Writes one resource file of the skill in one layer directory.
    ///
    /// The text of the file names the layer directory, thus a read of the file
    /// says which copy it took.
    ///
    /// - Parameters:
    ///   - relativePath: The path of the file, relative to the skill
    ///     directory.
    ///   - directory: The layer directory to write in.
    /// - Throws: Whatever `LayerFixtureSupport.writeTextFile(at:in:)` throws.
    private static func writeResource(at relativePath: String, in directory: URL) throws {
        try LayerFixtureSupport.writeTextFile(at: Self.layerPath(of: relativePath), in: directory)
    }

    /// The path of one resource of the skill, relative to a layer directory.
    ///
    /// - Parameter relativePath: The path of the file, relative to the skill
    ///   directory.
    /// - Returns: The path with the skill directory in front of it.
    private static func layerPath(of relativePath: String) -> String {
        "\(Self.overlaySkillID)/\(relativePath)"
    }

    /// The `path` field of a row, as the JSON of a result spells it: the
    /// encoder writes `\/` for each `/`.
    ///
    /// - Parameter relativePath: The path of the row.
    /// - Returns: The text to look for in the JSON.
    private static func jsonPathField(of relativePath: String) -> String {
        "\"path\":\"\(relativePath.replacingOccurrences(of: "/", with: "\\/"))\""
    }

    /// The part of the text of a fixture file that names the layer directory
    /// that holds the copy.
    ///
    /// `LayerFixtureSupport.writeTextFile(at:in:)` ends the text with the name
    /// of the directory, thus this mark says which copy a read took.
    ///
    /// - Parameter directory: A layer directory of the fixture.
    /// - Returns: The text to look for in the JSON.
    private static func layerMark(of directory: URL) -> String {
        "in \(directory.lastPathComponent)."
    }

    /// Dispatches one `list resource` call of the skill of the combined-view
    /// tests over `roots`.
    ///
    /// - Parameter roots: The registry roots to build over, lowest precedence
    ///   first.
    /// - Returns: The raw JSON text of the dispatch.
    private static func listOverlayResources(roots: [URL]) async throws -> String {
        let tool = try Self.makeTool(roots: roots)
        return try await tool.call(
            arguments: GeneratedContent(properties: ["op": "list resource", "id": Self.overlaySkillID]))
    }

    @Test func listResourceGivesEachPathOfEveryLayerDirectoryOneTime() async throws {
        let directories = try Self.makeThreeLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let json = try await Self.listOverlayResources(roots: directories)

        #expect(json.contains("\"total\":\(Self.overlayResourcePaths.count)"))
        #expect(json.components(separatedBy: "\"path\":").count - 1 == Self.overlayResourcePaths.count)
        for path in Self.overlayResourcePaths {
            #expect(json.contains(Self.jsonPathField(of: path)))
        }
    }

    @Test func listResourceGivesAFileOfBytesWithTheAssetKindAndItsSize() async throws {
        let directories = try Self.makeThreeLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let assetURL = try LayerFixtureSupport.writeBytesFile(
            at: Self.layerPath(of: Self.logoAssetPath), in: directories[2])
        let byteSize = try #require(
            FileManager.default.attributesOfItem(atPath: assetURL.path)[.size] as? Int)

        let json = try await Self.listOverlayResources(roots: directories)

        #expect(
            json.contains(
                "\"bytes\":\(byteSize),\"executable\":false,\"kind\":\"asset\","
                    + Self.jsonPathField(of: Self.logoAssetPath)))
    }

    @Test func listResourceGivesOneRowOfTheHigherCopyForAPathThatTwoDirectoriesHold() async throws {
        let directories = try Self.makeSharedPathFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let higherByteSize = Self.fileText(of: Self.higherCopyLine).utf8.count

        let json = try await Self.listOverlayResources(roots: directories)

        #expect(json.contains("\"total\":1"))
        #expect(
            json.contains(
                "\"bytes\":\(higherByteSize),\"executable\":false,\"kind\":\"reference\","
                    + Self.jsonPathField(of: Self.rulesReferencePath)))
    }

    @Test func listResourceMarksAScriptExecutableThatOnlyTheLowestDirectoryHolds() async throws {
        let directories = try Self.makeThreeLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }
        try LayerFixtureSupport.makeExecutable(
            directories[0].appendingPathComponent(Self.layerPath(of: Self.reportScriptPath)))

        let json = try await Self.listOverlayResources(roots: directories)

        #expect(
            json.contains(
                "\"executable\":true,\"kind\":\"script\"," + Self.jsonPathField(of: Self.reportScriptPath)))
    }

    @Test func listResourceTakesTheExecutableBitOfTheHigherCopyForAPathThatTwoDirectoriesHold() async throws {
        let directories = try Self.makeSharedPathFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }
        try LayerFixtureSupport.makeExecutable(
            directories[0].appendingPathComponent(Self.layerPath(of: Self.rulesReferencePath)))

        let json = try await Self.listOverlayResources(roots: directories)

        #expect(
            json.contains(
                "\"executable\":false,\"kind\":\"reference\","
                    + Self.jsonPathField(of: Self.rulesReferencePath)))
    }

    @Test func readResourceGivesTheCopyOfTheMiddleDirectoryForAScriptOnlyItHolds() async throws {
        let directories = try Self.makeThreeLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let json = try await Self.readResource(
            roots: directories, id: Self.overlaySkillID, path: Self.lintScriptPath)

        #expect(!Self.isCorrective(json))
        #expect(json.contains(Self.layerMark(of: directories[1])))
    }

    @Test func readResourceGivesTheCopyOfTheLowestDirectoryForAScriptOnlyItHolds() async throws {
        let directories = try Self.makeThreeLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let json = try await Self.readResource(
            roots: directories, id: Self.overlaySkillID, path: Self.reportScriptPath)

        #expect(!Self.isCorrective(json))
        #expect(json.contains(Self.layerMark(of: directories[0])))
    }

    @Test func readResourceGivesTheCopyOfTheHigherDirectoryForAPathThatTwoDirectoriesHold() async throws {
        let directories = try Self.makeSharedPathFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let json = try await Self.readResource(
            roots: directories, id: Self.overlaySkillID, path: Self.rulesReferencePath)

        #expect(json.contains("\"content\":\"\(Self.higherCopyLine)\""))
        #expect(!json.contains(Self.lowerCopyLine))
    }
}
