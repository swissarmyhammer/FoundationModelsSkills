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

    // MARK: - Shared budgets: N splices never multiply the single-render limits (^q1mywft)

    /// The number of `$0` splices the budget fixtures repeat -- enough that
    /// the per-span loop sums below cross one of Extras' untrusted limits in
    /// aggregate while each span alone stays well under every limit.
    private static let spliceCount = 50

    /// Builds a body of `spliceCount` repetitions of `$0` followed by
    /// `fragment`, so pass 1 splits it into `spliceCount` `.original` spans
    /// separated by `.quarantined` argument values.
    private static func repeatedSpliceBody(fragment: String) -> String {
        String(repeating: "$0\(fragment)", count: spliceCount)
    }

    /// One `{% for %}` per span of 3000 empty iterations: 3000 sits far
    /// under the 100k iteration limit, 50 x 3000 = 150k does not.
    private static let iterationBudgetFragment = "{% for i in 1...3000 %}{% endfor %}"

    /// One `{% for %}` per span of 1500 x 16 bytes = 24 KiB: 24 KiB sits far
    /// under the 1 MiB output limit and 1500 iterations far under the 100k
    /// iteration limit; 50 x 24 KiB = 1.2 MiB crosses the output limit
    /// while 50 x 1500 = 75k iterations still does not cross the other.
    private static let outputBudgetFragment = "{% for i in 1...1500 %}0123456789abcdef{% endfor %}"

    @Test(
        "a 50-splice untrusted body draws every span's loops from ONE shared budget",
        arguments: [
            (name: "iteration budget", fragment: RenderPipelineNoRescanTests.iterationBudgetFragment),
            (name: "output budget", fragment: RenderPipelineNoRescanTests.outputBudgetFragment),
        ])
    func fiftySpliceUntrustedBodyCannotExceedTheSingleRenderBudgets(name: String, fragment: String) throws {
        let skillDirectory = try makeTempDirectory()
        let body = Self.repeatedSpliceBody(fragment: fragment)

        #expect(throws: TemplateEngineError.self, "\(name)") {
            try realPipeline().renderBody(request(text: body, arguments: ["x"], skillDirectory: skillDirectory))
        }
    }

    @Test func singleSpliceBodyUnderTheBudgetsRendersSoTheBudgetFixtureIsValidTemplateText() throws {
        let skillDirectory = try makeTempDirectory()

        let result = try realPipeline().renderBody(
            request(text: "$0\(Self.iterationBudgetFragment)", arguments: ["x"], skillDirectory: skillDirectory))

        #expect(result == "x\n\nARGUMENTS: x")
    }

    // MARK: - Empty quarantined spans never split an original span

    @Test func emptyArgumentSubstitutionNoLongerSplitsTheOriginalSpanAroundIt() throws {
        let skillDirectory = try makeTempDirectory()
        let body = "{% if flag %}$1{% endif %}"

        let substituted = try ArgumentSubstitution().render(
            QuarantinedText(original: body), request: request(text: body, skillDirectory: skillDirectory))

        #expect(substituted.spans == [.original("{% if flag %}{% endif %}")])
    }

    @Test func emptyShellOutputNoLongerSplitsTheOriginalSpanAroundIt() throws {
        let skillDirectory = try makeTempDirectory()
        let body = "before !`true`after"

        let injected = try ShellInjection().render(
            QuarantinedText(original: body), request: request(text: body, skillDirectory: skillDirectory))

        #expect(injected.spans == [.original("before after")])
    }
}
