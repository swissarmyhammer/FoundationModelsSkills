import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsSkills

/// Tests for `ReadResource` that call the operation directly, without the
/// fused `skills` tool in front of it: the memberwise initializer, the
/// `generatedContent` round trip, the unreadable-file corrective, the
/// denied-path corrective, the absolute paths, the binary files, and the
/// empty window.
/// `ResourceOpsTests` covers the same operation through the tool's dispatch.
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
    /// `/private/var/...`, and a resolution of the symbolic links gives
    /// `/var/...` for a path that exists under it, so a missing path under
    /// such a root is a case that the confinement rule must handle.
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
        let context = ResourceTestSupport.makeContext(roots: [ResourceTestSupport.projectSkillsRoot])

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

    // MARK: - Denied-path correctives

    @Test func readResourceOnAPathThatWalksUpDrawsTheDeniedCorrective() async throws {
        let output = try await Self.read(id: "walker", path: "../outside.md") { _ in }

        #expect(output == .corrective(ResourcePathRules.deniedMessage(path: "../outside.md")))
    }

    /// A symbolic link inside the skill that points at a directory outside it.
    /// The file is there through the link, and the path leaves the skill, thus
    /// the read is denied and not reported as unreadable.
    @Test func readResourceOnASymbolicLinkThatLeavesTheSkillDrawsTheDeniedCorrective() async throws {
        let output = try await Self.read(id: "escaper", path: "escape/secret.md") { skillDirectory in
            let outside = skillDirectory.deletingLastPathComponent()
                .appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try "top secret\n".write(
                to: outside.appendingPathComponent("secret.md"), atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(
                at: skillDirectory.appendingPathComponent("escape"), withDestinationURL: outside)
        }

        #expect(output == .corrective(ResourcePathRules.deniedMessage(path: "escape/secret.md")))
    }

    // MARK: - Absolute paths

    /// The id of the skill that the two layer directories of the layered
    /// test give.
    private static let layeredSkillID = "layered"

    /// The text of the copy of the lower layer.
    private static let lowerLayerText = "lower layer"

    /// The text of the copy of the higher layer.
    private static let higherLayerText = "higher layer"

    /// The absolute path of `samplePath` in the `release-notes` fixture skill.
    private static var absoluteSamplePath: String {
        ResourceTestSupport.absoluteSkillFilePath(
            root: ResourceTestSupport.projectSkillsRoot, id: sampleID, path: samplePath)
    }

    /// The model can give the absolute path of a file of the skill. The read
    /// gives the same content as the relative read, and the result names the
    /// relative path.
    @Test func anAbsoluteReadGivesTheResultOfTheRelativeRead() async throws {
        let context = ResourceTestSupport.makeContext(roots: [ResourceTestSupport.projectSkillsRoot])

        let relativeOutput = try await ReadResource(id: Self.sampleID, path: Self.samplePath).execute(in: context)
        let absoluteOutput = try await ReadResource(id: Self.sampleID, path: Self.absoluteSamplePath)
            .execute(in: context)

        let relativeResult = try #require(ResourceTestSupport.successResult(of: relativeOutput))
        let absoluteResult = try #require(ResourceTestSupport.successResult(of: absoluteOutput))
        #expect(absoluteResult == relativeResult)
        #expect(absoluteResult.path == Self.samplePath)
    }

    /// An absolute path into a lower layer reads the copy of the highest
    /// layer that holds the same relative path.
    @Test func anAbsolutePathIntoALowerLayerReadsTheCopyOfTheHigherLayer() async throws {
        let roots = try LayerFixtureSupport.makeLayerDirectories(count: 2)
        defer { LayerFixtureSupport.removeDirectories(roots) }
        let skillDirectories = try roots.map {
            try ResourceTestSupport.writeMinimalSkillFile(id: Self.layeredSkillID, in: $0)
        }
        let lowerCopy = try LayerFixtureSupport.writeTextFile(
            Self.lowerLayerText, at: Self.samplePath, in: skillDirectories[0])
        try LayerFixtureSupport.writeTextFile(Self.higherLayerText, at: Self.samplePath, in: skillDirectories[1])

        let output = try await ReadResource(id: Self.layeredSkillID, path: lowerCopy.path)
            .execute(in: ResourceTestSupport.makeContext(roots: roots))

        let result = try #require(ResourceTestSupport.successResult(of: output))
        #expect(result.content == Self.higherLayerText)
        #expect(result.path == Self.samplePath)
    }

    /// The denied corrective names the path that the model gave.
    @Test func anAbsolutePathOutsideTheSkillDrawsTheDeniedCorrective() async throws {
        let context = ResourceTestSupport.makeContext(roots: [ResourceTestSupport.projectSkillsRoot])
        let path = ResourceTestSupport.systemFilePath

        let output = try await ReadResource(id: Self.sampleID, path: path).execute(in: context)

        #expect(output == .corrective(ResourcePathRules.deniedMessage(path: path)))
    }

    // MARK: - Binary files

    /// The path of the binary asset of the `release-notes` fixture skill.
    private static let binaryAssetPath = "assets/logo.bin"

    /// The path of the binary file of the layered binary test.
    private static let layeredBinaryPath = "assets/logo.png"

    /// The read of a binary file gives the absolute path of the winning copy.
    /// That path, given back as `path`, gives the same binary result.
    @Test func theAbsolutePathOfABinaryReadGivesTheSameBinaryResult() async throws {
        let context = ResourceTestSupport.makeContext(roots: [ResourceTestSupport.projectSkillsRoot])

        let firstOutput = try await ReadResource(id: Self.sampleID, path: Self.binaryAssetPath).execute(in: context)
        let firstResult = try #require(ResourceTestSupport.successResult(of: firstOutput))
        let absolutePath = try #require(firstResult.absolutePath)
        let secondOutput = try await ReadResource(id: Self.sampleID, path: absolutePath).execute(in: context)

        let secondResult = try #require(ResourceTestSupport.successResult(of: secondOutput))
        #expect(firstResult.binary)
        #expect(
            absolutePath
                == ResourceTestSupport.absoluteSkillFilePath(
                    root: ResourceTestSupport.projectSkillsRoot, id: Self.sampleID, path: Self.binaryAssetPath))
        #expect(secondResult == firstResult)
    }

    /// A binary file that only a lower layer holds gives the absolute path of
    /// the copy of that lower layer.
    @Test func aBinaryFileOfALowerLayerOnlyGivesTheAbsolutePathOfTheLowerCopy() async throws {
        let roots = try LayerFixtureSupport.makeLayerDirectories(count: 2)
        defer { LayerFixtureSupport.removeDirectories(roots) }
        let skillDirectories = try roots.map {
            try ResourceTestSupport.writeMinimalSkillFile(id: Self.layeredSkillID, in: $0)
        }
        let lowerCopy = try LayerFixtureSupport.writeBytesFile(at: Self.layeredBinaryPath, in: skillDirectories[0])
        let byteSize = try #require(
            FileManager.default.attributesOfItem(atPath: lowerCopy.path)[.size] as? Int)

        let output = try await ReadResource(id: Self.layeredSkillID, path: Self.layeredBinaryPath)
            .execute(in: ResourceTestSupport.makeContext(roots: roots))

        let result = try #require(ResourceTestSupport.successResult(of: output))
        let absolutePath = try #require(result.absolutePath)
        let lowerCopySuffix = "\(roots[0].lastPathComponent)/\(Self.layeredSkillID)/\(Self.layeredBinaryPath)"
        #expect(result.binary)
        #expect(result.byteSize == byteSize)
        #expect(result.path == Self.layeredBinaryPath)
        #expect(absolutePath.hasSuffix(lowerCopySuffix))
        #expect(FileManager.default.fileExists(atPath: absolutePath))
        #expect(result.content.contains(absolutePath))
        #expect(result.content.contains("\(byteSize) bytes"))
        #expect(result.start == 0 && result.end == 0 && result.totalLines == 0)
    }

    // MARK: - Result kinds

    /// The absolute path that the result-kind tests give to the binary factory.
    private static let sampleAbsolutePath = "/skills/release-notes/assets/logo.bin"

    /// The byte size that the result-kind tests give to the binary factory.
    private static let sampleByteSize = 4_096

    /// The binary factory sets `binary`, `absolutePath` and `byteSize`
    /// together, gives no lines, and names the path and the size in `content`.
    @Test func theBinaryFactorySetsEveryBinaryFieldConsistently() {
        let result = ReadResourceResult.binaryFile(
            id: Self.sampleID, path: Self.binaryAssetPath,
            absolutePath: Self.sampleAbsolutePath, byteSize: Self.sampleByteSize)

        #expect(result.binary)
        #expect(result.absolutePath == Self.sampleAbsolutePath)
        #expect(result.byteSize == Self.sampleByteSize)
        #expect(result.start == 0 && result.end == 0 && result.totalLines == 0)
        #expect(result.content.contains(Self.sampleAbsolutePath))
        #expect(result.content.contains("\(Self.sampleByteSize) bytes"))
    }

    /// The text initializer gives a result that is not binary and that has
    /// no binary field.
    @Test func theTextInitializerGivesNoBinaryField() {
        let result = ReadResourceResult(
            id: Self.sampleID, path: Self.samplePath, content: "", start: Self.sampleStart,
            end: Self.sampleStart - 1, totalLines: Self.sampleEnd)

        #expect(!result.binary)
        #expect(result.absolutePath == nil)
        #expect(result.byteSize == nil)
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
