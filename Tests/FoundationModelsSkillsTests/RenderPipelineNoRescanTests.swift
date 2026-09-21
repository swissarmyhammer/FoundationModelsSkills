import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// The full-real-pipeline composition matrix for plan.md §5's no-re-scan
/// contract (`^r3bhwdp`): passes 1-3 wired to their REAL implementations,
/// never `IdentityRenderPass` mocks, over both a model-supplied argument
/// value and a shell command's own output.
///
/// Before this task, `RenderPipeline.run` threaded a plain `String` between
/// passes, so pass N+1 re-scanned pass N's *entire* output -- including
/// whatever it had just spliced in. A `use skill` argument (model-supplied)
/// containing `` !`cmd` `` at line start was executed by pass 2; a shell
/// command's own stdout containing `{{ HOME }}`/`{% include %}` was expanded
/// by pass 3. `QuarantinedText` closes both holes structurally: a pass only
/// ever scans `.original` spans, never a `.quarantined` one an earlier pass
/// produced.
struct RenderPipelineNoRescanTests {
    /// A fresh, empty temporary directory to use as the skill directory --
    /// shell commands run with this as their working directory, and
    /// `!`touch sideeffect.txt`` writes here.
    ///
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    /// - Returns: The new directory's URL.
    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RenderPipelineNoRescanTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Builds a `RenderRequest` with sensible fixed defaults.
    private func request(
        text: String, arguments: [String] = [], skillDirectory: URL
    ) -> RenderRequest {
        RenderRequest(
            text: text,
            arguments: arguments,
            skillDirectory: skillDirectory,
            winningLayer: DotfolderStack.Layer(source: .project, root: skillDirectory),
            policy: RenderPolicy())
    }

    /// The real, fully-wired pipeline every test in this file drives --
    /// never `IdentityRenderPass` for any of the three slots.
    ///
    /// Pass 3 gets the real process environment, the same as the registry
    /// gives it, thus a `{{ VAR }}` of a spliced value names a variable that
    /// the template of the same render could resolve. Each assertion below
    /// then proves the quarantine, and not an empty ladder.
    private func realPipeline() -> RenderPipeline {
        RenderPipeline(
            argumentSubstitution: ArgumentSubstitution(), shellInjection: ShellInjection(),
            stencil: StencilPass(environment: ProcessInfo.processInfo.environment))
    }

    // MARK: - An argument value containing `` !`echo pwned` `` renders literal; no process spawns

    @Test func argumentValueContainingShellInjectionRendersLiteralAndSpawnsNoProcess() async throws {
        let skillDirectory = try makeTempDirectory()
        let probeFile = skillDirectory.appendingPathComponent("pwned.txt")
        let maliciousArgument = "!`touch pwned.txt`"

        let result = try await realPipeline().renderBody(
            request(text: "Argument: $ARGUMENTS", arguments: [maliciousArgument], skillDirectory: skillDirectory))

        #expect(result == "Argument: \(maliciousArgument)")
        #expect(!FileManager.default.fileExists(atPath: probeFile.path))
    }

    // MARK: - An argument value containing `{{ HOME }}`/`{% include %}` stays literal after a full body render

    @Test func argumentValueContainingStencilSyntaxStaysLiteralAfterFullBodyRender() async throws {
        let skillDirectory = try makeTempDirectory()
        setenv("RENDER_PIPELINE_NO_RESCAN_TESTS_HOME", "/should-never-appear", 1)
        defer { unsetenv("RENDER_PIPELINE_NO_RESCAN_TESTS_HOME") }
        let maliciousArgument = "{{ RENDER_PIPELINE_NO_RESCAN_TESTS_HOME }} {% include \"header\" %}"

        let result = try await realPipeline().renderBody(
            request(text: "Argument: $ARGUMENTS", arguments: [maliciousArgument], skillDirectory: skillDirectory))

        #expect(result == "Argument: \(maliciousArgument)")
        #expect(!result.contains("/should-never-appear"))
    }

