import Foundation
import Testing

@testable import FoundationModelsSkills

/// Tests for `SkillOverlay`, the combined view of one skill over the layer
/// directories that contribute to it: the union of the
/// paths, the copy of the highest directory, which directory gave the winning
/// copy, and which paths the overlay confines.
///
/// The directories of an overlay are ordered lowest precedence first, the
/// order of `DiscoveredSkill.contributingDirectories`.
struct SkillOverlayTests {
    /// The path of a file that the highest directory only holds.
    private static let higherOnlyPath = "references/house-style.md"

    /// The path of a file that the lowest directory only holds.
    private static let lowerOnlyPath = "scripts/report.sh"

    /// The path of a file that each directory holds.
    private static let sharedPath = "SKILL.md"

    /// The path of a file of bytes that are not UTF-8 text, which the lowest
    /// directory only holds.
    private static let bytesOnlyPath = "assets/logo.png"

    /// The path of a file that no directory of the fixture holds.
    private static let missingPath = "references/missing.md"

    /// The path of a file reached through a symbolic link that leaves the
    /// skill.
    private static let escapingPath = "escape/secret.md"

    // MARK: - The union of the paths

    @Test func entriesGiveTheUnionOfThePathsOfEveryDirectory() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let entries = SkillOverlay(directories: directories).entries()

