import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Skeleton tests for the §5 render pipeline (plan.md §5, decision #25):
/// fixed pass order, the body/metadata pass-set split, the single-shot
/// no-re-scan invariant, and `RenderPolicy` plumbing -- all provable with
/// identity and recording fakes, before any pass does real work.
struct RenderPipelineTests {
    /// One `RenderPass.render` call that a `RecordingPass` recorded.
    private struct Invocation: Sendable {
        /// The name of the pass that ran.
        let name: String

        /// The policy of the request that the pass received.
        let policy: RenderPolicy
    }

    /// A fake pass that records its own name and the request's policy, then
    /// returns `text` unchanged (an identity pass with a recording
    /// side-effect).
    private struct RecordingPass: RenderPass, ShellRenderPass {
        let name: String
        let recorder: Recorder<Invocation>

        func render(_ text: QuarantinedText, request: RenderRequest) throws -> QuarantinedText {
            recorder.record(Invocation(name: name, policy: request.policy))
            return text
        }
    }

    /// Builds a `RenderRequest` with sensible fixed defaults -- callers
    /// override only the fields the test cares about.
    private func request(
        text: String = "body text", arguments: [String] = [], policy: RenderPolicy = RenderPolicy()
    ) -> RenderRequest {
        RenderRequest(
            text: text,
            arguments: arguments,
            skillDirectory: URL(fileURLWithPath: "/tmp/render-pipeline-tests/skill", isDirectory: true),
            winningLayer: DotfolderStack.Layer(
                source: .project,
                root: URL(fileURLWithPath: "/tmp/render-pipeline-tests/.skills", isDirectory: true)),
            policy: policy)
    }

    // MARK: - Fixed order 1 -> 2 -> 3

    @Test func bodyRenderRunsPassesInFixedOrderOneThroughThree() async throws {
        let recorder = Recorder<Invocation>()
        let pipeline = RenderPipeline(
            argumentSubstitution: RecordingPass(name: "argumentSubstitution", recorder: recorder),
            shellInjection: RecordingPass(name: "shellInjection", recorder: recorder),
            stencil: RecordingPass(name: "stencil", recorder: recorder))

        _ = try await pipeline.renderBody(request())

        #expect(recorder.recorded.map(\.name) == ["argumentSubstitution", "shellInjection", "stencil"])
    }

    // MARK: - Metadata render path never invokes pass 2

    @Test func metadataRenderNeverInvokesShellInjectionPass() throws {
        let recorder = Recorder<Invocation>()
        let pipeline = RenderPipeline(
            argumentSubstitution: RecordingPass(name: "argumentSubstitution", recorder: recorder),
            shellInjection: RecordingPass(name: "shellInjection", recorder: recorder),
            stencil: RecordingPass(name: "stencil", recorder: recorder))

        _ = try pipeline.renderMetadata(request())

        #expect(recorder.recorded.map(\.name) == ["argumentSubstitution", "stencil"])
        #expect(!recorder.recorded.map(\.name).contains("shellInjection"))
    }

    // MARK: - No re-scan: a model-supplied argument can't drive execution/templating

    @Test func modelSuppliedArgumentContainingInjectionSyntaxNeverExecutesOrTemplates() async throws {
        // The full CRITICAL-severity regression this task fixes (^r3bhwdp):
        // wired with the REAL passes 1-3, a `$ARGUMENTS` value containing
        // `` !`...` `` and `{{ }}` syntax must render as inert literal text --
        // never spawn a process, never expand a template tag. `RenderPipelineNoRescanTests`
        // carries the full acceptance-criteria matrix; this is the
        // pipeline-level pin.
        // The pass gets the real process environment, thus `{{ HOME }}` names
        // a value that a template of this render could resolve. The assertion
        // below then proves the quarantine, and not an empty ladder.
        let pipeline = RenderPipeline(
            argumentSubstitution: ArgumentSubstitution(), shellInjection: ShellInjection(),
            stencil: StencilPass(environment: ProcessInfo.processInfo.environment))
        let maliciousArgument = "!`echo pwned` {{ HOME }}"

        let result = try await pipeline.renderBody(
            request(text: "Argument: $ARGUMENTS", arguments: [maliciousArgument]))

        #expect(result == "Argument: \(maliciousArgument)")
    }

    // MARK: - RenderPolicy plumbing

    @Test func renderPolicyIsPlumbedToEveryBodyPassInvocation() async throws {
        let recorder = Recorder<Invocation>()
        let pipeline = RenderPipeline(
            argumentSubstitution: RecordingPass(name: "argumentSubstitution", recorder: recorder),
            shellInjection: RecordingPass(name: "shellInjection", recorder: recorder),
            stencil: RecordingPass(name: "stencil", recorder: recorder))
        let policy = RenderPolicy(isShellExecutionDisabled: true, isScriptExecutionDisabled: true)

        _ = try await pipeline.renderBody(request(policy: policy))

        #expect(recorder.recorded.count == 3)
        for invocation in recorder.recorded {
            #expect(invocation.policy == policy)
        }
    }

    @Test func renderPolicyIsPlumbedToEveryMetadataPassInvocation() throws {
        let recorder = Recorder<Invocation>()
        let pipeline = RenderPipeline(
            argumentSubstitution: RecordingPass(name: "argumentSubstitution", recorder: recorder),
            shellInjection: RecordingPass(name: "shellInjection", recorder: recorder),
            stencil: RecordingPass(name: "stencil", recorder: recorder))
        let policy = RenderPolicy(isShellExecutionDisabled: true, isScriptExecutionDisabled: true)

        _ = try pipeline.renderMetadata(request(policy: policy))

        #expect(recorder.recorded.map(\.name) == ["argumentSubstitution", "stencil"])
        for invocation in recorder.recorded {
            #expect(invocation.policy == policy)
        }
    }

    // MARK: - Identity scaffold

    @Test func identityPipelineReturnsBodyTextUnchanged() async throws {
        let text = "Hello $0, !`echo hi`, {{ HOME }}"
        let result = try await RenderPipeline.identity.renderBody(request(text: text))
        #expect(result == text)
    }

    @Test func identityPipelineReturnsMetadataTextUnchanged() throws {
        let text = "A description with {{ working_directory }} in it."
        let result = try RenderPipeline.identity.renderMetadata(request(text: text))
        #expect(result == text)
    }
}
