import Foundation
import Testing

@testable import FoundationModelsSkills

/// Proves the snapshot writer of marketplace.md §7.3 steps 3 and 4: one flat
/// folder that holds `<skill>/` for each selected skill and `_partials/`, the
/// execute bit, the validation rules, and the diagnostics.
///
/// Each test writes into its own temporary folder, so no test reads the files
/// of another test. The happy path reads a fixture catalog through
/// ``LocalCatalogFileSource``. The rejection tests read an in-memory source,
/// because a folder on the disk cannot hold a submodule entry and a test
/// should not need a name that the file system itself refuses.
@Suite("Marketplace snapshot writer")
struct SnapshotWriterTests {
    // MARK: - Fixture

    /// The fixture catalog of the happy path: three skills and one partial.
    private static let fixtureName = "swissarmyhammer-skills"

    /// The skill ids of ``fixtureName``.
    private static let fixtureSkillIDs: Set<String> = ["code-context", "commit", "tdd"]

    /// The number of files that a full snapshot of ``fixtureName`` holds:
    /// three `SKILL.md` files, one extra file of the `tdd` skill, and one
    /// partial.
    private static let fixtureFileCount = 5

    /// The tree path of the first file that a full snapshot of
    /// ``fixtureName`` copies. The catalog lists `code-context` first.
    private static let fixtureFirstFilePath = "skills/code-context/SKILL.md"

    /// The tree path of the second file that a full snapshot of
    /// ``fixtureName`` copies. A limit of one file permits the first file,
    /// so this file is the one that reaches the limit.
    private static let fixtureSecondFilePath = "skills/commit/SKILL.md"

    /// Limits that no test tree reaches.
    private static let generousLimits = SnapshotLimits(maxBytes: 1 << 20, maxFiles: 100)

    /// A limit of one, to prove that the writer counts.
    private static let limitOfOne = 1

    /// The permissions that an executable file of a snapshot has.
    private static let executablePermissions = 0o755

    /// A temporary folder, and the snapshot folder that the writer makes
    /// inside it.
    private struct Destination {
        /// The temporary folder that holds the snapshot folder.
        let parent: URL

        /// The folder that the writer makes. It does not exist yet.
        var folder: URL {
            parent.appendingPathComponent("snapshot", isDirectory: true)
        }

        /// Whether the writer left the snapshot folder on the disk.
        var folderExists: Bool {
            FileManager.default.fileExists(atPath: folder.path)
        }

        /// Makes a new temporary folder.
        ///
        /// - Throws: The error of the folder.
        init() throws {
            parent = try MarketplaceTestSupport.makeTempDirectory()
        }

        /// Deletes the temporary folder.
        func remove() {
            try? FileManager.default.removeItem(at: parent)
        }

        /// The names of the items of one folder of the snapshot, in order.
        ///
        /// - Parameter relativePath: The folder, relative to ``folder``. The
        ///   empty path is ``folder`` itself.
        /// - Returns: The names, sorted.
        /// - Throws: The error of the folder read.
        func names(inFolder relativePath: String = "") throws -> [String] {
            let url = relativePath.isEmpty ? folder : folder.appendingPathComponent(relativePath)
            return try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
        }

        /// The text of one file of the snapshot.
        ///
        /// - Parameter relativePath: The file, relative to ``folder``.
        /// - Returns: The text of the file.
        /// - Throws: The error of the file read.
        func text(ofFile relativePath: String) throws -> String {
            try String(contentsOf: folder.appendingPathComponent(relativePath), encoding: .utf8)
        }
    }

    /// A ``CatalogFileSource`` that holds one tree in memory.
    ///
    /// A folder on the disk cannot hold a submodule entry, and the file
    /// system refuses a name such as `..`, so the rejection tests need a
    /// source that gives the writer exactly the entries of the test.
    private struct MemoryCatalogFileSource: CatalogFileSource {
        /// The text of each file, keyed by its tree path.
        var files: [String: String] = [:]

