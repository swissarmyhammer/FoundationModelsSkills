import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Tests for `SkillDiscovery`, Layer 3's directory-shaped discovery over
/// host-supplied layer roots (plan.md §3, §4; decisions #3/#19/#29): the §11
/// fixture-root snapshot (including last-root-wins shadowing), the
/// `user/_partials/` non-skill exclusion, a nonexistent root being skipped
/// silently, `.git`/`node_modules` exclusion, and the `DotfolderStack`
/// convenience helper's equivalence to passing roots directly.
struct SkillDiscoveryTests {
    private static let defaultsRoot = FixtureLibrary.url(relativePath: "defaults")
    private static let userRoot = FixtureLibrary.url(relativePath: "user")
    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    /// The §11 fixture stack's three layer roots, lowest precedence first.
    private static let fixtureRoots = [defaultsRoot, userRoot, projectSkillsRoot]

    /// Every id the §11 fixture stack's three layers structurally carry a
    /// `SKILL.md` for, regardless of shadowing.
    private static let expectedFixtureIDs: Set<String> = [
        "base-style", "commit", "deploy", "env-report", "git-context", "lint", "release-notes", "spec-clean",
    ]

    // MARK: - Fixture-root discovery snapshot

    @Test func discoveryOverFixtureRootsFindsEveryStructuralSkillDirectory() {
        let discovered = SkillDiscovery(roots: Self.fixtureRoots).discover()
        #expect(Set(discovered.map(\.id)) == Self.expectedFixtureIDs)
    }

    @Test func baseStyleWinsFromTheUserRootWithTheDefaultsCopyRecordedAsShadowed() throws {
        let discovered = SkillDiscovery(roots: Self.fixtureRoots).discover()
        let baseStyle = try #require(discovered.first { $0.id == "base-style" })

        #expect(baseStyle.rootIndex == 1)
        #expect(baseStyle.root.path == Self.userRoot.path)
        #expect(baseStyle.skillDirectory.path == Self.userRoot.appendingPathComponent("base-style").path)
        #expect(baseStyle.skillFileURL.path == baseStyle.skillDirectory.appendingPathComponent("SKILL.md").path)

        let shadowed = try #require(baseStyle.shadowedCandidates.first)
        #expect(baseStyle.shadowedCandidates.count == 1)
        #expect(shadowed.rootIndex == 0)
        #expect(shadowed.root.path == Self.defaultsRoot.path)
        #expect(shadowed.skillDirectory.path == Self.defaultsRoot.appendingPathComponent("base-style").path)
    }

    @Test func nonShadowedSkillsCarryNoShadowedCandidates() throws {
        let discovered = SkillDiscovery(roots: Self.fixtureRoots).discover()
        let commit = try #require(discovered.first { $0.id == "commit" })

        #expect(commit.shadowedCandidates.isEmpty)
        #expect(commit.rootIndex == 2)
        #expect(commit.root.path == Self.projectSkillsRoot.path)
    }

    // MARK: - user/_partials/ is not a skill

    @Test func userPartialsDirectoryIsNotDiscoveredAsASkill() {
        let discovered = SkillDiscovery(roots: Self.fixtureRoots).discover()
        #expect(!discovered.contains { $0.id == "_partials" })
    }

    // MARK: - Nonexistent root

    @Test func nonexistentRootInTheListIsSkippedWithoutError() {
        let bogusRoot = FixtureLibrary.url(relativePath: "does-not-exist-\(UUID().uuidString)")
        let discovered = SkillDiscovery(roots: [bogusRoot] + Self.fixtureRoots).discover()
        #expect(Set(discovered.map(\.id)) == Self.expectedFixtureIDs)
    }

    // MARK: - .git / node_modules exclusion

    @Test func gitAndNodeModulesDirectoriesAreSkippedOverATempDirectory() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Self.writeSkillFile(in: root.appendingPathComponent("real-skill", isDirectory: true))
        try Self.writeSkillFile(in: root.appendingPathComponent(".git", isDirectory: true))
        try Self.writeSkillFile(in: root.appendingPathComponent("node_modules", isDirectory: true))

