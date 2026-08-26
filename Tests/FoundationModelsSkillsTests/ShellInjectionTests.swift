import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Tests for `ShellInjection`, pass 2 of the §5 render pipeline (plan.md §5, decision #25):
/// the recognition grammar (inline vs. fenced vs. mid-word rejection), real execution (merged
/// output, working directory, inherited environment), the `isShellExecutionDisabled` policy,
/// re-execution with no caching, and the single-shot no-re-scan invariant end to end through
/// the full pipeline.
struct ShellInjectionTests {
    private let pass = ShellInjection()

    /// Creates a fresh, empty temporary directory, resolved to its real (symlink-free) path so
    /// tests that shell out to `pwd` can compare against it directly.
    ///
    /// Each test gets its own directory rather than sharing one, so a side-effect probe (a
    /// touched or appended file) from one test can never be observed by another.
    ///
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    /// - Returns: The new directory's URL.
    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // `realpath(3)`, not `URL.resolvingSymlinksInPath()`: the latter leaves macOS's
        // `/var` -> `/private/var` symlink unresolved for a `FileManager.temporaryDirectory`
        // path, which would desync this URL from what a spawned child's own `pwd` reports for
        // the identical directory.
        return URL(fileURLWithPath: Self.canonicalPath(of: directory.path), isDirectory: true)
    }

    /// Resolves `path` to its canonical, symlink-free absolute form via `realpath(3)`.
    ///
    /// - Parameter path: The filesystem path to resolve; must already exist.
    /// - Returns: The canonical path, or `path` unchanged on the practically impossible case of
    ///   `realpath` failing for a path this test just created.
    private static func canonicalPath(of path: String) -> String {
        var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
        guard let resolved = realpath(path, &buffer) else { return path }
        return String(cString: resolved)
    }

    /// Builds a `RenderRequest` with sensible fixed defaults -- callers override only the fields
    /// the test cares about. Mirrors `RenderPipelineTests`'/`ArgumentSubstitutionTests`' own
    /// helper.
    private func request(
        text: String, workingDirectory: URL, policy: RenderPolicy = RenderPolicy()
    ) -> RenderRequest {
        RenderRequest(
            text: text,
            skillDirectory: workingDirectory,
            winningLayer: DotfolderStack.Layer(source: .project, root: workingDirectory),
            policy: policy)
    }

    /// Runs `pass.render` over `text`, wrapping/flattening `QuarantinedText` so every call site
    /// below can pass/receive plain `String`s.
    private func render(_ text: String, request: RenderRequest) throws -> String {
        try pass.render(QuarantinedText(original: text), request: request).flattened
    }

    // MARK: - Recognition grammar

    @Test(
        "recognition grammar: inline/fenced forms execute, a mid-word inline form does not",
        arguments: [
            (
                name: "inline at the very start of the text executes",
                body: "!`printf started`", expected: "started"
            ),
            (
                name: "inline after a space executes, preserving the space",
                body: "before !`printf after`", expected: "before after"
            ),
            (
                name: "inline after a newline executes, preserving the newline",
                body: "line one\n!`printf started`", expected: "line one\nstarted"
            ),
            (
                name: "inline after a tab executes, preserving the tab",
                body: "before\t!`printf tabbed`", expected: "before\ttabbed"
            ),
            (
                name: "a mid-word inline form does not execute and stays fully literal",
                body: "text!`printf nope`", expected: "text!`printf nope`"
            ),
            (
                name: "a fenced block executes, replacing the whole fenced region",
                body: "```!\nprintf fenced\n```", expected: "fenced"
            ),
        ])
    func recognitionGrammarMatchesExpectedForm(name: String, body: String, expected: String) throws {
        let workingDirectory = try makeTempDirectory()
        let result = try render(body, request: request(text: body, workingDirectory: workingDirectory))
        #expect(result == expected, "\(name)")
    }

    // MARK: - Span-boundary grammar: the flattened text decides, not the span (^q1mywft)

    /// A pipeline of the REAL passes 1 and 2 -- pass 1 splits the body into
    /// `.original`/`.quarantined` spans around every `$ARGUMENTS` splice, so
    /// pass 2 scans span edges that sit mid-word, after whitespace, or after
    /// a newline in the flattened text. Pass 3 stays identity: nothing below
    /// carries Stencil syntax, and the span matrix is this pass's own.
    private func passOneAndTwoPipeline() -> RenderPipeline {
        RenderPipeline(
            argumentSubstitution: ArgumentSubstitution(), shellInjection: ShellInjection(),
            stencil: IdentityRenderPass())
    }

    @Test(
        "span-boundary grammar: only a line start or whitespace in the FLATTENED text enables an injection",
        arguments: [
            (
                name: "mid-word after a splice does not execute",
                body: "abc$ARGUMENTS!`printf pwned`", argument: "X", expected: "abcX!`printf pwned`"
            ),
            (
                name: "directly after a splice at the body start does not execute",
                body: "$ARGUMENTS!`printf pwned`", argument: "X", expected: "X!`printf pwned`"
            ),
            (
                name: "after a space that follows a splice executes",
                body: "$ARGUMENTS !`printf ran`", argument: "X", expected: "X ran"
            ),
            (
                name: "after a newline that follows a splice executes",
                body: "$ARGUMENTS\n!`printf ran`", argument: "X", expected: "X\nran"
            ),
            (
                name: "whitespace carried in from the spliced value itself executes",
                body: "$ARGUMENTS!`printf ran`", argument: "X ", expected: "X ran"
            ),
            (
                name: "the very start of the body still executes ahead of a splice",
                body: "!`printf ran` $ARGUMENTS", argument: "X", expected: "ran X"
            ),
            (
                name: "a fenced block on the line after a splice executes",
                body: "$ARGUMENTS\n```!\nprintf fenced\n```", argument: "X", expected: "X\nfenced"
            ),
            (
                name: "a fenced opener directly after a splice is not at a line start and does not execute",
                body: "$ARGUMENTS```!\nprintf nope\n```", argument: "X", expected: "X```!\nprintf nope\n```"
            ),
        ])
    func spanBoundaryGrammarFollowsTheFlattenedText(name: String, body: String, argument: String, expected: String)
        throws
    {
        let workingDirectory = try makeTempDirectory()
        var renderRequest = request(text: body, workingDirectory: workingDirectory)
        renderRequest.arguments = [argument]

        let result = try passOneAndTwoPipeline().renderBody(renderRequest)

        #expect(result == expected, "\(name)")
    }

    @Test func midWordInjectionAfterAPositionalSpliceNeverSpawnsAProcess() throws {
        let workingDirectory = try makeTempDirectory()
        let probeFile = workingDirectory.appendingPathComponent("pwned.txt")
        let body = "abc$1!`touch pwned.txt`"
        var renderRequest = request(text: body, workingDirectory: workingDirectory)
        renderRequest.arguments = ["first", "second"]

        let result = try passOneAndTwoPipeline().renderBody(renderRequest)

        #expect(result == "abcsecond!`touch pwned.txt`\n\nARGUMENTS: first second")
        #expect(!FileManager.default.fileExists(atPath: probeFile.path))
    }

    // MARK: - Execution

    @Test func executesInlineCommandAndInlinesItsOutput() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try render(
            "!`printf hello`", request: request(text: "!`printf hello`", workingDirectory: workingDirectory))
        #expect(result == "hello")
    }

    @Test func mergesStdoutAndStderrIntoOneInlinedOutput() throws {
        let workingDirectory = try makeTempDirectory()
        let body = "!`echo out; echo err 1>&2`"
        let result = try render(body, request: request(text: body, workingDirectory: workingDirectory))
        #expect(result.contains("out"))
        #expect(result.contains("err"))
    }

    @Test func runsWithTheSkillDirectoryAsItsWorkingDirectory() throws {
        let workingDirectory = try makeTempDirectory()
        let body = "!`pwd`"
        let result = try render(body, request: request(text: body, workingDirectory: workingDirectory))
        #expect(result == workingDirectory.path)
    }

    @Test func inheritsTheHostProcessEnvironment() throws {
        setenv("SHELL_INJECTION_TESTS_ENV_VAR", "hello-env", 1)
        defer { unsetenv("SHELL_INJECTION_TESTS_ENV_VAR") }

        let workingDirectory = try makeTempDirectory()
        let body = "!`echo $SHELL_INJECTION_TESTS_ENV_VAR`"
        let result = try render(body, request: request(text: body, workingDirectory: workingDirectory))
        #expect(result == "hello-env")
    }

    // MARK: - isShellExecutionDisabled: inert marker, nothing runs

    @Test func disabledPolicyRendersTheInertMarkerAndRunsNothing() throws {
        let workingDirectory = try makeTempDirectory()
        let probeFile = workingDirectory.appendingPathComponent("sideeffect.txt")
        let body = "!`touch sideeffect.txt`"

        let result = try render(
            body,
            request: request(
                text: body, workingDirectory: workingDirectory,
                policy: RenderPolicy(isShellExecutionDisabled: true)))

        #expect(result == ShellInjection.disabledMarker)
        #expect(!FileManager.default.fileExists(atPath: probeFile.path))
    }

    // MARK: - Re-execution: no caching

    @Test func reRenderingTheSamePassReExecutesTheCommand() throws {
        let workingDirectory = try makeTempDirectory()
        let counterFile = workingDirectory.appendingPathComponent("counter.txt")
        let body = "!`echo tick >> counter.txt`"
        let renderRequest = request(text: body, workingDirectory: workingDirectory)

        _ = try render(body, request: renderRequest)
        _ = try render(body, request: renderRequest)

        let counterContents = try String(contentsOf: counterFile, encoding: .utf8)
        let tickCount = counterContents.split(separator: "\n").count
        #expect(tickCount == 2)
    }

    // MARK: - Body-only, proven end to end with a real instance

    @Test func metadataRenderNeverExecutesEvenValidInjectionSyntax() throws {
        let workingDirectory = try makeTempDirectory()
        let probeFile = workingDirectory.appendingPathComponent("metadata-sideeffect.txt")
        let text = "!`touch metadata-sideeffect.txt`"
        let pipeline = RenderPipeline(
            argumentSubstitution: ArgumentSubstitution(), shellInjection: ShellInjection(),
            stencil: IdentityRenderPass())

        let result = try pipeline.renderMetadata(request(text: text, workingDirectory: workingDirectory))

        #expect(result == text)
        #expect(!FileManager.default.fileExists(atPath: probeFile.path))
    }

    // MARK: - Single-shot: injected output is never re-scanned, end to end

    @Test func fullBodyRenderKeepsInjectedShellOutputLiteralThroughLaterPasses() throws {
        // The sentinel file's content is written directly to disk -- never through this pass's
        // own regex or through `ArgumentSubstitution` -- so it can carry `$0`, another
        // `` !`command` ``, and `{{ HOME }}` verbatim with no quoting gymnastics at all. If either
        // pass re-scanned pass 2's injected output, one of these three would be transformed;
        // none is. Wired with the REAL `StencilPass`, not `IdentityRenderPass` -- an identity
        // pass 3 can never disprove re-scanning, since it never interprets `{{ }}` either way.
        let workingDirectory = try makeTempDirectory()
        let sentinel = "$0 !`echo hi` {{ HOME }}"
        try sentinel.write(
            to: workingDirectory.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)

        let body = """
            Argument zero is: $0

            Shell says: !`cat sentinel.txt`
            """
        let pipeline = RenderPipeline(
            argumentSubstitution: ArgumentSubstitution(), shellInjection: ShellInjection(),
            stencil: StencilPass())
        var renderRequest = request(text: body, workingDirectory: workingDirectory)
        renderRequest.arguments = ["real-value"]

        let result = try pipeline.renderBody(renderRequest)

        // Pass 1 legitimately substituted the `$0` outside the injection...
        #expect(result.contains("Argument zero is: real-value"))
        // ...but the sentinel text pass 2 spliced in afterward stays byte-for-byte literal:
        // its own `$0` was never handed back to pass 1, its own `` !`echo hi` `` was never
        // handed back to this pass, and its own `{{ HOME }}` was never handed to the REAL pass
        // 3 -- if it had been, this would read the host's actual `$HOME` value instead.
        #expect(result.contains("Shell says: \(sentinel)"))
    }

    // MARK: - git-context fixture: preload: true + a deterministic injection

    @Test func gitContextFixturePreloadsAndRendersItsDeterministicInjection() throws {
        let url = FixtureLibrary.url(relativePath: "project/.skills/git-context/SKILL.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        guard case .decoded(let skill) = FrontmatterDecoder.decode(text: text) else {
            Issue.record("expected the git-context fixture to decode")
            return
        }

        #expect(skill.frontmatter.preload == true)

        let pipeline = RenderPipeline(
            argumentSubstitution: ArgumentSubstitution(), shellInjection: ShellInjection(),
            stencil: IdentityRenderPass())
        let result = try pipeline.renderBody(
            request(
                text: skill.body,
                workingDirectory: FixtureLibrary.url(relativePath: "project/.skills/git-context")))

        #expect(result.contains("on branch main, working tree clean"))
    }
}