        /// The items of each folder, keyed by its tree path.
        var listings: [String: [CatalogTreeEntry]] = [:]

        /// Reads the bytes of one file.
        ///
        /// - Parameter path: The tree path of the file.
        /// - Returns: The bytes, or `nil` when no file is at the path.
        func contents(atPath path: String) throws -> Data? {
            files[path].map { Data($0.utf8) }
        }

        /// Lists the items of one folder.
        ///
        /// - Parameter path: The tree path of the folder.
        /// - Returns: The items, or an empty list when no folder is at the
        ///   path.
        func entries(inDirectory path: String) throws -> [CatalogTreeEntry] {
            listings[path] ?? []
        }
    }

    /// Makes a source and a catalog of one skill folder that holds the given
    /// items, for the rejection tests.
    ///
    /// - Parameters:
    ///   - entries: The items of the skill folder.
    ///   - files: The text of each file of the skill folder, keyed by its
    ///     name. The default is no file.
    /// - Returns: The source and the catalog that names the one skill.
    private static func oneSkill(
        holding entries: [CatalogTreeEntry], files: [String: String] = [:]
    ) -> (source: MemoryCatalogFileSource, catalog: ResolvedCatalog) {
        let folder = "tool"
        let source = MemoryCatalogFileSource(
            files: Dictionary(uniqueKeysWithValues: files.map { ("\(folder)/\($0.key)", $0.value) }),
            listings: [folder: entries])
        let catalog = ResolvedCatalog(
            name: "memory", version: nil,
            skills: [ResolvedSkill(name: folder, path: folder, plugin: nil)],
            renames: [:], diagnostics: [])
        return (source, catalog)
    }

    /// Writes a snapshot of one fixture catalog.
    ///
    /// - Parameters:
    ///   - name: The folder name of the fixture.
    ///   - selection: The skills that the host takes.
    ///   - destination: The folder that the writer makes.
    ///   - limits: The policy limits of the write.
    /// - Returns: The report of the write.
    /// - Throws: The error of the write.
    private static func writeFixture(
        named name: String, selection: SkillSelection, to destination: Destination,
        limits: SnapshotLimits = generousLimits
    ) throws -> SnapshotReport {
        let source = LocalCatalogFileSource(root: FixtureLibrary.marketplaceCatalog(named: name))
        let catalog = CatalogResolver.resolve(from: source, selection: selection)
        return try SnapshotWriter.write(
            catalog: catalog, from: source, to: destination.folder, limits: limits)
    }

    // MARK: - Happy path

    @Test func aSnapshotOfAFixtureCatalogLoadsAsALayerRoot() throws {
        let destination = try Destination()
        defer { destination.remove() }

        let report = try Self.writeFixture(named: Self.fixtureName, selection: .all, to: destination)

        #expect(report.diagnostics.isEmpty)
        #expect(report.fileCount == Self.fixtureFileCount)
        #expect(report.byteCount > 0)
        let registry = SkillsRegistry(roots: [destination.folder])
        #expect(Set(registry.metadata().map(\.id)) == Self.fixtureSkillIDs)
    }

    @Test func aSkillSelectionKeepsOnlyTheChosenSkills() throws {
        let destination = try Destination()
        defer { destination.remove() }

        _ = try Self.writeFixture(named: Self.fixtureName, selection: .skills(["tdd"]), to: destination)

        #expect(try destination.names() == ["_partials", "tdd"])
    }

    @Test func thePartialsFolderOfASelectedSkillFolderIsCopied() throws {
        let destination = try Destination()
        defer { destination.remove() }

        _ = try Self.writeFixture(named: Self.fixtureName, selection: .all, to: destination)

        #expect(try destination.names(inFolder: "_partials") == ["sah-task-standards.md"])
    }

