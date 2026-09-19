import Foundation
import Testing

@testable import FoundationModelsSkills

/// Tests for `PathConfinement` over the contributing directories of one skill
/// (plan.md §7.3): a path that one lower directory only holds, a path that two
/// directories hold, a path that leaves each directory, the path that no
/// directory holds, and the agreement of the one-directory form with a list of
/// one directory.
struct PathConfinementTests {
    /// The path of a resource file that the tests write.
    private static let resourcePath = "references/rules.md"

    /// The path of a resource file that no directory of the tests holds.
    private static let missingPath = "references/missing.md"

    // MARK: - The contributing directories

    @Test func aPathThatTheLowerDirectoryOnlyHoldsResolvesInThatDirectory() throws {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 2)
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let written = try LayerFixtureSupport.writeTextFile(at: Self.resourcePath, in: directories[1])

        let resolved = PathConfinement.resolvedURL(relativePath: Self.resourcePath, in: directories)

        #expect(resolved?.path == LayerFixtureSupport.resolvedPath(of: written))
    }

    @Test func aPathThatTwoDirectoriesHoldResolvesToTheCopyOfTheHigherDirectory() throws {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 2)
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let higherCopy = try LayerFixtureSupport.writeTextFile(at: Self.resourcePath, in: directories[0])
        try LayerFixtureSupport.writeTextFile(at: Self.resourcePath, in: directories[1])

        let resolved = PathConfinement.resolvedURL(relativePath: Self.resourcePath, in: directories)

        #expect(resolved?.path == LayerFixtureSupport.resolvedPath(of: higherCopy))
    }

    /// A path that no directory holds still resolves, in the highest
    /// directory that confines it. `ReadResource` then reports that the file
    /// could not be read, and not that the path is denied.
    @Test func aPathThatNoDirectoryHoldsResolvesInTheHighestDirectory() throws {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 2)
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let resolved = PathConfinement.resolvedURL(relativePath: Self.missingPath, in: directories)

        #expect(resolved?.path == "\(LayerFixtureSupport.resolvedPath(of: directories[0]))/\(Self.missingPath)")
    }

    @Test func anEmptyDirectoryListDeniesEveryPath() {
        #expect(PathConfinement.resolvedURL(relativePath: Self.resourcePath, in: []) == nil)
    }

    // MARK: - A path that leaves each of the directories

    @Test(arguments: ["../outside.md", "/etc/passwd", "~/secrets.md", ""])
    func aPathThatNoDirectoryCanConfineIsDenied(path: String) throws {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 2)
        defer { LayerFixtureSupport.removeDirectories(directories) }

        #expect(PathConfinement.resolvedURL(relativePath: path, in: directories) == nil)
    }

    /// A symbolic link in each directory that points at one directory outside
    /// each of them. The file exists through both links, and both copies
    /// leave their own directory, thus the path is denied.
    @Test func aSymbolicLinkThatPointsOutOfEachDirectoryIsDenied() throws {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 3)
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let outside = directories[2]
        try LayerFixtureSupport.writeTextFile(at: "secret.md", in: outside)
        for directory in directories.prefix(2) {
            try FileManager.default.createSymbolicLink(
                at: directory.appendingPathComponent("escape"), withDestinationURL: outside)
        }

        let resolved = PathConfinement.resolvedURL(
            relativePath: "escape/secret.md", in: Array(directories.prefix(2)))

        #expect(resolved == nil)
    }

    /// A symbolic link in the higher directory that leaves it, beside a real
    /// copy in the lower directory: the higher copy is denied, and the lower
    /// copy wins.
    @Test func aCopyThatLeavesItsOwnDirectoryGivesWayToTheCopyOfALowerDirectory() throws {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 3)
        defer { LayerFixtureSupport.removeDirectories(directories) }
        let outside = directories[2]
        try LayerFixtureSupport.writeTextFile(at: "rules.md", in: outside)
        try FileManager.default.createSymbolicLink(
            at: directories[0].appendingPathComponent("references"), withDestinationURL: outside)
        let lowerCopy = try LayerFixtureSupport.writeTextFile(at: "references/rules.md", in: directories[1])

        let resolved = PathConfinement.resolvedURL(
            relativePath: "references/rules.md", in: Array(directories.prefix(2)))

        #expect(resolved?.path == LayerFixtureSupport.resolvedPath(of: lowerCopy))
    }

    // MARK: - The one-directory form is the list form

    /// Each path shape the one-directory form answers: a file it holds, a
    /// file it does not hold, and a path that leaves it.
    @Test(arguments: ["references/rules.md", "references/missing.md", "../outside.md"])
    func theOneDirectoryFormGivesTheSameAnswerAsAListOfOneDirectory(path: String) throws {
        let directory = try WatcherTestSupport.makeTempDirectory()
        defer { LayerFixtureSupport.removeDirectories([directory]) }
        try LayerFixtureSupport.writeTextFile(at: Self.resourcePath, in: directory)

        let single = PathConfinement.resolvedURL(relativePath: path, in: directory)
        let list = PathConfinement.resolvedURL(relativePath: path, in: [directory])

        #expect(single?.path == list?.path)
    }
}
