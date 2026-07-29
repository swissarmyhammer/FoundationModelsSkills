import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Tests for `SkillsRegistry`'s `SlashCommandProviding` conformance
/// (plan.md §6, §7.1; decision #29): `commands(workingDirectory:)`'s
/// command snapshot over the §11 fixture stack, `argumentHint` assembly
/// from `commandListing()`'s parsed parameters, and `commandUpdates`'s
/// reload bridge.
struct SlashCommandProvidingTests {
    // MARK: - Fixture roots (mirrors SkillsRegistryTests)

    private static let defaultsRoot = FixtureLibrary.url(relativePath: "defaults")
    private static let userRoot = FixtureLibrary.url(relativePath: "user")
    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    /// The §11 fixture stack's three layer roots, lowest precedence first.
    private static let fixtureRoots = [defaultsRoot, userRoot, projectSkillsRoot]

    /// Every id the §11 fixture stack lists on the user `/` menu -- every
    /// structural skill except `lint` (`user-invocable: false`, plan.md
    /// §6).
    private static let expectedCommandIDs: Set<String> = [
        "base-style", "commit", "deploy", "env-report", "git-context", "release-notes", "spec-clean",
    ]

    // MARK: - commands(workingDirectory:) snapshot

    @Test func commandsOverTheFixtureStackListsExactlyTheUserInvocableSkills() async {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let commands = await registry.commands(workingDirectory: Self.fixtureRoots[0])
        #expect(Set(commands.map(\.name)) == Self.expectedCommandIDs)
    }

    @Test func commandsExcludeAModelVisibleButUserHiddenSkill() async {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let commands = await registry.commands(workingDirectory: Self.fixtureRoots[0])
        #expect(!commands.contains { $0.name == "lint" })
    }

