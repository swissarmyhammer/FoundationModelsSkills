import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Skeleton tests for the §5 render pipeline (plan.md §5, decision #25):
/// fixed pass order, the body/metadata pass-set split, the single-shot
/// no-re-scan invariant, and `RenderPolicy` plumbing -- all provable with
/// identity and recording fakes, before any pass does real work.
struct RenderPipelineTests {
    /// Records each `RenderPass.render` invocation it participates in --
    /// `@unchecked Sendable` because these tests call the pipeline
    /// synchronously, single-threaded (mirrors
    /// `FoundationModelsShelltool`'s `WarningRecorder` test-fake pattern).
    private final class InvocationRecorder: @unchecked Sendable {
        private(set) var invocations: [(name: String, policy: RenderPolicy)] = []

        func record(name: String, policy: RenderPolicy) {
            invocations.append((name: name, policy: policy))
        }
    }

    /// A fake pass that records its own name and the request's policy, then
    /// returns `text` unchanged (an identity pass with a recording
    /// side-effect).
    private struct RecordingPass: RenderPass {
        let name: String
        let recorder: InvocationRecorder

        func render(_ text: QuarantinedText, request: RenderRequest) throws -> QuarantinedText {
            recorder.record(name: name, policy: request.policy)
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

    @Test func bodyRenderRunsPassesInFixedOrderOneThroughThree() throws {
        let recorder = InvocationRecorder()
        let pipeline = RenderPipeline(
            argumentSubstitution: RecordingPass(name: "argumentSubstitution", recorder: recorder),
            shellInjection: RecordingPass(name: "shellInjection", recorder: recorder),
            stencil: RecordingPass(name: "stencil", recorder: recorder))

        _ = try pipeline.renderBody(request())

        #expect(recorder.invocations.map(\.name) == ["argumentSubstitution", "shellInjection", "stencil"])
    }

    // MARK: - Metadata render path never invokes pass 2

    @Test func metadataRenderNeverInvokesShellInjectionPass() throws {
        let recorder = InvocationRecorder()
        let pipeline = RenderPipeline(
            argumentSubstitution: RecordingPass(name: "argumentSubstitution", recorder: recorder),
            shellInjection: RecordingPass(name: "shellInjection", recorder: recorder),
            stencil: RecordingPass(name: "stencil", recorder: recorder))

        _ = try pipeline.renderMetadata(request())

        #expect(recorder.invocations.map(\.name) == ["argumentSubstitution", "stencil"])
        #expect(!recorder.invocations.map(\.name).contains("shellInjection"))
    }

    // MARK: - No re-scan: a model-supplied argument can't drive execution/templating

    @Test func modelSuppliedArgumentContainingInjectionSyntaxNeverExecutesOrTemplates() throws {
        // The full CRITICAL-severity regression this task fixes (^r3bhwdp):
        // wired with the REAL passes 1-3, a `$ARGUMENTS` value containing
        // `` !`...` `` and `{{ }}` syntax must render as inert literal text --
        // never spawn a process, never expand a template tag. `RenderPipelineNoRescanTests`
        // carries the full acceptance-criteria matrix; this is the
        // pipeline-level pin.
        let pipeline = RenderPipeline(
            argumentSubstitution: ArgumentSubstitution(), shellInjection: ShellInjection(), stencil: StencilPass())
        let maliciousArgument = "!`echo pwned` {{ HOME }}"

        let result = try pipeline.renderBody(request(text: "Argument: $ARGUMENTS", arguments: [maliciousArgument]))

        #expect(result == "Argument: \(maliciousArgument)")
    }

    // MARK: - RenderPolicy plumbing

    @Test func renderPolicyIsPlumbedToEveryBodyPassInvocation() throws {
        let recorder = InvocationRecorder()
        let pipeline = RenderPipeline(
            argumentSubstitution: RecordingPass(name: "argumentSubstitution", recorder: recorder),
            shellInjection: RecordingPass(name: "shellInjection", recorder: recorder),
            stencil: RecordingPass(name: "stencil", recorder: recorder))
        let policy = RenderPolicy(isShellExecutionDisabled: true, isScriptExecutionDisabled: true)

        _ = try pipeline.renderBody(request(policy: policy))

        #expect(recorder.invocations.count == 3)
        for invocation in recorder.invocations {
            #expect(invocation.policy == policy)
        }
    }

    @Test func renderPolicyIsPlumbedToEveryMetadataPassInvocation() throws {
        let recorder = InvocationRecorder()
        let pipeline = RenderPipeline(
            argumentSubstitution: RecordingPass(name: "argumentSubstitution", recorder: recorder),
            shellInjection: RecordingPass(name: "shellInjection", recorder: recorder),
            stencil: RecordingPass(name: "stencil", recorder: recorder))
        let policy = RenderPolicy(isShellExecutionDisabled: true, isScriptExecutionDisabled: true)

        _ = try pipeline.renderMetadata(request(policy: policy))

        #expect(recorder.invocations.map(\.name) == ["argumentSubstitution", "stencil"])
        for invocation in recorder.invocations {
            #expect(invocation.policy == policy)
        }
    }

    // MARK: - Identity scaffold

    @Test func identityPipelineReturnsBodyTextUnchanged() throws {
        let text = "Hello $0, !`echo hi`, {{ HOME }}"
        let result = try RenderPipeline.identity.renderBody(request(text: text))
        #expect(result == text)
    }

    @Test func identityPipelineReturnsMetadataTextUnchanged() throws {
        let text = "A description with {{ working_directory }} in it."
        let result = try RenderPipeline.identity.renderMetadata(request(text: text))
        #expect(result == text)
    }
}
