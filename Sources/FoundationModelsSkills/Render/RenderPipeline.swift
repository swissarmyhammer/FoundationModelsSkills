import Foundation
import FoundationModelsExtras

/// Policy flags that gate side-effecting render-pipeline passes.
///
/// Set once at `SkillsRegistry` construction so every render path --
/// model-driven `use skill`, user-driven `/command`, and the CLI -- honors
/// the same policy. `ShellInjection` (pass 2)
/// reads `isShellExecutionDisabled`; `isScriptExecutionDisabled` is read by
/// the `run script` resource operation, outside this pipeline entirely.
public struct RenderPolicy: Sendable, Equatable {
    /// Asserts `` !`command` ``/fenced shell injection (pass 2) is disabled.
    ///
    /// When `true`, the pass substitutes an inert marker instead of running
    /// anything. Immutable: a `RenderPolicy` is a
    /// construction-time invariant, never mutated after `SkillsRegistry`
    /// captures it.
    public let isShellExecutionDisabled: Bool
    /// Asserts the `run script` resource operation is disabled.
    ///
    /// Enforced downstream, not by this pipeline.
    /// Immutable for the same reason as `isShellExecutionDisabled`.
    public let isScriptExecutionDisabled: Bool

    /// How long one `` !`command` ``/fenced shell command can run before
    /// `ShellInjection` kills its whole process group.
    ///
    /// A command that passes this limit writes no output into the body: the
    /// pass writes an inert marker in its place and renders the rest of the
    /// body. Immutable for the same reason as the two flags.
    public let shellCommandTimeout: Duration

    /// The most bytes of merged output `ShellInjection` holds for one
    /// command.
    ///
    /// The read of the output stops at this limit, thus a command that
    /// writes without end cannot grow the memory of the host. A command that
    /// passes the limit writes no output into the body: the pass writes an
    /// inert marker in its place. Immutable for the same reason as the two
    /// flags.
    public let shellOutputByteLimit: Int

    /// The seconds that `defaultShellCommandTimeout` is made of.
    ///
    /// The `Duration` below carries the value; this constant names the number
    /// that builds it, thus the file holds no unnamed literal.
    private static let defaultShellCommandTimeoutSeconds = 30

    /// The `shellCommandTimeout` a host that states none gets.
    ///
    /// Long enough for the `git`, `date` and `ls` calls a skill body usually
    /// makes, and short enough that a command which hangs does not hold the
    /// render of a turn.
    public static let defaultShellCommandTimeout: Duration =
        .seconds(defaultShellCommandTimeoutSeconds)

    /// The `shellOutputByteLimit` a host that states none gets.
    ///
    /// One mebibyte: far above the output of a command a skill body usually
    /// makes, and small enough that a command which writes without end costs
    /// a bounded amount of memory.
    public static let defaultShellOutputByteLimit = 1_048_576

    /// Creates a `RenderPolicy`.
    ///
    /// Both flags default to `false`, the permissive default -- hosts opt
    /// into restriction explicitly. Both limits default to the safe values
    /// above, which a host overrides to widen or to narrow them.
    ///
    /// - Parameters:
    ///   - isShellExecutionDisabled: Disables pass 2 when `true`.
    ///   - isScriptExecutionDisabled: Disables the `run script` operation
    ///     when `true`.
    ///   - shellCommandTimeout: How long one shell command of pass 2 can run.
    ///   - shellOutputByteLimit: The most bytes of output pass 2 holds for one
    ///     command.
    public init(
        isShellExecutionDisabled: Bool = false,
        isScriptExecutionDisabled: Bool = false,
        shellCommandTimeout: Duration = RenderPolicy.defaultShellCommandTimeout,
        shellOutputByteLimit: Int = RenderPolicy.defaultShellOutputByteLimit
    ) {
        self.isShellExecutionDisabled = isShellExecutionDisabled
        self.isScriptExecutionDisabled = isScriptExecutionDisabled
        self.shellCommandTimeout = shellCommandTimeout
        self.shellOutputByteLimit = shellOutputByteLimit
    }
}