    @Test func commandsCarryTheRenderedDescriptionFromCommandListing() async throws {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let commands = await registry.commands(workingDirectory: Self.fixtureRoots[0])
        let commit = try #require(commands.first { $0.name == "commit" })
        #expect(
            commit.description
                == "Create a git commit for the currently staged changes using the given message.")
    }

    @Test func commandsCarryARawUnrenderedPromptTemplateBody() async throws {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let commands = await registry.commands(workingDirectory: Self.fixtureRoots[0])
        let commit = try #require(commands.first { $0.name == "commit" })
        guard case .prompt(let template) = commit.body else {
            Issue.record("expected commit's body to be .prompt, got \(commit.body)")
            return
        }
        // §5 pass 1 ($-argument substitution) has not run: the raw
        // `$0`/`$ARGUMENTS` tokens are still present, unsubstituted
        // (plan.md §7.1's caveat).
        #expect(template.contains("$0"))
        #expect(template.contains("$ARGUMENTS"))
    }

    @Test func commandsPreserveRawShellInjectionSyntaxUninterpretedInThePromptTemplate() async throws {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let commands = await registry.commands(workingDirectory: Self.fixtureRoots[0])
        let gitContext = try #require(commands.first { $0.name == "git-context" })
        guard case .prompt(let template) = gitContext.body else {
            Issue.record("expected git-context's body to be .prompt, got \(gitContext.body)")
            return
        }
        // §5 pass 2 (shell injection) has not run: the raw `` !`command` ``
        // token is still present verbatim, not replaced by the command's
        // executed output (plan.md §7.1's caveat).
        #expect(template.contains(#"!`echo "on branch main, working tree clean"`"#))
    }

    @Test func commandsPreserveRawStencilSyntaxUnrenderedInThePromptTemplate() async throws {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let commands = await registry.commands(workingDirectory: Self.fixtureRoots[0])
        let envReport = try #require(commands.first { $0.name == "env-report" })
        guard case .prompt(let template) = envReport.body else {
            Issue.record("expected env-report's body to be .prompt, got \(envReport.body)")
            return
        }
        // §5 pass 3 (Stencil) has not run either: the raw `{% include %}`/
        // `{{ }}` tags are still present verbatim, not substituted (plan.md
        // §7.1's caveat).
        #expect(template.contains(#"{% include "header" %}"#))
        #expect(template.contains("{{ HOME }}"))
        #expect(template.contains("{{ working_directory }}"))
    }

    // MARK: - argumentHint assembly

    @Test func commandWithASingleRequiredHintedParameterGetsThatPlaceholderAsItsHint() async throws {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let commands = await registry.commands(workingDirectory: Self.fixtureRoots[0])
        let commit = try #require(commands.first { $0.name == "commit" })
        #expect(commit.argumentHint == "<message>")
    }

    @Test func commandWithNoParametersGetsANilArgumentHint() async throws {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let commands = await registry.commands(workingDirectory: Self.fixtureRoots[0])
        let baseStyle = try #require(commands.first { $0.name == "base-style" })
        #expect(baseStyle.argumentHint == nil)
    }

    @Test func commandWithMultipleHintedParametersJoinsThemInPositionOrderWithTheVariadicTailRenderedAsEllipsis()
        async throws
    {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFixture(
            id: "multi-arg",
            skillMarkdown: """
                ---
                name: multi-arg
                description: Multi-argument fixture for argumentHint assembly.
                arguments:
                  - target
                  - mode
                  - files
                argument-hint: "<target> [mode] files..."
                ---
                Deploys $0 in $1 mode to $2.
                """,
            in: root)

        let registry = SkillsRegistry(roots: [root])
        let commands = await registry.commands(workingDirectory: root)
        let command = try #require(commands.first { $0.name == "multi-arg" })
        #expect(command.argumentHint == "<target> [mode] files...")
    }

    @Test func commandWithUnhintedArgumentsSynthesizesARequiredPlaceholder() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFixture(
            id: "unhinted",
            skillMarkdown: """
                ---
                name: unhinted
                description: Fixture with arguments but no argument-hint.
                arguments:
                  - target
                ---
                Deploys $0.
                """,
            in: root)

        let registry = SkillsRegistry(roots: [root])
        let commands = await registry.commands(workingDirectory: root)
        let command = try #require(commands.first { $0.name == "unhinted" })
        #expect(command.argumentHint == "<target>")
    }

    // MARK: - commandUpdates reload tick

    @Test func editingASkillFileProducesACommandUpdatesTickWithTheChangedCommandSet() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFixture(
            id: "editable-command",
            skillMarkdown: """
                ---
                name: editable-command
                description: before edit
                ---
                Body text.
                """,
            in: root)

        let registry = SkillsRegistry(roots: [root], watch: true)
        let stream = try #require(registry.commandUpdates)
        let recorder = SlashCommandUpdateRecorder()
        let subscription = Task {
            for await commands in stream { await recorder.record(commands) }
        }
        defer { subscription.cancel() }

        try Self.writeSkillFixture(
            id: "editable-command",
            skillMarkdown: """
                ---
                name: editable-command
                description: after edit
                ---
                Body text.
                """,
            in: root)

        let count = await Self.waitForPublicationCount(recorder, atLeast: 1, timeout: .seconds(10))
        #expect(count == 1)

        let publications = await recorder.publications
        let updated = try #require(publications.first)
        let command = try #require(updated.first { $0.name == "editable-command" })
        #expect(command.description == "after edit")
    }

    @Test func watchFalseRegistryHasANilCommandUpdates() {
        let registry = SkillsRegistry(roots: Self.fixtureRoots, watch: false)
        #expect(registry.commandUpdates == nil)
    }

    // MARK: - Test helpers

    /// Tallies every `[SlashCommand]` list `SkillsRegistry.commandUpdates`
    /// publishes during a test.
    ///
    /// An actor rather than relying on the `AsyncStream` itself for
    /// assertions, mirroring `SkillsRegistryReloadTests.MetadataUpdateRecorder`.
    private actor SlashCommandUpdateRecorder {
        private(set) var publications: [[SlashCommand]] = []

        /// Appends `commands` as the next observed publication.
        ///
        /// - Parameter commands: The published command list to record.
        func record(_ commands: [SlashCommand]) {
            publications.append(commands)
        }
    }

    /// Polls `recorder`'s publication count until it reaches `target` or
    /// `timeout` elapses.
    ///
    /// - Parameters:
    ///   - recorder: The recorder to poll.
    ///   - target: The publication count to wait for.
    ///   - timeout: How long to keep polling before giving up.
    /// - Returns: The observed publication count at the moment polling
    ///   stopped, whether or not it reached `target`.
    private static func waitForPublicationCount(
        _ recorder: SlashCommandUpdateRecorder, atLeast target: Int, timeout: Duration
    ) async -> Int {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var current = await recorder.publications.count
        while current < target, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            current = await recorder.publications.count
        }
        return current
    }

    /// Creates a fresh, empty temporary directory for a test root, so one
    /// test's filesystem activity can never be observed by another.
    ///
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    /// - Returns: The new directory's URL.
    private static func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes `id/SKILL.md` directly under `root`, creating the skill's own
    /// subdirectory first.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and (by
    ///     convention, not enforced here) `skillMarkdown`'s own `name:`.
    ///   - skillMarkdown: The complete `SKILL.md` file contents, frontmatter
    ///     fence included.
    ///   - root: The directory to write the skill's own subdirectory under.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    private static func writeSkillFixture(id: String, skillMarkdown: String, in root: URL) throws {
        let skillDirectory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try skillMarkdown.write(
            to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
