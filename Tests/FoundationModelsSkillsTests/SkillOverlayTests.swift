import Foundation
import Testing

@testable import FoundationModelsSkills

/// Tests for `SkillOverlay`, the combined view of one skill over the layer
/// directories that contribute to it (plan.md §3, §7.3): the union of the
/// paths, the copy of the highest directory, and which directory gave the
/// winning copy.
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

    // MARK: - The union of the paths

    @Test func entriesGiveTheUnionOfThePathsOfEveryDirectory() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let entries = SkillOverlay(directories: directories).entries()

        #expect(Set(entries.keys) == [Self.sharedPath, Self.lowerOnlyPath, Self.higherOnlyPath])
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
        #expect(
            winner.url.path
                == LayerFixtureSupport.resolvedPath(of: directories[0].appendingPathComponent(Self.lowerOnlyPath)))
    }

    @Test func resolveNamesTheHighestDirectoryForAPathThatTwoDirectoriesHold() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        let winner = try #require(SkillOverlay(directories: directories).resolve(Self.sharedPath))

        #expect(winner.directoryIndex == 1)
        #expect(
            winner.url.path
                == LayerFixtureSupport.resolvedPath(of: directories[1].appendingPathComponent(Self.sharedPath)))
    }

    @Test func resolveDeniesAPathThatLeavesEachDirectory() throws {
        let directories = try Self.makeTwoLayerFixture()
        defer { LayerFixtureSupport.removeDirectories(directories) }

        #expect(SkillOverlay(directories: directories).resolve("../outside.md") == nil)
    }

    // MARK: - Test helpers

    /// Makes the two-layer fixture each test of this suite reads: the lowest
    /// directory holds `SKILL.md` and one script, and the highest directory
    /// holds its own `SKILL.md` and one reference file.
    ///
    /// - Returns: The two layer directories, lowest precedence first.
    /// - Throws: Whatever `LayerFixtureSupport` throws.
    private static func makeTwoLayerFixture() throws -> [URL] {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 2)
        try LayerFixtureSupport.writeTextFile(at: sharedPath, in: directories[0])
        try LayerFixtureSupport.writeTextFile(at: lowerOnlyPath, in: directories[0])
        try LayerFixtureSupport.writeTextFile(at: sharedPath, in: directories[1])
        try LayerFixtureSupport.writeTextFile(at: higherOnlyPath, in: directories[1])
        return directories
    }
}
