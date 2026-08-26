import Foundation
import FoundationModelsExtras

/// Policy flags that gate side-effecting render-pipeline passes.
///
/// Set once at `SkillsRegistry` construction so every render path --
/// model-driven `use skill`, user-driven `/command`, and the CLI -- honors
/// the same policy (plan.md decisions #25/#28). `ShellInjection` (pass 2)
/// reads `isShellExecutionDisabled`; `isScriptExecutionDisabled` is read by
/// the M6 `run script` resource operation, outside this pipeline entirely.
public struct RenderPolicy: Sendable, Equatable {
    /// Asserts `` !`command` ``/fenced shell injection (pass 2) is disabled.
    ///
    /// When `true`, the pass substitutes an inert marker instead of running
    /// anything (plan.md decision #25). Immutable: a `RenderPolicy` is a
    /// construction-time invariant, never mutated after `SkillsRegistry`
    /// captures it.
    public let isShellExecutionDisabled: Bool
    /// Asserts the M6 `run script` resource operation is disabled.
    ///
    /// Enforced downstream, not by this pipeline (plan.md decision #28).
    /// Immutable for the same reason as `isShellExecutionDisabled`.
    public let isScriptExecutionDisabled: Bool

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

/// One render invocation's inputs.
///
/// Carries the text to render, the arguments supplied at call time, the
/// skill's `arguments:` frontmatter names, the skill's own directory, the
/// dotfolder layer that won the skill, and the policy every pass must honor
/// (plan.md §5). Not mutated by
/// `RenderPipeline` during a render call -- each pass receives the same
/// `RenderRequest` and returns transformed text rather than writing back
/// into the request; only the pipeline's local working text is rebound
/// between passes.
public struct RenderRequest: Sendable {
    /// The text to render.
    ///
    /// A skill body, or one `description`/`metadata.*` value (plan.md §5's
    /// "Templated: description, all metadata values, and the body").
    public var text: String
    /// The arguments supplied to `use skill`/`/command`/the CLI, in order.
    ///
    /// Pass 1's raw material for `$ARGUMENTS`/`$N`/`$name` substitution.
    /// Empty for a `description`/`metadata.*` render, which carries no
    /// per-call arguments.
    public var arguments: [String]
    /// The skill's `arguments:` frontmatter names, in declared order.
    ///
    /// Pass 1's name->position table for `$name` substitution (plan.md §5:
    /// "`$name` -- named arg from the `arguments:` frontmatter"). Position
    /// `i` in this array corresponds to position `i` of the shell-tokenized
    /// positional arguments that `$i`/`$ARGUMENTS[i]` also index (all of
    /// `arguments` joined as typed, then split by `ArgumentSubstitution`'s
    /// own shell-style tokenizer) -- **not** necessarily index `i` of
    /// `arguments` itself, since an `arguments` element containing
    /// unprotected whitespace re-splits into more than one position on
    /// retokenization. A caller building `arguments` element-by-element
    /// (rather than typing one raw command line) should quote any
    /// multi-word value it supplies, the same discipline `$N`/`$ARGUMENTS[N]`
    /// already require. Deliberately **not** `argument-hint:`- or
    /// body-inferred names (`SkillParameter`'s broader §6.1 merge) --
    /// `$name` resolves only against the authoritative `arguments:` list, so
    /// a `$word` that isn't a declared argument name (e.g. `$HOME`) is left
    /// untouched rather than misread as a reference. Empty for a
    /// `description`/`metadata.*` render, like `arguments`.
    public var argumentNames: [String]
    /// The skill's own directory.
    ///
    /// Used as `${SKILL_DIR}` (pass 1) and the shell injection working
    /// directory (pass 2, body renders only).
    public var skillDirectory: URL
    /// The dotfolder layer that won this skill.
    ///
    /// From `DotfolderStack` -- pass 3's trust mapping (defaults ->
    /// `.trusted`, user/project -> `.untrusted`, plan.md §5, decision #29).
    public var winningLayer: DotfolderStack.Layer
    /// The render policy every pass must honor.
    ///
    /// Threaded unchanged to every pass invocation in this render call --
    /// gates pass 2 (`isShellExecutionDisabled`) and the M6 `run script`
    /// operation outside this pipeline (`isScriptExecutionDisabled`), per
    /// plan.md decisions #25/#28.
    public var policy: RenderPolicy

