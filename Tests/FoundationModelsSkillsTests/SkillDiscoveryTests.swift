import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Tests for `SkillDiscovery`, Layer 3's directory-shaped discovery over the
/// combined view of the layers (plan.md §3, §4): the §11 fixture-root
/// snapshot, the contributing layer directories of one id, the
/// `user/_partials/` non-skill exclusion, a nonexistent root being skipped
/// silently, `.git`/`node_modules` exclusion, and the equivalence of the three
/// construction paths (layers, bare roots, and a `DotfolderStack`).
struct SkillDiscoveryTests {
    private static let defaultsRoot = FixtureLibrary.url(relativePath: "defaults")
    private static let userRoot = FixtureLibrary.url(relativePath: "user")
    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    /// The §11 fixture stack's three layer roots, lowest precedence first.
    private static let fixtureRoots = [defaultsRoot, userRoot, projectSkillsRoot]

    /// Every id the §11 fixture stack's three layers structurally carry a
    /// `SKILL.md` for, whichever layer gives the file.
    private static let expectedFixtureIDs: Set<String> = [
        "base-style", "commit", "deploy", "env-report", "git-context", "lint", "release-notes", "spec-clean",
    ]

    // MARK: - Fixture-root discovery snapshot

    @Test func discoveryOverFixtureRootsFindsEveryStructuralSkillDirectory() {
        let discovered = SkillDiscovery(roots: Self.fixtureRoots).discover()
        #expect(Set(discovered.map(\.id)) == Self.expectedFixtureIDs)
    }

