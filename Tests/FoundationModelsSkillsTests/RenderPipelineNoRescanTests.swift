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
    private func realPipeline() -> RenderPipeline {
        RenderPipeline(
            argumentSubstitution: ArgumentSubstitution(), shellInjection: ShellInjection(), stencil: StencilPass())
    }

    // MARK: - An argument value containing `` !`echo pwned` `` renders literal; no process spawns

    @Test func argumentValueContainingShellInjectionRendersLiteralAndSpawnsNoProcess() throws {
        let skillDirectory = try makeTempDirectory()
        let probeFile = skillDirectory.appendingPathComponent("pwned.txt")
        let maliciousArgument = "!`touch pwned.txt`"

        let result = try realPipeline().renderBody(
            request(text: "Argument: $ARGUMENTS", arguments: [maliciousArgument], skillDirectory: skillDirectory))

        #expect(result == "Argument: \(maliciousArgument)")
        #expect(!FileManager.default.fileExists(atPath: probeFile.path))
    }

    // MARK: - An argument value containing `{{ HOME }}`/`{% include %}` stays literal after a full body render

    @Test func argumentValueContainingStencilSyntaxStaysLiteralAfterFullBodyRender() throws {
        let skillDirectory = try makeTempDirectory()
        setenv("RENDER_PIPELINE_NO_RESCAN_TESTS_HOME", "/should-never-appear", 1)
        defer { unsetenv("RENDER_PIPELINE_NO_RESCAN_TESTS_HOME") }
        let maliciousArgument = "{{ RENDER_PIPELINE_NO_RESCAN_TESTS_HOME }} {% include \"header\" %}"

        let result = try realPipeline().renderBody(
            request(text: "Argument: $ARGUMENTS", arguments: [maliciousArgument], skillDirectory: skillDirectory))

        #expect(result == "Argument: \(maliciousArgument)")
        #expect(!result.contains("/should-never-appear"))
    }

    // MARK: - Shell output containing `{{ HOME }}`, `$0`, and `` !`cmd` `` stays literal end-to-end

    @Test func shellCommandOutputContainingDollarStencilAndInjectionSyntaxStaysLiteralEndToEnd() throws {
        let skillDirectory = try makeTempDirectory()
        setenv("RENDER_PIPELINE_NO_RESCAN_TESTS_HOME", "/should-never-appear", 1)
        defer { unsetenv("RENDER_PIPELINE_NO_RESCAN_TESTS_HOME") }
        let sentinelProbe = skillDirectory.appendingPathComponent("second-order-pwned.txt")
        let sentinel = "$0 !`touch second-order-pwned.txt` {{ RENDER_PIPELINE_NO_RESCAN_TESTS_HOME }}"
        try sentinel.write(
            to: skillDirectory.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)

        let result = try realPipeline().renderBody(
            request(text: "Shell says: !`cat sentinel.txt`", skillDirectory: skillDirectory))

        #expect(result == "Shell says: \(sentinel)")
        #expect(!FileManager.default.fileExists(atPath: sentinelProbe.path))
        #expect(!result.contains("/should-never-appear"))
    }

    // MARK: - Composition: all three assertions together, over one render

    @Test func realPassOneTwoThreeTogetherSatisfyAllThreeNoRescanAssertions() throws {
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

        let result = try realPipeline().renderBody(
            request(text: body, arguments: [maliciousArgument], skillDirectory: skillDirectory))

        #expect(result.contains("Argument: \(maliciousArgument)"))
        #expect(result.contains("Shell says: \(sentinel)"))
        #expect(!FileManager.default.fileExists(atPath: argumentProbe.path))
        #expect(!FileManager.default.fileExists(atPath: shellProbe.path))
        #expect(!result.contains("/should-never-appear"))
    }
}