    @Test func aDuplicatePartialNameGivesADiagnosticAndTheLaterFolderWins() throws {
        let destination = try Destination()
        defer { destination.remove() }
        let root = try MarketplaceTestSupport.makeTempDirectory(withFiles: Self.twoPartialFolderTree)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = LocalCatalogFileSource(root: root)
        let catalog = CatalogResolver.resolve(from: source, selection: .all)

        let report = try SnapshotWriter.write(
            catalog: catalog, from: source, to: destination.folder, limits: Self.generousLimits)

        #expect(report.diagnostics.count == 1)
        #expect(report.diagnostics.first?.severity == .warning)
        #expect(try destination.text(ofFile: "_partials/shared.md") == "from second")
    }

    /// A tree with two plugins, each with its own `_partials/shared.md`.
    private static let twoPartialFolderTree: [String: String] = [
        ".claude-plugin/marketplace.json": """
            {
              "name": "two-plugins",
              "plugins": [
                { "name": "first", "source": "./first" },
                { "name": "second", "source": "./second" }
              ]
            }
            """,
        "first/skills/alpha/SKILL.md": skillFile(named: "alpha"),
        "first/skills/_partials/shared.md": "from first",
        "second/skills/beta/SKILL.md": skillFile(named: "beta"),
        "second/skills/_partials/shared.md": "from second",
    ]

    /// The text of one fixture `SKILL.md` file.
    ///
    /// - Parameter name: The frontmatter name of the skill.
    /// - Returns: The text of the file.
    private static func skillFile(named name: String) -> String {
        """
        ---
        name: \(name)
        description: A fixture skill of the snapshot writer tests.
        ---

        The body of \(name).
        """
    }

    // MARK: - The execute bit

