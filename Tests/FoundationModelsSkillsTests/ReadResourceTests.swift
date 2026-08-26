import Foundation
import FoundationModels
import FoundationModelsSkills
import Testing

/// Tests for `ReadResource` that call the operation directly, without the
/// fused `skills` tool in front of it: the memberwise initializer, the
/// `generatedContent` round trip, the unreadable-file corrective, and the
/// empty window. `ResourceOpsTests` covers the same operation through the
/// tool's dispatch.
struct ReadResourceTests {
    /// The skill id every direct-construction test names.
    private static let sampleID = "release-notes"

    /// The resource path every direct-construction test names.
    private static let samplePath = "references/changelog.md"

    /// The first line the round-trip tests ask for.
    private static let sampleStart = 3

    /// The last line the round-trip tests ask for.
    private static let sampleEnd = 7

    /// The line count of the short fixture the empty-window test reads.
    private static let shortFixtureLineCount = 3

    /// The first line the empty-window test asks for; past the end of the
    /// short fixture, so the window holds no line.
    private static let emptyWindowStart = 10

    /// The file mode that refuses every read.
    private static let unreadableMode = 0o000

    /// Whether the test process is root. Root reads a mode-`0o000` file, so
    /// the unreadable-file corrective cannot be reached under root.
    private static var isRoot: Bool { geteuid() == 0 }

    /// The corrective `ReadResource` draws for a confined path it cannot read.
    ///
    /// - Parameter path: The path that could not be read.
    /// - Returns: The message, in the operation's own wording.
    private static func unreadableMessage(path: String) -> String {
        "The path `\(path)` could not be read."
    }

    /// The package's own `.build` directory, whose real path is its path.
    private static let buildScratchParent = FixtureLibrary.packageRoot()
        .appendingPathComponent(".build", isDirectory: true)

    /// The macOS temp directory. `SkillDiscovery` lists a root under it as
    /// `/private/var/...`, and `resolvingSymlinksInPath()` resolves a path
    /// that exists under it to `/var/...`, so a missing path under such a
    /// root is the case ^2dzxvms fixed in `PathConfinement`.
    private static let temporaryScratchParent = FileManager.default.temporaryDirectory