        #expect(
            Set(entries.keys)
                == [Self.sharedPath, Self.lowerOnlyPath, Self.higherOnlyPath, Self.bytesOnlyPath])
    }

    @Test func entriesGiveAFileWhoseBytesAreNotText() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let entries = SkillOverlay(directories: directories).entries()

        #expect(
            entries[Self.bytesOnlyPath]?.path
                == directories[0].appendingPathComponent(Self.bytesOnlyPath).path)
    }

    @Test func entriesGiveTheCopyOfTheHighestDirectoryForAPathThatTwoDirectoriesHold() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let entries = SkillOverlay(directories: directories).entries()

        #expect(entries[Self.sharedPath]?.path == directories[1].appendingPathComponent(Self.sharedPath).path)
    }

    @Test func entriesGiveTheCopyOfTheLowestDirectoryForAPathThatOnlyItHolds() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let entries = SkillOverlay(directories: directories).entries()

        #expect(entries[Self.lowerOnlyPath]?.path == directories[0].appendingPathComponent(Self.lowerOnlyPath).path)
    }

    // MARK: - The directory that gave the winning copy

    @Test func resolveNamesTheLowestDirectoryForAPathThatOnlyItHolds() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let winner = try #require(SkillOverlay(directories: directories).resolve(Self.lowerOnlyPath))

        #expect(winner.directoryIndex == 0)
        #expect(winner.url.path == directories[0].appendingPathComponent(Self.lowerOnlyPath).path)
    }

    @Test func resolveNamesTheHighestDirectoryForAPathThatTwoDirectoriesHold() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let winner = try #require(SkillOverlay(directories: directories).resolve(Self.sharedPath))

        #expect(winner.directoryIndex == 1)
        #expect(winner.url.path == directories[1].appendingPathComponent(Self.sharedPath).path)
    }

    @Test func resolveDeniesAPathThatLeavesEachDirectory() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        #expect(SkillOverlay(directories: directories).resolve("../outside.md") == nil)
    }

    /// Only a copy that exists resolves. A caller that gets nothing back then
    /// asks `confines(_:)` whether the path is denied or simply not there.
    @Test func resolveGivesNothingForAPathThatNoDirectoryHolds() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        #expect(SkillOverlay(directories: directories).resolve(Self.missingPath) == nil)
    }

    // MARK: - The paths the overlay confines

    /// A well-formed path that no directory holds is confined: the caller
    /// reports that the file could not be read, and not that it is denied.
    @Test func aWellFormedPathThatNoDirectoryHoldsIsConfined() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        #expect(SkillOverlay(directories: directories).confines(Self.missingPath))
    }

    @Test func aPathThatWalksUpIsNotConfined() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        #expect(!SkillOverlay(directories: directories).confines("../outside.md"))
    }

    /// A symbolic link in the highest directory that points at a directory
    /// outside the skill: the file is there, and the path leaves the skill,
    /// thus the overlay does not confine it.
    @Test func aPathThatLeavesTheSkillThroughASymbolicLinkIsNotConfined() throws {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 3)
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let outside = directories[2]
        try LayerFixtureSupport.writeTextFile(at: "secret.md", in: outside)
        try FileManager.default.createSymbolicLink(
            at: directories[1].appendingPathComponent("escape"), withDestinationURL: outside)

        let overlay = SkillOverlay(directories: Array(directories.prefix(2)))

        #expect(!overlay.confines(Self.escapingPath))
    }

    // MARK: - The execute bit of the winning copy

    @Test func isExecutableGivesTheModeOfTheCopyOfTheLowestDirectory() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }
        try LayerFixtureSupport.makeExecutable(
            directories[0].appendingPathComponent(Self.lowerOnlyPath))

        #expect(SkillOverlay(directories: directories).isExecutable(Self.lowerOnlyPath))
    }

    /// The copy of the highest directory wins, thus its mode is the answer and
    /// the mode of the lower copy is hidden, the same way its text is.
    @Test func isExecutableGivesTheModeOfTheHigherCopyForAPathThatTwoDirectoriesHold() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }
        try LayerFixtureSupport.makeExecutable(
            directories[0].appendingPathComponent(Self.sharedPath))

        #expect(!SkillOverlay(directories: directories).isExecutable(Self.sharedPath))
    }

    // MARK: - The relative path of a path that the model gives

    /// The directory under which the `/tmp` test makes its layer directory.
    /// On macOS, `/tmp` is a symbolic link to `/private/tmp`.
    private static let shortTemporaryParent = URL(fileURLWithPath: "/tmp", isDirectory: true)

    /// The prefix that macOS puts before `/tmp` when it resolves the link.
    private static let privatePrefix = "/private"

    @Test func aRelativePathComesBackWithNoChange() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        #expect(SkillOverlay(directories: directories).relativePath(for: Self.higherOnlyPath) == Self.higherOnlyPath)
    }

    /// The text check of a relative path stays with the caller, thus a
    /// relative path that walks up also comes back with no change.
    @Test func aRelativePathThatWalksUpComesBackWithNoChange() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        #expect(SkillOverlay(directories: directories).relativePath(for: "../outside.md") == "../outside.md")
    }

    @Test func anAbsolutePathInTheHighestDirectoryGivesItsRelativePath() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let absolutePath = directories[1].appendingPathComponent(Self.higherOnlyPath).path

        #expect(SkillOverlay(directories: directories).relativePath(for: absolutePath) == Self.higherOnlyPath)
    }

    @Test func anAbsolutePathInTheLowestDirectoryGivesItsRelativePath() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let absolutePath = directories[0].appendingPathComponent(Self.lowerOnlyPath).path

        #expect(SkillOverlay(directories: directories).relativePath(for: absolutePath) == Self.lowerOnlyPath)
    }

    /// An absolute path into the lowest directory gives the relative path, and
    /// that relative path resolves to the copy of the highest directory.
    @Test func anAbsolutePathIntoALowerCopyResolvesToTheHigherCopy() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let overlay = SkillOverlay(directories: directories)
        let absolutePath = directories[0].appendingPathComponent(Self.sharedPath).path

        let relativePath = try #require(overlay.relativePath(for: absolutePath))
        let winner = try #require(overlay.resolve(relativePath))

        #expect(relativePath == Self.sharedPath)
        #expect(winner.directoryIndex == 1)
    }

    /// The `/tmp` form and the `/private/tmp` form of one file give the same
    /// relative path, whichever form the directory of the overlay has.
    @Test(arguments: [false, true])
    func theTmpFormAndThePrivateTmpFormGiveTheSameRelativePath(directoryHasPrivatePrefix: Bool) throws {
        let tmpDirectory = Self.shortTemporaryParent
            .appendingPathComponent("SkillOverlayTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
        defer { LayerFixtureSupport.removeDirectories([tmpDirectory]) }
        try LayerFixtureSupport.writeTextFile(at: Self.higherOnlyPath, in: tmpDirectory)
        let tmpFormPath = tmpDirectory.appendingPathComponent(Self.higherOnlyPath).path
        let privateFormPath = Self.privatePrefix + tmpFormPath
        let directory =
            directoryHasPrivatePrefix ? URL(fileURLWithPath: Self.privatePrefix + tmpDirectory.path) : tmpDirectory
        let overlay = SkillOverlay(directories: [directory])

        #expect(overlay.relativePath(for: tmpFormPath) == Self.higherOnlyPath)
        #expect(overlay.relativePath(for: privateFormPath) == Self.higherOnlyPath)
    }

    @Test func aSystemFileGivesNothing() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        #expect(SkillOverlay(directories: directories).relativePath(for: ResourceTestSupport.systemFilePath) == nil)
    }

    /// The name of the skill directory of the sibling tests.
    private static let siblingTestSkillName = "release-notes"

    /// A file in a sibling directory of the skill, under the same layer root,
    /// is outside the skill: a file of a different skill, and a file of a
    /// directory whose name starts with the name of the skill directory.
    @Test(arguments: ["other-skill/SKILL.md", "release-notes-extra/x"])
    func aFileOfASiblingDirectoryGivesNothing(pathUnderRoot: String) throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { LayerFixtureSupport.removeDirectories([root]) }
        let skillDirectory = root.appendingPathComponent(Self.siblingTestSkillName, isDirectory: true)
        try LayerFixtureSupport.writeTextFile(at: Self.sharedPath, in: skillDirectory)
        let siblingFile = try LayerFixtureSupport.writeTextFile(at: pathUnderRoot, in: root)

        #expect(SkillOverlay(directories: [skillDirectory]).relativePath(for: siblingFile.path) == nil)
    }

    @Test func anAbsolutePathWhoseParentStepsLeaveTheSkillGivesNothing() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let escapingPath = directories[1].path + "/references/../../outside.md"

        #expect(SkillOverlay(directories: directories).relativePath(for: escapingPath) == nil)
    }

    /// A symbolic link in the skill that points at a directory outside it: the
    /// absolute path through the link leaves the skill.
    @Test func anAbsolutePathThroughASymbolicLinkThatLeavesTheSkillGivesNothing() throws {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 2)
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let (skillDirectory, outside) = (directories[0], directories[1])
        try LayerFixtureSupport.writeTextFile(at: "secret.md", in: outside)
        try FileManager.default.createSymbolicLink(
            at: skillDirectory.appendingPathComponent("escape"), withDestinationURL: outside)
        let linkedPath = skillDirectory.appendingPathComponent(Self.escapingPath).path

        #expect(SkillOverlay(directories: [skillDirectory]).relativePath(for: linkedPath) == nil)
    }

    // MARK: - Test helpers

    /// Makes the two-layer fixture each test of this suite reads: the lowest
    /// directory holds `SKILL.md`, one script and one file of bytes that are
    /// not UTF-8 text, and the highest directory holds its own `SKILL.md` and
    /// one reference file.
    ///
    /// - Returns: The two layer directories, lowest precedence first.
    /// - Throws: Whatever `LayerFixtureSupport` throws.
    private static func makeTwoLayerFixture() throws -> [URL] {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 2)
        try LayerFixtureSupport.writeTextFile(at: sharedPath, in: directories[0])
        try LayerFixtureSupport.writeTextFile(at: lowerOnlyPath, in: directories[0])
        try LayerFixtureSupport.writeBytesFile(at: bytesOnlyPath, in: directories[0])
        try LayerFixtureSupport.writeTextFile(at: sharedPath, in: directories[1])
        try LayerFixtureSupport.writeTextFile(at: higherOnlyPath, in: directories[1])
        return directories
    }
}