        let discovered = SkillDiscovery(roots: [root]).discover()
        #expect(discovered.map(\.id) == ["real-skill"])
    }

    // MARK: - Multi-level shadow chain

    @Test func threeRootShadowChainAccumulatesShadowedCandidatesInPrecedenceOrder() throws {
        let root0 = try Self.makeTempDirectory()
        let root1 = try Self.makeTempDirectory()
        let root2 = try Self.makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: root0)
            try? FileManager.default.removeItem(at: root1)
            try? FileManager.default.removeItem(at: root2)
        }

        try Self.writeSkillFile(in: root0.appendingPathComponent("shared-skill", isDirectory: true))
        try Self.writeSkillFile(in: root1.appendingPathComponent("shared-skill", isDirectory: true))
        try Self.writeSkillFile(in: root2.appendingPathComponent("shared-skill", isDirectory: true))

        let discovered = SkillDiscovery(roots: [root0, root1, root2]).discover()
        let winner = try #require(discovered.first { $0.id == "shared-skill" })

        #expect(winner.rootIndex == 2)
        #expect(winner.root.path == root2.path)
        #expect(winner.shadowedCandidates.map(\.rootIndex) == [0, 1])
        #expect(winner.shadowedCandidates.map { $0.root.path } == [root0.path, root1.path])
    }

    // MARK: - Root edge cases

    @Test func rootThatIsARegularFileIsSkippedWithoutThrowing() throws {
        let parent = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let fileRoot = parent.appendingPathComponent("not-a-directory")
        try "not a directory".write(to: fileRoot, atomically: true, encoding: .utf8)

        let discovered = SkillDiscovery(roots: [fileRoot]).discover()
        #expect(discovered.isEmpty)
    }

    @Test func emptyRootsListDiscoversNoSkills() {
        #expect(SkillDiscovery(roots: []).discover().isEmpty)
    }

    // MARK: - DotfolderStack -> roots helper equivalence

    @Test func stackHelperProducesTheSameDiscoveryResultAsPassingRootsDirectly() {
        let stack = DotfolderStack(
            name: "skills",
            workingDirectory: FixtureLibrary.url(relativePath: "project"),
            defaultsDirectory: Self.defaultsRoot,
            userDirectory: Self.userRoot)

        let viaStack = SkillDiscovery(stack: stack).discover()
        let viaRoots = SkillDiscovery(roots: Self.fixtureRoots).discover()

        #expect(Self.comparableProjection(viaStack) == Self.comparableProjection(viaRoots))
    }

    // MARK: - Test helpers

    /// Projects `discovered` to path-based strings, sorted by id, so two
    /// discovery runs can be compared for equivalence without depending on
    /// `URL`'s exact trailing-slash representation.
    ///
    /// - Parameter discovered: The discovery result to project.
    /// - Returns: One comparable string per discovered skill, sorted by id.
    private static func comparableProjection(_ discovered: [DiscoveredSkill]) -> [String] {
        discovered
            .sorted { $0.id < $1.id }
            .map { skill in
                "\(skill.id)|\(skill.rootIndex)|\(skill.root.path)|\(skill.skillDirectory.path)|"
                    + "\(skill.skillFileURL.path)"
            }
    }

    /// Creates a fresh, empty temporary directory for a test that needs real
    /// disk structure (`.git`/`node_modules` exclusion), so a side effect
    /// from one test can never be observed by another.
    ///
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    /// - Returns: The new directory's URL.
    private static func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes a minimal but structurally valid `SKILL.md` directly under
    /// `directory`, creating `directory` first if it does not already exist.
    ///
    /// - Parameter directory: The directory to create the `SKILL.md` file
    ///   under.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    private static func writeSkillFile(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = "---\nname: \(directory.lastPathComponent)\ndescription: test fixture.\n---\nBody.\n"
        try text.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
