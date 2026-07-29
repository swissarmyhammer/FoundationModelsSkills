import Foundation
import FoundationModelsExtras

// Review fix (^8jqwxc5): both flags were originally named
// `disableShellExecution`/`disableScriptExecution`, which reads as an
// imperative rather than a state assertion. Renamed to
// `isShellExecutionDisabled`/`isScriptExecutionDisabled` to follow the
// boolean assertion naming pattern.
/// Policy flags that gate side-effecting render-pipeline passes, set once at
/// `SkillsRegistry` construction so every render path -- model-driven `use
/// skill`, user-driven `/command`, and the CLI -- honors the same policy
/// (plan.md decisions #25/#28).
///
/// Neither flag does anything yet: this task's three passes are identity
/// transforms. `ShellInjection` (pass 2) reads `isShellExecutionDisabled`
/// once it lands; `isScriptExecutionDisabled` is read by the M6 `run script`
/// resource operation, outside this pipeline entirely.
public struct RenderPolicy: Sendable, Equatable {
    /// Asserts `` !`command` ``/fenced shell injection (pass 2) is disabled.
    ///
    /// When `true`, the pass substitutes an inert marker instead of running
    /// anything (plan.md decision #25).
    public var isShellExecutionDisabled: Bool
    /// Asserts the M6 `run script` resource operation is disabled.
    ///
    /// Enforced downstream, not by this pipeline (plan.md decision #28).
    public var isScriptExecutionDisabled: Bool

    /// Creates a `RenderPolicy`.
    ///
    /// Both flags default to `false`, the permissive default -- hosts opt
    /// into restriction explicitly.
    ///
    /// - Parameters:
    ///   - isShellExecutionDisabled: Disables pass 2 when `true`.
    ///   - isScriptExecutionDisabled: Disables the M6 `run script` operation
    ///     when `true`.
    public init(isShellExecutionDisabled: Bool = false, isScriptExecutionDisabled: Bool = false) {
        self.isShellExecutionDisabled = isShellExecutionDisabled
        self.isScriptExecutionDisabled = isScriptExecutionDisabled
    }
}

/// One render invocation's inputs: the text to render, the arguments
/// supplied at call time, the skill's own directory, the dotfolder layer
/// that won the skill, and the policy every pass must honor (plan.md §5).
///
/// Not mutated by `RenderPipeline` during a render call -- each pass
/// receives the same `RenderRequest` and returns transformed text rather
/// than writing back into the request; only the pipeline's local working
/// text is rebound between passes.
public struct RenderRequest: Sendable {
    /// The text to render -- a skill body, or one `description`/
    /// `metadata.*` value (plan.md §5's "Templated: description, all
    /// metadata values, and the body").
    public var text: String
    /// The arguments supplied to `use skill`/`/command`/the CLI, in order.
    ///
    /// Pass 1's raw material for `$ARGUMENTS`/`$N`/`$name` substitution.
    /// Empty for a `description`/`metadata.*` render, which carries no
    /// per-call arguments.
    public var arguments: [String]
    /// The skill's own directory -- `${SKILL_DIR}` (pass 1) and the shell
    /// injection working directory (pass 2, body renders only).
    public var skillDirectory: URL
    /// The dotfolder layer that won this skill, from `DotfolderStack` --
    /// pass 3's trust mapping (defaults -> `.trusted`, user/project ->
    /// `.untrusted`, plan.md §5, decision #29).
    public var winningLayer: DotfolderStack.Layer
    /// The render policy every pass must honor (plan.md decisions #25/#28).
    public var policy: RenderPolicy

    /// Creates a `RenderRequest`.
    ///
    /// - Parameters:
    ///   - text: The text to render.
    ///   - arguments: The arguments supplied at call time, in order.
    ///     Defaults to empty.
    ///   - skillDirectory: The skill's own directory.
    ///   - winningLayer: The dotfolder layer that won this skill.
    ///   - policy: The render policy every pass must honor.
    public init(
        text: String,
        arguments: [String] = [],
        skillDirectory: URL,
        winningLayer: DotfolderStack.Layer,
        policy: RenderPolicy
    ) {
        self.text = text
        self.arguments = arguments
        self.skillDirectory = skillDirectory
        self.winningLayer = winningLayer
        self.policy = policy
    }
}