    /// Creates a `RenderRequest`.
    ///
    /// - Parameters:
    ///   - text: The text to render.
    ///   - arguments: The arguments supplied at call time, in order.
    ///     Defaults to empty.
    ///   - argumentNames: The skill's `arguments:` frontmatter names, in
    ///     declared order. Defaults to empty.
    ///   - skillDirectory: The skill's own directory.
    ///   - winningLayer: The dotfolder layer that won this skill.
    ///   - policy: The render policy every pass must honor.
    public init(
        text: String,
        arguments: [String] = [],
        argumentNames: [String] = [],
        skillDirectory: URL,
        winningLayer: DotfolderStack.Layer,
        policy: RenderPolicy
    ) {
        self.text = text
        self.arguments = arguments
        self.argumentNames = argumentNames
        self.skillDirectory = skillDirectory
        self.winningLayer = winningLayer
        self.policy = policy
    }
}

/// One render-pipeline pass.
///
/// A single-shot text transform over a render request (plan.md §5).
/// `RenderPipeline` invokes each pass at most once per `render` call, in a
/// fixed order, feeding it the previous pass's output. Operates on
/// `QuarantinedText`, not a plain `String`, so the no-re-scan contract is
/// structural rather than a convention each pass must remember: a
/// conforming pass scans and substitutes only within `.original` spans (via
/// `QuarantinedText.mappingOriginalSpans(_:)`), marking anything it splices
/// in as `.quarantined` so no later pass -- in this call or any other --
/// ever scans text it, or an earlier pass, already produced.
public protocol RenderPass: Sendable {
    /// Transforms `text` for `request`.
    ///
    /// - Parameters:
    ///   - text: The input text -- the render request's original `text`,
    ///     wrapped as a single `.original` span, for the first pass in a
    ///     pass-set; the previous pass's output for every pass after it.
    ///   - request: The render request this pass runs under, including the
    ///     `RenderPolicy` every side-effecting pass must honor.
    /// - Returns: The transformed text, passed unchanged to the next pass in
    ///   the set (or flattened into the pipeline's final result, for the
    ///   set's last pass).
    /// - Throws: Any error a conforming pass raises while transforming
    ///   `text`; see each conforming type for the specific errors it can
    ///   throw.
    func render(_ text: QuarantinedText, request: RenderRequest) throws -> QuarantinedText
}

/// A pass that returns its input unchanged.
///
/// A testing/scaffold stand-in for any of the three §5 passes
/// (`ArgumentSubstitution`, `ShellInjection`, `StencilPass`) -- used by
/// `RenderPipeline.identity` and by tests that only care about a subset of
/// the pass-set's behavior.
public struct IdentityRenderPass: RenderPass {
    /// Creates an `IdentityRenderPass`.
    ///
    /// Takes no configuration -- every instance behaves identically, so the
    /// pipeline can create as many as it needs without shared state.
    public init() {}

    /// Returns `text` unchanged (identity transformation).
    ///
    /// - Parameters:
    ///   - text: The input text; returned unchanged.
    ///   - request: The render request this pass runs under. Ignored -- an
    ///     identity pass has no side effects to gate.
    /// - Returns: `text`, unchanged.
    /// - Throws: Never; this pass performs an identity transformation and
    ///   never fails.
    public func render(_ text: QuarantinedText, request: RenderRequest) throws -> QuarantinedText {
        text
    }
}

/// The §5 render pipeline: three ordered, single-shot passes.
///
/// Argument substitution, shell injection, and Stencil, assembled into the
/// two pass-sets plan.md §5 defines (decision #25). `renderBody` runs all
/// three passes; `renderMetadata` runs only passes 1 and 3, since shell
/// execution must never fire while building `description`/`metadata.*`
/// values (a watcher-driven reload path, not a per-call one). Both methods
/// run their pass-set exactly once, in order, threading each pass's output
/// into the next -- the single-shot, no-re-scan contract `RenderPass`
/// documents.
public struct RenderPipeline: Sendable {
    /// Pass 1: argument + variable substitution (plan.md §5.1).
    ///
    /// `SkillsRegistry` wires this to a real `ArgumentSubstitution` instance;
    /// `IdentityRenderPass` remains available as a scaffold/testing default
    /// (`RenderPipeline.identity`).
    public var argumentSubstitution: any RenderPass
    /// Pass 2: shell injection, body renders only (plan.md §5.2, decision #25).
    ///
    /// `SkillsRegistry` wires this to a real `ShellInjection` instance.
    public var shellInjection: any RenderPass
    /// Pass 3: Stencil templating (plan.md §5.3).
    ///
    /// `SkillsRegistry` wires this to a real `StencilPass` instance.
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

    /// A pipeline wired with `IdentityRenderPass` for all three §5 passes.
    ///
    /// A testing/scaffold default -- `SkillsRegistry` wires a real
    /// `RenderPipeline` (`ArgumentSubstitution`/`ShellInjection`/
    /// `StencilPass`) directly, never through this property.
    public static var identity: RenderPipeline {
        RenderPipeline(
            argumentSubstitution: IdentityRenderPass(),
            shellInjection: IdentityRenderPass(),
            stencil: IdentityRenderPass())
    }

    /// Renders a skill body.
    ///
    /// Runs passes 1, 2, then 3, in that fixed order (plan.md §5).
    ///
    /// - Parameter request: The render request; `request.text` is the
    ///   body's source text.
    /// - Returns: The fully rendered body.
    /// - Throws: Any error thrown by a render pass in the pipeline (passes
    ///   1, 2, and 3).
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
    /// - Throws: Any error thrown by a render pass in the pipeline (passes
    ///   1 and 3).
    public func renderMetadata(_ request: RenderRequest) throws -> String {
        try run(passes: [argumentSubstitution, stencil], request: request)
    }

    /// Runs `passes` once each, in order.
    ///
    /// Threads each pass's output through to the next as input -- the
    /// shared, single-shot execution engine both `renderBody` and
    /// `renderMetadata` build on. Starts from `request.text` wrapped as a
    /// single `.original` `QuarantinedText` span, and flattens the last
    /// pass's output back to a plain `String` only once every pass has run,
    /// so a `.quarantined` span any pass produces stays invisible to every
    /// later pass in `passes` (plan.md §5's no-re-scan contract).
    ///
    /// - Parameters:
    ///   - passes: The ordered pass-set to run, exactly once each.
    ///   - request: The render request; only `request.text` is superseded
    ///     between passes, by each pass's returned output.
    /// - Returns: The last pass's output, flattened.
    /// - Throws: Any error thrown by a pass in `passes`.
    private func run(passes: [any RenderPass], request: RenderRequest) throws -> String {
        var text = QuarantinedText(original: request.text)
        for pass in passes {
            text = try pass.render(text, request: request)
        }
        return text.flattened
    }
}