    @Test func anExecutableFileKeepsModeSevenFiveFive() throws {
        let destination = try Destination()
        defer { destination.remove() }
        let tree = Self.oneSkill(
            holding: [
                CatalogTreeEntry(name: "SKILL.md", kind: .file(isExecutable: false)),
                CatalogTreeEntry(name: "run.sh", kind: .file(isExecutable: true)),
            ],
            files: ["SKILL.md": Self.skillFile(named: "tool"), "run.sh": "#!/bin/sh\necho hello\n"])

        _ = try SnapshotWriter.write(
            catalog: tree.catalog, from: tree.source, to: destination.folder, limits: Self.generousLimits)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: destination.folder.appendingPathComponent("tool/run.sh").path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue == Self.executablePermissions)
    }

    // MARK: - Rejections

    @Test func anEntryNameWithTwoDotsIsRejectedAndNoFolderStays() throws {
        let destination = try Destination()
        defer { destination.remove() }
        let tree = Self.oneSkill(holding: [CatalogTreeEntry(name: "..", kind: .file(isExecutable: false))])

        #expect(throws: SnapshotError.unsafeEntryName(directory: "tool", name: "..")) {
            _ = try SnapshotWriter.write(
                catalog: tree.catalog, from: tree.source, to: destination.folder, limits: Self.generousLimits)
        }
        #expect(!destination.folderExists)
    }

    @Test func anEntryNameWithASeparatorIsRejectedAndNoFolderStays() throws {
        let destination = try Destination()
        defer { destination.remove() }
        let tree = Self.oneSkill(holding: [CatalogTreeEntry(name: "a/b", kind: .file(isExecutable: false))])

        #expect(throws: SnapshotError.unsafeEntryName(directory: "tool", name: "a/b")) {
            _ = try SnapshotWriter.write(
                catalog: tree.catalog, from: tree.source, to: destination.folder, limits: Self.generousLimits)
        }
        #expect(!destination.folderExists)
    }

    @Test func aSymlinkThatLeavesTheSkillFolderIsRejectedAndNoFolderStays() throws {
        let destination = try Destination()
        defer { destination.remove() }
        let target = "../../outside.md"
        let tree = Self.oneSkill(holding: [CatalogTreeEntry(name: "link.md", kind: .symlink(target: target))])

        #expect(throws: SnapshotError.escapingSymlink(path: "tool/link.md", target: target)) {
            _ = try SnapshotWriter.write(
                catalog: tree.catalog, from: tree.source, to: destination.folder, limits: Self.generousLimits)
        }
        #expect(!destination.folderExists)
    }

    @Test func aSymlinkThatStaysInTheSkillFolderIsCopied() throws {
        let destination = try Destination()
        defer { destination.remove() }
        let tree = Self.oneSkill(
            holding: [
                CatalogTreeEntry(name: "SKILL.md", kind: .file(isExecutable: false)),
                CatalogTreeEntry(name: "link.md", kind: .symlink(target: "SKILL.md")),
            ],
            files: ["SKILL.md": Self.skillFile(named: "tool")])

        _ = try SnapshotWriter.write(
            catalog: tree.catalog, from: tree.source, to: destination.folder, limits: Self.generousLimits)

        let link = destination.folder.appendingPathComponent("tool/link.md").path
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link) == "SKILL.md")
    }

    @Test func aSubmoduleEntryIsRejectedAndNoFolderStays() throws {
        let destination = try Destination()
        defer { destination.remove() }
        let tree = Self.oneSkill(holding: [CatalogTreeEntry(name: "vendor", kind: .submodule)])

        #expect(throws: SnapshotError.submodule(path: "tool/vendor")) {
            _ = try SnapshotWriter.write(
                catalog: tree.catalog, from: tree.source, to: destination.folder, limits: Self.generousLimits)
        }
        #expect(!destination.folderExists)
    }

    // MARK: - Limits

    @Test func aFileCountAboveTheLimitIsRejectedAndNoFolderStays() throws {
        let destination = try Destination()
        defer { destination.remove() }
        let limits = SnapshotLimits(maxBytes: Self.generousLimits.maxBytes, maxFiles: Self.limitOfOne)

        #expect(
            throws: SnapshotError.tooManyFiles(path: Self.fixtureSecondFilePath, limit: Self.limitOfOne)
        ) {
            _ = try Self.writeFixture(
                named: Self.fixtureName, selection: .all, to: destination, limits: limits)
        }
        #expect(!destination.folderExists)
    }

    @Test func aByteCountAboveTheLimitIsRejectedAndNoFolderStays() throws {
        let destination = try Destination()
        defer { destination.remove() }
        let limits = SnapshotLimits(maxBytes: Self.limitOfOne, maxFiles: Self.generousLimits.maxFiles)

        #expect(
            throws: SnapshotError.tooManyBytes(path: Self.fixtureFirstFilePath, limit: Self.limitOfOne)
        ) {
            _ = try Self.writeFixture(
                named: Self.fixtureName, selection: .all, to: destination, limits: limits)
        }
        #expect(!destination.folderExists)
    }

    // MARK: - Large file storage

    @Test func aLargeFileStoragePointerIsWrittenAndGivesADiagnostic() throws {
        let destination = try Destination()
        defer { destination.remove() }
        let pointer = """
            \(SnapshotWriter.largeFileStoragePrefix)
            oid sha256:0123456789abcdef
            size 12345

            """
        let tree = Self.oneSkill(
            holding: [
                CatalogTreeEntry(name: "SKILL.md", kind: .file(isExecutable: false)),
                CatalogTreeEntry(name: "diagram.png", kind: .file(isExecutable: false)),
            ],
            files: ["SKILL.md": Self.skillFile(named: "tool"), "diagram.png": pointer])

        let report = try SnapshotWriter.write(
            catalog: tree.catalog, from: tree.source, to: destination.folder, limits: Self.generousLimits)

        #expect(report.diagnostics.count == 1)
        #expect(report.diagnostics.first?.severity == .warning)
        #expect(report.diagnostics.first?.message.contains("tool/diagram.png") == true)
        #expect(try destination.text(ofFile: "tool/diagram.png") == pointer)
    }
}