/// One render invocation's inputs.
///
/// Carries the text to render, the arguments supplied at call time, the
/// skill's `arguments:` frontmatter names, the skill's own directory, the
/// dotfolder layer that won the skill, and the policy every pass must honor. Not mutated by
/// `RenderPipeline` during a render call -- each pass receives the same
/// `RenderRequest` and returns transformed text rather than writing back
/// into the request; only the pipeline's local working text is rebound
/// between passes.
public struct RenderRequest: Sendable {
    /// The text to render.
    ///
    /// A skill body, or one `description`/`metadata.*` value. The
    /// description, all metadata values, and the body are templated.
    public var text: String
    /// The arguments supplied to `use skill`/`/command`/the CLI, in order.
    ///
    /// Pass 1's raw material for `$ARGUMENTS`/`$N`/`$name` substitution.
    /// Empty for a `description`/`metadata.*` render, which carries no
    /// per-call arguments.
    public var arguments: [String]
    /// The skill's `arguments:` frontmatter names, in declared order.
    ///
    /// Pass 1's name->position table for `$name` substitution: `$name` is a
    /// named argument from the `arguments:` frontmatter. Position
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
    /// body-inferred names (`SkillParameter`'s broader merge) --
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
    /// `.trusted`, user/project -> `.untrusted`).
    public var winningLayer: DotfolderStack.Layer
    /// The render policy every pass must honor.
    ///
    /// Threaded unchanged to every pass invocation in this render call --
    /// gates pass 2 (`isShellExecutionDisabled`) and the `run script`
    /// operation outside this pipeline (`isScriptExecutionDisabled`).
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
/// A single-shot text transform over a render request.
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

/// The one render-pipeline pass that waits for a child process.
///
/// Pass 2 starts a shell command for each injection site and waits for it to
/// end, thus its transform suspends where a `RenderPass` transform returns at
/// once. The two protocols stand apart so that `RenderPipeline.renderMetadata`
/// -- which never runs pass 2 -- stays synchronous, and with it every catalog
/// reader that builds a `description`/`metadata.*` value.
///
/// A synchronous transform satisfies this requirement as it stands, thus
/// `IdentityRenderPass` stands in for pass 2 with no second body.
public protocol ShellRenderPass: Sendable {
    /// Transforms `text` for `request`, waiting for each command it starts.
    ///
    /// - Parameters:
    ///   - text: The input text -- the output of pass 1.
    ///   - request: The render request this pass runs under, including the
    ///     `RenderPolicy` this pass must honor.
    /// - Returns: The transformed text, passed on to pass 3.
    /// - Throws: Any error a conforming pass raises while transforming
    ///   `text`; see each conforming type for the specific errors it can
    ///   throw.
    func render(_ text: QuarantinedText, request: RenderRequest) async throws -> QuarantinedText
}

/// A pass that returns its input unchanged.
///
/// A testing/scaffold stand-in for any of the three render passes
/// (`ArgumentSubstitution`, `ShellInjection`, `StencilPass`) -- used by
/// `RenderPipeline.identity` and by tests that only care about a subset of
/// the pass-set's behavior.
public struct IdentityRenderPass: RenderPass, ShellRenderPass {
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

/// The render pipeline: three ordered, single-shot passes.
///
/// Argument substitution, shell injection, and Stencil, assembled into the
/// two pass-sets. `renderBody` runs all
/// three passes; `renderMetadata` runs only passes 1 and 3, since shell
/// execution must never fire while building `description`/`metadata.*`
/// values (a watcher-driven reload path, not a per-call one). Both methods
/// run their pass-set exactly once, in order, threading each pass's output
/// into the next -- the single-shot, no-re-scan contract `RenderPass`
/// documents.
public struct RenderPipeline: Sendable {
    /// Pass 1: argument + variable substitution.
    ///
    /// `SkillsRegistry` wires this to a real `ArgumentSubstitution` instance;
    /// `IdentityRenderPass` remains available as a scaffold/testing default
    /// (`RenderPipeline.identity`).
    public var argumentSubstitution: any RenderPass
    /// Pass 2: shell injection, body renders only.
    ///
    /// `SkillsRegistry` wires this to a real `ShellInjection` instance.
    public var shellInjection: any ShellRenderPass
    /// Pass 3: Stencil templating.
    ///
    /// `SkillsRegistry` wires this to a real `StencilPass` instance.
    public var stencil: any RenderPass

    /// Creates a `RenderPipeline` from its three named passes.
    ///
    /// - Parameters:
    ///   - argumentSubstitution: Pass 1.
    ///   - shellInjection: Pass 2, body renders only.
    ///   - stencil: Pass 3.
    public init(
        argumentSubstitution: any RenderPass, shellInjection: any ShellRenderPass, stencil: any RenderPass
    ) {
        self.argumentSubstitution = argumentSubstitution
        self.shellInjection = shellInjection
        self.stencil = stencil
    }

    /// A pipeline wired with `IdentityRenderPass` for all three render passes.
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
    /// Runs passes 1, 2, then 3, in that fixed order.
    ///
    /// Suspends while pass 2 waits for the shell command of each injection
    /// site, thus the body pass-set runs its three passes by hand rather than
    /// through the `run(passes:request:)` loop that `renderMetadata` shares:
    /// pass 2 alone carries the `async` transform.
    ///
    /// - Parameter request: The render request; `request.text` is the
    ///   body's source text.
    /// - Returns: The fully rendered body.
    /// - Throws: Any error thrown by a render pass in the pipeline (passes
    ///   1, 2, and 3).
    public func renderBody(_ request: RenderRequest) async throws -> String {
        let substituted = try argumentSubstitution.render(QuarantinedText(original: request.text), request: request)
        let injected = try await shellInjection.render(substituted, request: request)
        return try stencil.render(injected, request: request).flattened
    }

    /// Renders a `description`/`metadata.*` value: passes 1 and 3 only.
    ///
    /// Pass 2 (shell injection) never runs here -- `description`/
    /// `metadata.*` values render at metadata-build/reload/list time, where
    /// shell execution would fire on every watcher event rather than once
    /// per call.
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
    /// single-shot execution engine `renderMetadata` builds on.
    /// `renderBody` runs its own three passes, because pass 2 suspends.
    /// Starts from `request.text` wrapped as a
    /// single `.original` `QuarantinedText` span, and flattens the last
    /// pass's output back to a plain `String` only once every pass has run,
    /// so a `.quarantined` span any pass produces stays invisible to every
    /// later pass in `passes`.
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
