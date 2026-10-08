import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Tests for `SkillsRegistry`'s `SlashCommandProviding` conformance
/// `commands(workingDirectory:)`'s
/// command snapshot over the fixture stack, `argumentHint` assembly
/// from `commandListing()`'s parsed parameters, and `commandUpdates`'s
/// reload bridge.
struct SlashCommandProvidingTests {
    // MARK: - Fixture roots (mirrors SkillsRegistryTests)

    private static let defaultsRoot = FixtureLibrary.url(relativePath: "defaults")
    private static let userRoot = FixtureLibrary.url(relativePath: "user")
    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    /// The fixture stack's three layer roots, lowest precedence first.
    private static let fixtureRoots = [defaultsRoot, userRoot, projectSkillsRoot]

    /// Every id the fixture stack lists on the user `/` menu -- every
    /// structural skill except `lint` (`user-invocable: false`).
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

    // MARK: - The body renders through the render pipeline

    @Test func commandBodyRendersTheTypedTextAsTheOneArgumentOfCall() async throws {
        // The text after `/commit ` goes into the pipeline as one argument,
        // thus `$ARGUMENTS` gets it as typed and `$0` gets its first
        // shell-style token. The result is what `call(id:arguments:)` gives
        // for the same text.
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let commit = try await Self.command(named: "commit", in: registry)
        let typed = "\"fix the off-by-one bug\""

        let rendered = try await Self.render(commit, typed: typed)

        #expect(rendered == (try await registry.call(id: "commit", arguments: [typed])))
        #expect(rendered.contains("using the message: fix the off-by-one bug"))
        #expect(rendered.contains(typed))
        #expect(!rendered.contains("$0"))
        #expect(!rendered.contains("$ARGUMENTS"))
    }

    @Test func commandBodyWithUnquotedTextGivesTheFirstWordToDollarZero() async throws {
        // Text with no quotation marks splits with shell-style quoting: `$0`
        // gets the first word only, and `$ARGUMENTS` gets the text as typed.
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let commit = try await Self.command(named: "commit", in: registry)
        let typed = "fix the bug"

        let rendered = try await Self.render(commit, typed: typed)

        #expect(rendered == (try await registry.call(id: "commit", arguments: [typed])))
        #expect(rendered.contains("using the message: fix\n"))
        #expect(rendered.split(separator: "\n").contains("fix the bug"))
    }

    @Test func commandBodyWithNoTypedTextRendersWithNoArgumentsAppend() async throws {
        // `/commit` with nothing after it is a call with no arguments, not a
        // call with one empty argument: the `ARGUMENTS:` fallback stays out.
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let commit = try await Self.command(named: "commit", in: registry)

        let rendered = try await Self.render(commit, typed: "")

        #expect(rendered == (try await registry.call(id: "commit", arguments: [])))
        #expect(!rendered.contains("ARGUMENTS:"))
    }

    @Test func commandBodyRunsShellInjection() async throws {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let gitContext = try await Self.command(named: "git-context", in: registry)

        let rendered = try await Self.render(gitContext, typed: "")

        #expect(rendered.contains("on branch main, working tree clean"))
        #expect(!rendered.contains("!`"))
    }

    @Test func commandBodyRunsStencil() async throws {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let envReport = try await Self.command(named: "env-report", in: registry)

        let rendered = try await Self.render(envReport, typed: "")

        #expect(rendered.contains("Shared Header"))
        #expect(!rendered.contains("{% include"))
        #expect(!rendered.contains("{{ HOME }}"))
    }

    // MARK: - argumentHint assembly

    @Test func commandWithASingleHintedParameterGetsThatPlaceholderAsItsHint() async throws {
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

    @Test func commandWithUnhintedArgumentsSynthesizesABracketedPlaceholder() async throws {
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
        #expect(command.argumentHint == "[target]")
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

    /// The error a test throws when a command carries a body of a kind other
    /// than `.rendered`.
    private struct UnexpectedBodyKind: Error, CustomStringConvertible {
        let body: SlashCommand.Body
        var description: String { "expected a .rendered body, got \(body)" }
    }

    /// The command of `registry` that `commands(workingDirectory:)` lists
    /// under `name`.
    ///
    /// - Parameters:
    ///   - name: The command name, which is the skill id.
    ///   - registry: The registry over the fixture stack to read.
    /// - Returns: The one `SlashCommand` named `name`.
    /// - Throws: The `#require` failure when no command holds `name`.
    private static func command(named name: String, in registry: SkillsRegistry) async throws
        -> SlashCommand
    {
        let commands = await registry.commands(workingDirectory: Self.fixtureRoots[0])
        return try #require(commands.first { $0.name == name })
    }

    /// Renders `command` with `typed` as the text after `/name `.
    ///
    /// - Parameters:
    ///   - command: The command to render.
    ///   - typed: The raw text the user typed after the command name.
    /// - Returns: The rendered prompt text.
    /// - Throws: `UnexpectedBodyKind` when the body is not `.rendered`, or
    ///   whatever the render itself throws.
    private static func render(_ command: SlashCommand, typed: String) async throws -> String {
        guard case .rendered(let render) = command.body else {
            throw UnexpectedBodyKind(body: command.body)
        }
        return try await render(
            SlashCommand.Invocation(arguments: typed, workingDirectory: Self.fixtureRoots[0]))
    }

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