    // MARK: - Shell output containing `{{ HOME }}`, `$0`, and `` !`cmd` `` stays literal end-to-end

    @Test func shellCommandOutputContainingDollarStencilAndInjectionSyntaxStaysLiteralEndToEnd() async throws {
        let skillDirectory = try makeTempDirectory()
        setenv("RENDER_PIPELINE_NO_RESCAN_TESTS_HOME", "/should-never-appear", 1)
        defer { unsetenv("RENDER_PIPELINE_NO_RESCAN_TESTS_HOME") }
        let sentinelProbe = skillDirectory.appendingPathComponent("second-order-pwned.txt")
        // The `{% include %}` names a partial that no layer of this render
        // holds, and this pipeline gives pass 3 no layer at all. Thus a pass 3
        // that scanned the output of pass 2 would raise a render error here,
        // and the render below would throw instead of giving the text back.
        let sentinel = """
            $0 !`touch second-order-pwned.txt` {{ RENDER_PIPELINE_NO_RESCAN_TESTS_HOME }} \
            {% include "no-such-partial" %}
            """
        try sentinel.write(
            to: skillDirectory.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)

        let result = try await realPipeline().renderBody(
            request(text: "Shell says: !`cat sentinel.txt`", skillDirectory: skillDirectory))

        #expect(result == "Shell says: \(sentinel)")
        #expect(!FileManager.default.fileExists(atPath: sentinelProbe.path))
        #expect(!result.contains("/should-never-appear"))
    }

    // MARK: - Composition: all three assertions together, over one render

    @Test func realPassOneTwoThreeTogetherSatisfyAllThreeNoRescanAssertions() async throws {
        let skillDirectory = try makeTempDirectory()
        let argumentProbe = skillDirectory.appendingPathComponent("argument-pwned.txt")
        let shellProbe = skillDirectory.appendingPathComponent("shell-pwned.txt")
        setenv("RENDER_PIPELINE_NO_RESCAN_TESTS_HOME", "/should-never-appear", 1)
        defer { unsetenv("RENDER_PIPELINE_NO_RESCAN_TESTS_HOME") }

        let maliciousArgument = "!`touch argument-pwned.txt` {{ RENDER_PIPELINE_NO_RESCAN_TESTS_HOME }}"
        let sentinel = "$0 !`touch shell-pwned.txt` {{ RENDER_PIPELINE_NO_RESCAN_TESTS_HOME }}"
        try sentinel.write(
            to: skillDirectory.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)
        let body = """
            Argument: $ARGUMENTS

            Shell says: !`cat sentinel.txt`
            """

        let result = try await realPipeline().renderBody(
            request(text: body, arguments: [maliciousArgument], skillDirectory: skillDirectory))

        #expect(result.contains("Argument: \(maliciousArgument)"))
        #expect(result.contains("Shell says: \(sentinel)"))
        #expect(!FileManager.default.fileExists(atPath: argumentProbe.path))
        #expect(!FileManager.default.fileExists(atPath: shellProbe.path))
        #expect(!result.contains("/should-never-appear"))
    }

    // MARK: - Empty quarantined spans never split an original span

    @Test func emptyArgumentSubstitutionNoLongerSplitsTheOriginalSpanAroundIt() throws {
        let skillDirectory = try makeTempDirectory()
        let body = "{% if flag %}$1{% endif %}"

        let substituted = try ArgumentSubstitution().render(
            QuarantinedText(original: body), request: request(text: body, skillDirectory: skillDirectory))

        #expect(substituted.spans == [.original("{% if flag %}{% endif %}")])
    }

    @Test func emptyShellOutputNoLongerSplitsTheOriginalSpanAroundIt() async throws {
        let skillDirectory = try makeTempDirectory()
        let body = "before !`true`after"

        let injected = try await ShellInjection().render(
            QuarantinedText(original: body), request: request(text: body, skillDirectory: skillDirectory))

        #expect(injected.spans == [.original("before after")])
    }
}