/// One render-pipeline pass: a single-shot text transform over a render
/// request (plan.md §5).
///
/// `RenderPipeline` invokes each pass at most once per `render` call, in a
/// fixed order, feeding it the previous pass's output. No pass is ever
/// re-invoked within one render, and a pass's own output is never handed
/// back to it or to an earlier pass -- conforming types must not attempt to
/// re-scan text they, or an earlier pass, already produced.
public protocol RenderPass: Sendable {
    /// Transforms `text` for `request`.
    ///
    /// - Parameters:
    ///   - text: The input text -- the render request's original `text` for
    ///     the first pass in a pass-set, or the previous pass's output for
    ///     every pass after it.
    ///   - request: The render request this pass runs under, including the
    ///     `RenderPolicy` every side-effecting pass must honor.
    /// - Returns: The transformed text, passed unchanged to the next pass in
    ///   the set (or returned as the pipeline's final result, for the set's
    ///   last pass).
    func render(_ text: String, request: RenderRequest) throws -> String
}

/// A pass that returns its input unchanged.
///
/// The placeholder implementation for all three §5 passes until each is
/// replaced by its own render task (`ArgumentSubstitution`,
/// `ShellInjection`, the Stencil pass) -- this task wires the pipeline's
/// shape, not any pass's real behavior.
public struct IdentityRenderPass: RenderPass {
    /// Creates an `IdentityRenderPass`.
    public init() {}

    public func render(_ text: String, request: RenderRequest) throws -> String {
        text
    }
}

/// The §5 render pipeline: three ordered, single-shot passes -- argument
/// substitution, shell injection, Stencil -- assembled into the two pass-sets
/// plan.md §5 defines (decision #25).
///
/// `renderBody` runs all three passes; `renderMetadata` runs only passes 1
/// and 3, since shell execution must never fire while building
/// `description`/`metadata.*` values (a watcher-driven reload path, not a
/// per-call one). Both methods run their pass-set exactly once, in order,
/// threading each pass's output into the next -- the single-shot,
/// no-re-scan contract `RenderPass` documents.
public struct RenderPipeline: Sendable {
    /// Pass 1: argument + variable substitution (plan.md §5.1).
    ///
    /// Identity in this task.
    public var argumentSubstitution: any RenderPass
    /// Pass 2: shell injection, body renders only (plan.md §5.2, decision
    /// #25).
    ///
    /// Identity in this task.
    public var shellInjection: any RenderPass
    /// Pass 3: Stencil templating (plan.md §5.3).
    ///
    /// Identity in this task.
    public var stencil: any RenderPass

    /// Creates a `RenderPipeline` from its three named passes.
    ///
    /// - Parameters:
    ///   - argumentSubstitution: Pass 1.
    ///   - shellInjection: Pass 2, body renders only.
    ///   - stencil: Pass 3.
    public init(argumentSubstitution: any RenderPass, shellInjection: any RenderPass, stencil: any RenderPass) {
        self.argumentSubstitution = argumentSubstitution
        self.shellInjection = shellInjection
        self.stencil = stencil
    }

    /// A pipeline wired with `IdentityRenderPass` for all three §5 passes --
    /// this task's scaffold default.
    ///
    /// `SkillsRegistry` (a later task) swaps each pass out for its real
    /// implementation as it lands.
    public static var identity: RenderPipeline {
        RenderPipeline(
            argumentSubstitution: IdentityRenderPass(),
            shellInjection: IdentityRenderPass(),
            stencil: IdentityRenderPass())
    }

    /// Renders a skill **body**: passes 1, 2, then 3, in that fixed order
    /// (plan.md §5).
    ///
    /// - Parameter request: The render request; `request.text` is the
    ///   body's source text.
    /// - Returns: The fully rendered body.
    public func renderBody(_ request: RenderRequest) throws -> String {
        try run(passes: [argumentSubstitution, shellInjection, stencil], request: request)
    }

    /// Renders a `description`/`metadata.*` value: passes 1 and 3 only.
    ///
    /// Pass 2 (shell injection) never runs here -- `description`/
    /// `metadata.*` values render at metadata-build/reload/list time, where
    /// shell execution would fire on every watcher event rather than once
    /// per call (plan.md §5, decision #25).
    ///
    /// - Parameter request: The render request; `request.text` is the
    ///   `description`/`metadata.*` value's source text.
    /// - Returns: The fully rendered value.
    public func renderMetadata(_ request: RenderRequest) throws -> String {
        try run(passes: [argumentSubstitution, stencil], request: request)
    }

    /// Runs `passes` once each, in order, threading each pass's output text
    /// into the next as input -- the shared, single-shot execution engine
    /// both `renderBody` and `renderMetadata` build on.
    ///
    /// - Parameters:
    ///   - passes: The ordered pass-set to run, exactly once each.
    ///   - request: The render request; only `request.text` is superseded
    ///     between passes, by each pass's returned output.
    /// - Returns: The last pass's output.
    private func run(passes: [any RenderPass], request: RenderRequest) throws -> String {
        var text = request.text
        for pass in passes {
            text = try pass.render(text, request: request)
        }
        return text
    }
}