    @Test func baseStyleTakesItsSkillFileFromTheUserRootAndKeepsTheDefaultsDirectory() throws {
        let discovered = SkillDiscovery(roots: Self.fixtureRoots).discover()
        let baseStyle = try #require(discovered.first { $0.id == "base-style" })

        #expect(baseStyle.rootIndex == 1)
        #expect(baseStyle.root.path == Self.userRoot.path)
        #expect(baseStyle.skillDirectory.path == Self.userRoot.appendingPathComponent("base-style").path)
        #expect(baseStyle.skillFileURL.path == baseStyle.skillDirectory.appendingPathComponent("SKILL.md").path)

        #expect(baseStyle.contributingDirectories.map(\.rootIndex) == [0, 1])
        #expect(
            baseStyle.contributingDirectories.map { $0.root.path } == [Self.defaultsRoot.path, Self.userRoot.path])
        #expect(
            baseStyle.contributingDirectories.map { $0.skillDirectory.path } == [
                Self.defaultsRoot.appendingPathComponent("base-style").path,
                Self.userRoot.appendingPathComponent("base-style").path,
            ])
    }

    @Test func aSkillThatOneLayerOnlyGivesHasOneContributingDirectory() throws {
        let discovered = SkillDiscovery(roots: Self.fixtureRoots).discover()
        let commit = try #require(discovered.first { $0.id == "commit" })

        #expect(commit.contributingDirectories.map(\.rootIndex) == [2])
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

    // MARK: - Depth bound: exactly one level below root, never the root itself

    /// A `SKILL.md` two levels below `root` (`root/a/b/SKILL.md`) is not
    /// discovered -- an id is a child directory of a layer root, and the
    /// `SKILL.md` of that child directory is the only one discovery reads.
    @Test func nestedTwoLevelsBelowRootIsNotDiscovered() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Self.writeSkillFile(in: root.appendingPathComponent("shallow-skill", isDirectory: true))
        try Self.writeSkillFile(
            in: root.appendingPathComponent("a", isDirectory: true).appendingPathComponent("b", isDirectory: true))

        let discovered = SkillDiscovery(roots: [root]).discover()
        #expect(discovered.map(\.id) == ["shallow-skill"])
    }

    /// A `SKILL.md` placed directly at `root` (`root/SKILL.md`, not inside
    /// any subdirectory) is not discovered -- an id is a child directory of a
    /// layer root, and `root` is never one of its own child directories.
    @Test func aSkillFileDirectlyAtTheRootItselfIsNotDiscovered() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Self.writeSkillFile(in: root.appendingPathComponent("shallow-skill", isDirectory: true))
        try "---\nname: root-level\ndescription: test fixture.\n---\nBody.\n"
            .write(to: root.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let discovered = SkillDiscovery(roots: [root]).discover()
        #expect(discovered.map(\.id) == ["shallow-skill"])
    }

    // MARK: - The contributing layer directories of one id

    /// The layer example of plan.md §3: `defaults` gives the whole skill,
    /// `user` gives its own `SKILL.md` and one script, and `project` gives one
    /// reference file only. The three layer directories all contribute, lowest
    /// precedence first.
    @Test func aSkillThatThreeLayersGiveHasThreeContributingDirectoriesLowestFirst() throws {
        let roots = try Self.makeTempDirectories(count: 3)
        defer { Self.removeDirectories(roots) }

        try Self.writeSkillFile(in: roots[0].appendingPathComponent("review", isDirectory: true))
        try Self.writeTextFile(at: roots[0].appendingPathComponent("review/references/rules.md"))
        try Self.writeTextFile(at: roots[0].appendingPathComponent("review/scripts/lint.sh"))
        try Self.writeTextFile(at: roots[0].appendingPathComponent("review/scripts/report.sh"))
        try Self.writeSkillFile(in: roots[1].appendingPathComponent("review", isDirectory: true))
        try Self.writeTextFile(at: roots[1].appendingPathComponent("review/scripts/lint.sh"))
        try Self.writeTextFile(at: roots[2].appendingPathComponent("review/references/house-style.md"))

        let discovered = SkillDiscovery(roots: roots).discover()
        let review = try #require(discovered.first { $0.id == "review" })

        #expect(discovered.map(\.id) == ["review"])
        #expect(review.rootIndex == 1)
        #expect(review.skillDirectory.path == roots[1].appendingPathComponent("review").path)
        #expect(review.contributingDirectories.map(\.rootIndex) == [0, 1, 2])
        #expect(review.contributingDirectories.map { $0.root.path } == roots.map(\.path))
        #expect(
            review.contributingDirectories.map { $0.skillDirectory.path }
                == roots.map { $0.appendingPathComponent("review").path })
    }

    /// A higher layer that holds `<id>/` with no `SKILL.md` contributes its
    /// files, and the `SKILL.md` of the lower layer still wins.
    @Test func aLayerDirectoryWithNoSkillFileIsStillAContributingDirectory() throws {
        let roots = try Self.makeTempDirectories(count: 2)
        defer { Self.removeDirectories(roots) }

        try Self.writeSkillFile(in: roots[0].appendingPathComponent("review", isDirectory: true))
        try Self.writeTextFile(at: roots[1].appendingPathComponent("review/references/house-style.md"))

        let review = try #require(SkillDiscovery(roots: roots).discover().first { $0.id == "review" })

        #expect(review.rootIndex == 0)
        #expect(review.skillDirectory.path == roots[0].appendingPathComponent("review").path)
        #expect(review.contributingDirectories.map(\.rootIndex) == [0, 1])
    }

    /// An id that no layer gives a `SKILL.md` for is not a skill, however many
    /// layers hold a directory of that name.
    @Test func anIDThatNoLayerGivesASkillFileForIsNotDiscovered() throws {
        let roots = try Self.makeTempDirectories(count: 2)
        defer { Self.removeDirectories(roots) }

        try Self.writeTextFile(at: roots[0].appendingPathComponent("notes/references/rules.md"))
        try Self.writeTextFile(at: roots[1].appendingPathComponent("notes/scripts/lint.sh"))

        #expect(SkillDiscovery(roots: roots).discover().isEmpty)
    }

    // MARK: - Multi-layer chain

    @Test func threeLayersOfOneIDGiveThreeContributingDirectoriesAndTheHighestSkillFile() throws {
        let roots = try Self.makeTempDirectories(count: 3)
        defer { Self.removeDirectories(roots) }

        for root in roots {
            try Self.writeSkillFile(in: root.appendingPathComponent("shared-skill", isDirectory: true))
        }

        let discovered = SkillDiscovery(roots: roots).discover()
        let winner = try #require(discovered.first { $0.id == "shared-skill" })

        #expect(winner.rootIndex == 2)
        #expect(winner.root.path == roots[2].path)
        #expect(winner.contributingDirectories.map(\.rootIndex) == [0, 1, 2])
        #expect(winner.contributingDirectories.map { $0.root.path } == roots.map(\.path))
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

    // MARK: - The three construction paths agree

    @Test func theLayersInitDiscoversTheSameSkillsAsTheRootsInit() {
        let layers = Self.fixtureRoots.map { DotfolderStack.Layer(source: .project, root: $0) }

        let viaLayers = SkillDiscovery(layers: layers).discover()
        let viaRoots = SkillDiscovery(roots: Self.fixtureRoots).discover()

        #expect(Self.comparableProjection(viaLayers) == Self.comparableProjection(viaRoots))
    }

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

    /// Creates `count` fresh, empty temporary directories for a test that
    /// needs more than one layer root on real disk.
    ///
    /// - Parameter count: How many directories to create.
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    /// - Returns: The new directories, in the order they were created.
    private static func makeTempDirectories(count: Int) throws -> [URL] {
        try (0..<count).map { _ in try makeTempDirectory() }
    }

    /// Removes each directory of `directories`, for the cleanup of a test that
    /// made more than one of them.
    ///
    /// - Parameter directories: The directories to remove.
    private static func removeDirectories(_ directories: [URL]) {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Writes a small text file at `url`, creating the directories above it
    /// first -- a file of a skill that is not its `SKILL.md`.
    ///
    /// - Parameter url: The file to write.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    private static func writeTextFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Text of \(url.lastPathComponent).\n".write(to: url, atomically: true, encoding: .utf8)
    }
}
