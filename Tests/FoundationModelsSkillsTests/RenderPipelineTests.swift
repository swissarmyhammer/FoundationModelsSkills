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

        func render(_ text: String, request: RenderRequest) throws -> String {
            recorder.record(name: name, policy: request.policy)
            return text
        }
    }

    /// A fake pass that ignores its input and always returns `output` --
    /// stands in for a pass whose output is independent of what came before
    /// it (e.g. pass 2 injecting freshly generated shell output).
    private struct ConstantOutputPass: RenderPass {
        let output: String

        func render(_ text: String, request: RenderRequest) throws -> String {
            output
        }
    }

    /// A fake pass that performs a real substitution -- replaces every
    /// literal `$0` with `SUBSTITUTED` -- and records that it ran.
    ///
    /// Recording (rather than just transforming) lets the no-re-scan test
    /// prove **both** that this pass ran exactly once **and** that a later
    /// pass's `$0`-shaped output is never handed back to it -- a plain
    /// identity/no-op check alone couldn't distinguish "ran once, correctly
    /// excluded from later scanning" from "never ran at all".
    private struct SubstitutingPass: RenderPass {
        let recorder: InvocationRecorder

        func render(_ text: String, request: RenderRequest) throws -> String {
            recorder.record(name: "argumentSubstitution", policy: request.policy)
            return text.replacingOccurrences(of: "$0", with: "SUBSTITUTED")
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

    // MARK: - No re-scan: pass-1 syntax in a later pass's output stays literal

    @Test func laterPassOutputContainingPassOneSyntaxIsNotReSubstituted() throws {
        let recorder = InvocationRecorder()
        let pipeline = RenderPipeline(
            argumentSubstitution: SubstitutingPass(recorder: recorder),
            shellInjection: ConstantOutputPass(output: "shell output with literal $0 inside"),
            stencil: IdentityRenderPass())

        let result = try pipeline.renderBody(request(text: "no dollar tokens here"))

        // Pass 1 ran exactly once -- proven by the recorder, not just
        // inferred from the output -- before pass 2 produced its
        // "$0"-shaped output; pass 1 is never re-invoked, so the "$0" pass 2
        // injected survives pass 3 (identity here) completely
        // unsubstituted.
        #expect(recorder.invocations.map(\.name) == ["argumentSubstitution"])
        #expect(result == "shell output with literal $0 inside")
    }

    // MARK: - RenderPolicy plumbing

    @Test func renderPolicyIsPlumbedToEveryBodyPassInvocation() throws {
        let recorder = InvocationRecorder()
        let pipeline = RenderPipeline(
            argumentSubstitution: RecordingPass(name: "argumentSubstitution", recorder: recorder),
            shellInjection: RecordingPass(name: "shellInjection", recorder: recorder),
            stencil: RecordingPass(name: "stencil", recorder: recorder))
        let policy = RenderPolicy(disableShellExecution: true, disableScriptExecution: true)

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
        let policy = RenderPolicy(disableShellExecution: true, disableScriptExecution: true)

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