    /// Creates a fresh scratch root under `parent`.
    ///
    /// - Parameter parent: The directory to create the root in.
    /// - Returns: The created directory. The caller removes it.
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    private static func makeScratchRoot(under parent: URL) throws -> URL {
        let root = parent.appendingPathComponent("ReadResourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Writes a skill under a fresh scratch root and reads `path` inside it.
    ///
    /// - Parameters:
    ///   - id: The skill id to write and read.
    ///   - path: The resource path to read, relative to the skill directory.
    ///   - start: The first line to return, or `nil` for the default.
    ///   - scratchParent: The directory to create the scratch root in.
    ///     Defaults to the package's own `.build` directory.
    ///   - prepare: Populates the skill directory before the read.
    /// - Returns: The operation's output.
    private static func read(
        id: String, path: String, start: Int? = nil, scratchParent: URL = Self.buildScratchParent,
        prepare: (URL) throws -> Void
    ) async throws -> ReadResourceOutput {
        let root = try Self.makeScratchRoot(under: scratchParent)
        defer { try? FileManager.default.removeItem(at: root) }
        let skillDirectory = try ResourceTestSupport.writeMinimalSkillFile(id: id, in: root)
        try prepare(skillDirectory)
        let context = ResourceTestSupport.makeContext(roots: [root])
        return try await ReadResource(id: id, path: path, start: start).execute(in: context)
    }

    // MARK: - Memberwise initializer

    @Test func memberwiseInitStoresEveryParameter() {
        let operation = ReadResource(
            id: Self.sampleID, path: Self.samplePath, start: Self.sampleStart, end: Self.sampleEnd)

        #expect(operation.id == Self.sampleID)
        #expect(operation.path == Self.samplePath)
        #expect(operation.start == Self.sampleStart)
        #expect(operation.end == Self.sampleEnd)
    }

    @Test func memberwiseInitDefaultsStartAndEndToNil() {
        let operation = ReadResource(id: Self.sampleID, path: Self.samplePath)

        #expect(operation.id == Self.sampleID)
        #expect(operation.path == Self.samplePath)
        #expect(operation.start == nil)
        #expect(operation.end == nil)
    }

    // MARK: - generatedContent / init(_:) round trips

    @Test func roundTripsThroughGeneratedContentWithStartAndEndPresent() throws {
        let original = ReadResource(
            id: Self.sampleID, path: Self.samplePath, start: Self.sampleStart, end: Self.sampleEnd)

        let decoded = try ReadResource(original.generatedContent)

        #expect(decoded.id == original.id)
        #expect(decoded.path == original.path)
        #expect(decoded.start == original.start)
        #expect(decoded.end == original.end)
    }

    @Test func roundTripsThroughGeneratedContentWithNoStartOrEnd() throws {
        let original = ReadResource(id: Self.sampleID, path: Self.samplePath)

        let content = original.generatedContent
        let decoded = try ReadResource(content)

        #expect(decoded.id == original.id)
        #expect(decoded.path == original.path)
        #expect(decoded.start == nil)
        #expect(decoded.end == nil)
        #expect(!content.jsonString.contains("\"start\""))
        #expect(!content.jsonString.contains("\"end\""))
    }

    // MARK: - Unreadable-file correctives

    @Test func readResourceOnAMissingFileDrawsTheUnreadableCorrective() async throws {
        // No file at all is what fails the `fileSize(at:)` stat guard; a
        // dangling link stats to the link's own size and fails at the open.
        let context = ResourceTestSupport.makeContext(roots: [FixtureLibrary.url(relativePath: "project/.skills")])

        let output = try await ReadResource(id: Self.sampleID, path: "references/missing.md").execute(in: context)

        #expect(output == .corrective(Self.unreadableMessage(path: "references/missing.md")))
    }

    @Test func readResourceOnADanglingSymlinkDrawsTheUnreadableCorrective() async throws {
        let output = try await Self.read(id: "dangling", path: "dangling-link") { skillDirectory in
            try FileManager.default.createSymbolicLink(
                at: skillDirectory.appendingPathComponent("dangling-link"),
                withDestinationURL: skillDirectory.appendingPathComponent("missing.txt"))
        }

        #expect(output == .corrective(Self.unreadableMessage(path: "dangling-link")))
    }

    @Test func readResourceOnAMissingFileUnderATemporaryRootDrawsTheUnreadableCorrective() async throws {
        let output = try await Self.read(
            id: "temporary-missing", path: "references/missing.md", scratchParent: Self.temporaryScratchParent
        ) { _ in }

        #expect(output == .corrective(Self.unreadableMessage(path: "references/missing.md")))
    }

    @Test func readResourceOnADanglingSymlinkUnderATemporaryRootDrawsTheUnreadableCorrective() async throws {
        let output = try await Self.read(
            id: "temporary-dangling", path: "dangling-link", scratchParent: Self.temporaryScratchParent
        ) { skillDirectory in
            try FileManager.default.createSymbolicLink(
                at: skillDirectory.appendingPathComponent("dangling-link"),
                withDestinationURL: skillDirectory.appendingPathComponent("missing.txt"))
        }

        #expect(output == .corrective(Self.unreadableMessage(path: "dangling-link")))
    }

    @Test(.enabled(if: !ReadResourceTests.isRoot, "Root reads a mode-0o000 file, so the corrective is unreachable."))
    func readResourceOnAFileWithNoReadPermissionDrawsTheUnreadableCorrective() async throws {
        let output = try await Self.read(id: "forbidden", path: "secret.txt") { skillDirectory in
            let fileURL = skillDirectory.appendingPathComponent("secret.txt")
            try "top secret\n".write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: Self.unreadableMode], ofItemAtPath: fileURL.path)
        }

        #expect(output == .corrective(Self.unreadableMessage(path: "secret.txt")))
    }

    // MARK: - Empty window

    @Test func readResourcePastTheLastLineReturnsAnEmptyWindowEndingBeforeStart() async throws {
        let output = try await Self.read(id: "short", path: "short.txt", start: Self.emptyWindowStart) {
            skillDirectory in
            let lines = (1...Self.shortFixtureLineCount).map { "line \($0)" }
            try (lines.joined(separator: "\n") + "\n")
                .write(to: skillDirectory.appendingPathComponent("short.txt"), atomically: true, encoding: .utf8)
        }

        let expected = ReadResourceResult(
            id: "short", path: "short.txt", content: "", start: Self.emptyWindowStart,
            end: Self.emptyWindowStart - 1, totalLines: Self.shortFixtureLineCount)
        #expect(output == .success(expected))
    }
}
