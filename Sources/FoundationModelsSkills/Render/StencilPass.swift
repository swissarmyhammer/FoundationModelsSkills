import Foundation
import FoundationModelsExtras

/// Pass 3 of the §5 render pipeline: Stencil templating via Extras'
/// `TemplateEngine` facade.
///
/// Builds a single merged `TemplateContext` implementing the plan.md §5.3
/// precedence ladder -- explicit context (where declared skill arguments
/// also land, as `{{ name }}`) beats environment variables as flat keys
/// (`{{ HOME }}`) beats well-known values (`working_directory`, `date`,
/// `hostname`, `dotfolder_name`) -- then renders through
/// `TemplateEngine.render(_:context:trust:)`, never raw Stencil. Because the
/// merge already happens here, `TemplateEngine`'s own internal
/// environment/well-known rungs never come into play: every key this pass
/// cares about is already present at the "explicit context" rung by the
/// time `TemplateEngine` sees it, which is also what makes this pass
/// deterministically testable despite `TemplateEngine`'s hermetic-test seam
/// being module-internal to `FoundationModelsExtras` (not part of its
/// public surface).
///
/// Trust is derived per render from `RenderRequest.winningLayer`, strictly
/// by the plan.md decision #29 mapping -- the layer the host tagged
/// `.defaults` renders `.trusted`; `.user`/`.project` layers render
/// `.untrusted`. There is no override escape hatch: a host that wants a
/// particular root to render trusted labels it `.defaults` at the layer
/// level (`SkillsRegistry.init(layers:)`), the one sanctioned way to
/// influence this mapping.
///
/// `{% include "header" %}` partials resolve through `DotfolderLoader`,
/// Extras' internal loader that `TemplateEngine.init(partials:)` wires up
/// automatically from a `DotfolderStack` -- `DotfolderLoader` itself is not
/// public API, so this pass builds a `DotfolderStack` directly over `layers`
/// (the host-supplied roots, ordered lowest precedence first) rather than
/// letting a stack derive its own layers from a bare name; `DotfolderStack`
/// exposes `layers` as a mutable property and `Layer.init(source:root:)`
/// publicly for exactly this purpose.
public struct StencilPass: RenderPass {
    /// The host-supplied layer roots this pass resolves `{% include %}`
    /// partials against, ordered lowest precedence first.
    ///
    /// The SAME roots the skill itself was discovered over (plan.md
    /// decision #29), not a stack `TemplateEngine`/`DotfolderStack` derives
    /// on its own; a later root's `_partials/<name>` shadows an earlier
    /// root's copy.
    public var layers: [DotfolderStack.Layer]

    /// The environment dictionary consulted for the ladder's middle rung.
    ///
    /// Defaults to `ProcessInfo.processInfo.environment` (the real process
    /// environment); tests inject a fixed dictionary for deterministic
    /// golden renders.
    public var environment: [String: String]

    /// The well-known system values backing the ladder's lowest rung.
    ///
    /// Defaults to real process state (`WellKnownValues.current(layers:)`)
    /// when not supplied at `init`; tests inject fixed values for
    /// deterministic golden renders.
    public var wellKnownValues: WellKnownValues

    /// Creates a `StencilPass`.
    ///
    /// - Parameters:
    ///   - layers: The host-supplied layer roots to resolve `{% include %}`
    ///     partials against, lowest precedence first. Defaults to empty (no
    ///     partials resolution).
    ///   - environment: The environment dictionary for the ladder's middle
    ///     rung. Defaults to the real process environment.
    ///   - wellKnownValues: The well-known values for the ladder's lowest
    ///     rung. Defaults to `WellKnownValues.current(layers:)` computed
    ///     from `layers` when `nil`.
    public init(
        layers: [DotfolderStack.Layer] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        wellKnownValues: WellKnownValues? = nil
    ) {
        self.layers = layers
        self.environment = environment
        self.wellKnownValues = wellKnownValues ?? .current(layers: layers)
    }

    /// The context-key prefix under which `render(_:request:)` hands each
    /// `.quarantined` span's text to Stencil as an opaque value; the span's
    /// ordinal is appended (`<prefix>0`, `<prefix>1`, ...).
    ///
    /// Public so a test can prove a spliced value spelled exactly like one
    /// of these references still renders literal. A skill author can name a
    /// declared argument this way too, and loses nothing by it: the
    /// quarantine keys are set last, so they always win, and the value they
    /// resolve to is text the same render already spliced in.
    public static let quarantinedSpanContextKeyPrefix = "stencilPassQuarantinedSpan"

    /// Renders `text` as ONE Stencil template through Extras'
    /// `TemplateEngine`, with every `.quarantined` span handed to Stencil as
    /// an opaque context value rather than as template text.
    ///
    /// A `.quarantined` span (an earlier pass's substituted argument value
    /// or shell output) never reaches the template parser at all: the
    /// template Stencil sees carries a `{{ <key> }}` reference in its place,
    /// and the span's text sits in the context under that key. So
    /// `{{ HOME }}`/`{% include %}` syntax it happens to contain stays
    /// literal -- plan.md §5's no-re-scan contract, enforced for pass 3 the
    /// same way pass 2 enforces it for `` !`command` `` -- while the
    /// `.original` text on either side of it still parses as one template,
    /// so a `{% if %}...{% endif %}` block may straddle a splice.
    ///
    /// One template also means one render call, and so ONE set of
    /// `Trust.untrusted` budgets (output size, iteration count, include
    /// depth) for the whole text. `TemplateEngine` allots fresh budgets per
    /// `render` call, so rendering N spans as N templates would hand an
    /// untrusted body N times every limit -- and a body can mint spans for
    /// free with a run of `$N` references. Rendering once closes that gap
    /// without any budget-in seam on Extras' side. The spliced text counts
    /// toward the output budget like any other rendered text.
    ///
    /// A splice inside a Stencil delimiter pair -- a variable (`{{ $1 }}`,
    /// `{{$1}}`, `{{ "$1" }}`), a tag (`{% if $1 %}`), or a comment
    /// (`{# $1 #}`) -- is a rendering error this pass raises itself, before
    /// Stencil ever parses the template. Substituted data must never drive
    /// template structure, and Stencil's lexer is not quote-aware, so the
    /// `{{ <key> }}` reference standing where the data was would otherwise
    /// render garbage rather than fail. A bare `{` immediately before a
    /// splice stays literal (`{$1}` renders `{value}`); see
    /// `template(for:injectingQuarantinedSpansInto:)`.
    ///
    /// - Parameters:
    ///   - text: The input text to render -- pass 2's output (body renders)
    ///     or pass 1's output (metadata renders), since this pass always
    ///     runs last in both `RenderPipeline` pass-sets.
    ///   - request: The render request this pass runs under;
    ///     `winningLayer` selects the trust mode, `arguments`/
    ///     `argumentNames` populate the explicit context's declared skill
    ///     arguments.
    /// - Returns: The rendered text as a single `.quarantined` span: every
    ///   byte of it is this pass's own output, which no later pass may scan
    ///   (`RenderPass`'s contract; this pass is last in both pass-sets, so
    ///   in practice the pipeline flattens it straight away).
    /// - Throws: `TemplateEngineError.renderingFailed` when Stencil fails to
    ///   parse or render the template, or when the resolved
    ///   `Trust.untrusted` validation rejects it (a disallowed tag/filter,
    ///   an include-depth bomb, an output-size bomb, or an iteration bomb).
    public func render(_ text: QuarantinedText, request: RenderRequest) throws -> QuarantinedText {
        let engine = TemplateEngine(partials: Self.partialsStack(layers: layers))
        var context = templateContext(for: request)
        let template = try Self.template(for: text, injectingQuarantinedSpansInto: &context)
        let rendered = try engine.render(template, context: context, trust: resolvedTrust(for: request.winningLayer))
        return QuarantinedText(spans: [.quarantined(rendered)])
    }

    /// Stencil's three delimiter pairs -- variable, tag, comment -- as
    /// `(opener, closer)`; `endsInsideOpenDelimiter(_:)` reads them to tell
    /// whether template text stops partway through one.
    private static let delimiterPairs: [(opener: String, closer: String)] = [
        (opener: "{{", closer: "}}"), (opener: "{%", closer: "%}"), (opener: "{#", closer: "#}"),
    ]

    /// Builds the single template `render(_:request:)` hands to Stencil:
    /// `text`'s `.original` spans verbatim, and a `{{ <key> }}` reference in
    /// place of each `.quarantined` span, whose text lands in `context`
    /// under that key.
    ///
    /// A splice that would land inside an open delimiter pair -- template
    /// text so far that has opened a `{{`, `{%`, or `{#` and not yet closed
    /// it -- is refused here, as a `TemplateEngineError.renderingFailed`.
    /// Substituted data inside a variable, tag, or comment could only ever
    /// name a variable, steer a tag, or vanish, and Stencil's lexer is not
    /// quote-aware, so letting the reference through would render garbage
    /// (`{{ $1 }}` became `{{ {{ key }} }}`, an empty variable followed by
    /// a literal ` }}`) rather than fail.
    ///
    /// A run of bare `{` at the very end of the text before a splice is
    /// moved out of the template and onto the front of the spliced value.
    /// It is always literal text there: any `{` that opened real syntax
    /// would be part of an open delimiter, refused above. Leaving it in the
    /// template would fuse with the reference's own `{{` (`{$1}` becoming
    /// `{{{ key }}}`), which Stencil reads as a garbled variable; moving it
    /// renders `{value}`.
    ///
    /// - Parameters:
    ///   - text: The pass's input.
    ///   - context: The render's context; receives one `.string` entry per
    ///     `.quarantined` span, keyed by `quarantinedSpanContextKeyPrefix`
    ///     plus the span's ordinal. Set after every other rung, so nothing
    ///     else can shadow a key.
    /// - Returns: The template text.
    /// - Throws: `TemplateEngineError.renderingFailed` when a `.quarantined`
    ///   span sits inside an open Stencil delimiter pair.
    private static func template(for text: QuarantinedText, injectingQuarantinedSpansInto context: inout TemplateContext)
        throws -> String
    {
        var template = ""
        var quarantinedSpanCount = 0
        for span in text.spans {
            switch span {
            case .original(let spanText):
                template += spanText
            case .quarantined(let spliced):
                guard !Self.endsInsideOpenDelimiter(template) else {
                    throw TemplateEngineError.renderingFailed(
                        message:
                            "a substituted value sits inside a Stencil variable, tag, or comment; substituted data can never form template syntax"
                    )
                }
                let key = "\(quarantinedSpanContextKeyPrefix)\(quarantinedSpanCount)"
                quarantinedSpanCount += 1
                context.set(key: key, to: .string(Self.movingTrailingBraces(from: &template, ontoFrontOf: spliced)))
                template += "{{ \(key) }}"
            }
        }
        return template
    }

    /// Reports whether `template` ends partway through one of
    /// `delimiterPairs`: some opener occurs after every closer.
    ///
    /// - Parameter template: The template text built so far.
    /// - Returns: `true` when the last opener in `template` is not followed
    ///   by any closer.
    private static func endsInsideOpenDelimiter(_ template: String) -> Bool {
        let lastOpener = delimiterPairs.compactMap { template.range(of: $0.opener, options: .backwards)?.lowerBound }.max()
        let lastCloser = delimiterPairs.compactMap { template.range(of: $0.closer, options: .backwards)?.lowerBound }.max()
        guard let lastOpener else { return false }
        return lastCloser.map { $0 < lastOpener } ?? true
    }

    /// Strips every trailing `{` from `template`, and returns `value` with
    /// the stripped braces prepended.
    ///
    /// - Parameters:
    ///   - template: The template text built so far; trailing braces are
    ///     removed from it.
    ///   - value: The spliced value about to follow `template`.
    /// - Returns: `value`, prefixed with whatever `template` lost.
    private static func movingTrailingBraces(from template: inout String, ontoFrontOf value: String) -> String {
        var moved = ""
        while template.last == "{" {
            template.removeLast()
            moved.append("{")
        }
        return moved + value
    }

    /// Resolves `layer`'s `Trust` by the plan.md decision #29 mapping.
    ///
    /// - Parameter layer: The winning layer to resolve trust for.
    /// - Returns: `.trusted` for a `.defaults` layer; `.untrusted` for any
    ///   other source.
    private func resolvedTrust(for layer: DotfolderStack.Layer) -> TemplateEngine.Trust {
        layer.source == .defaults ? .trusted : .untrusted
    }

    /// Builds this render's merged `TemplateContext`: well-known values
    /// lowest, `environment` next, declared skill arguments highest.
    ///
    /// - Parameter request: The render request supplying the declared
    ///   argument names/values for the explicit-context rung.
    /// - Returns: The merged context, ready for `TemplateEngine.render`.
    private func templateContext(for request: RenderRequest) -> TemplateContext {
        var context = TemplateContext()
        for (key, value) in wellKnownValues.templateValues {
            context.set(key: key, to: value)
        }
        for (key, value) in environment {
            context.set(key: key, to: .string(value))
        }
        for (name, value) in Self.namedArguments(for: request) {
            context.set(key: name, to: .string(value))
        }
        return context
    }

    /// Pairs each *distinct* name in `request.argumentNames` with its
    /// positional value, tokenized and indexed the same way
    /// `ArgumentSubstitution`'s own `.named` branch resolves `$name` -- so
    /// `$name` (pass 1) and `{{ name }}` (this pass) always agree on which
    /// supplied argument a declared name refers to, including a name past
    /// the supplied argument count or a name declared more than once.
    ///
    /// `ArgumentSubstitution` resolves `$name` via
    /// `argumentNames.firstIndex(of: name)` -- always that name's *first*
    /// occurrence, regardless of how many later positions repeat it -- so
    /// a repeated name here is paired only once, at its first occurrence's
    /// position, rather than once per occurrence (which would let a later
    /// `context.set` for the same key silently overwrite the first with a
    /// different position's value). A name with no corresponding supplied
    /// value pairs with `""`, exactly as `ArgumentSubstitution` substitutes
    /// `$name` in that case -- every declared name is always set at the
    /// explicit-context rung, so none can fall through to an environment
    /// variable or well-known value of the same key (plan.md §5.3's ladder
    /// would otherwise leak host state a skill author never supplied).
    ///
    /// - Parameter request: The render request supplying `arguments` and
    ///   `argumentNames`.
    /// - Returns: `(name, value)` pairs, one per distinct name in
    ///   `request.argumentNames`, in first-occurrence order; empty when
    ///   `argumentNames` is empty.
    private static func namedArguments(for request: RenderRequest) -> [(name: String, value: String)] {
        guard !request.argumentNames.isEmpty else { return [] }
        let positionalArguments = ArgumentSubstitution.shellStyleTokens(
            request.arguments.joined(separator: " "))
        var seenNames: Set<String> = []
        return request.argumentNames.enumerated().compactMap { index, name in
            guard seenNames.insert(name).inserted else { return nil }
            return (name: name, value: positionalArguments[safe: index] ?? "")
        }
    }

    /// Builds the `DotfolderStack` `TemplateEngine.init(partials:)` uses to
    /// resolve `{% include %}` over `layers`.
    ///
    /// `DotfolderStack` exposes no initializer that takes `layers` directly,
    /// so this builds a throwaway stack (name and working directory are
    /// irrelevant -- construction performs no I/O) and immediately replaces
    /// its derived layers with the host-supplied ones.
    ///
    /// - Parameter layers: The host-supplied layer roots, lowest precedence
    ///   first.
    /// - Returns: A stack wrapping exactly `layers`, or `nil` when `layers`
    ///   is empty (no partials resolution).
    private static func partialsStack(layers: [DotfolderStack.Layer]) -> DotfolderStack? {
        guard !layers.isEmpty else { return nil }
        var stack = DotfolderStack(
            name: "stencil-pass-partials", workingDirectory: URL(fileURLWithPath: "/", isDirectory: true))
        stack.layers = layers
        return stack
    }
}

extension StencilPass {
    /// The well-known system values backing the plan.md §5.3 precedence
    /// ladder's lowest rung: `working_directory`, `date`, `hostname`, and
    /// `dotfolder_name`.
    ///
    /// Extras' own equivalent type (`WellKnownValues`, backing
    /// `TemplateEngine`'s internal ladder) is module-internal, not part of
    /// its public surface, so `StencilPass` carries this small mirror:
    /// `current(layers:)` derives the real values for production use,
    /// and every field is independently injectable for deterministic tests.
    public struct WellKnownValues: Sendable {
        /// The current working directory.
        public var workingDirectory: String
        /// Today's date.
        public var date: String
        /// The current machine's hostname.
        public var hostname: String
        /// The dotfolder name recovered from the `.project`-sourced layer
        /// among the roots given to `current(layers:)`, or `nil` when none
        /// was found (or none was given).
        public var dotfolderName: String?

        /// Creates a `WellKnownValues`.
        ///
        /// - Parameters:
        ///   - workingDirectory: The current working directory.
        ///   - date: Today's date.
        ///   - hostname: The current machine's hostname.
        ///   - dotfolderName: The dotfolder name, or `nil` when there is
        ///     none. Defaults to `nil`.
        public init(workingDirectory: String, date: String, hostname: String, dotfolderName: String? = nil) {
            self.workingDirectory = workingDirectory
            self.date = date
            self.hostname = hostname
            self.dotfolderName = dotfolderName
        }

        /// This value's fields as `TemplateValue`s, keyed ready to overlay
        /// into a `TemplateContext`.
        ///
        /// `dotfolder_name` is present only when `dotfolderName` is
        /// non-`nil`.
        var templateValues: [String: TemplateValue] {
            var values: [String: TemplateValue] = [
                "working_directory": .string(workingDirectory),
                "date": .string(date),
                "hostname": .string(hostname),
            ]
            if let dotfolderName {
                values["dotfolder_name"] = .string(dotfolderName)
            }
            return values
        }

        /// Formats `date` as a bare calendar date fixed to UTC, so the
        /// string does not depend on the running machine's local time zone.
        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter
        }()

        /// Derives the real well-known values from process state: the
        /// current working directory, today's UTC date, this machine's
        /// hostname, and (when `layers` carries a `.project`-sourced layer)
        /// its dotfolder name.
        ///
        /// - Parameter layers: The host-supplied layer roots to recover a
        ///   `dotfolder_name` from. Defaults to empty (no `dotfolder_name`).
        /// - Returns: The derived well-known values.
        public static func current(layers: [DotfolderStack.Layer] = []) -> WellKnownValues {
            WellKnownValues(
                workingDirectory: FileManager.default.currentDirectoryPath,
                date: dateFormatter.string(from: Date()),
                hostname: ProcessInfo.processInfo.hostName,
                dotfolderName: Self.projectDotfolderName(in: layers))
        }

        /// Recovers a bare dotfolder name (e.g. `"myagent"`) from `layers`'
        /// highest-precedence `.project`-sourced layer's root directory name
        /// (`<workingDirectory>/.myagent`).
        ///
        /// The same derivation Extras' `TemplateEngine` applies to a
        /// `DotfolderStack`'s own layers, with one deliberate difference:
        /// Extras takes the *first* `.project` layer, because
        /// `DotfolderStack.init` appends exactly one; this takes the *last*.
        /// `layers` is ordered lowest precedence first (the same convention
        /// every other layer-ordered method in this package follows), so the
        /// *last* matching layer -- not the first -- is the winning one.
        /// This matters for `SkillsRegistry.init(roots:)`'s unlabeled
        /// convenience, which tags every root `.project`: picking the first
        /// match there would silently resolve the lowest-precedence root's
        /// name instead of the intended project root's. For a stack-derived
        /// layer list (`SkillsRegistry.init(stack:)`) the two agree, since
        /// only one `.project` layer exists.
        ///
        /// - Parameter layers: The host-supplied layer roots to search.
        /// - Returns: The dotfolder name, or `nil` when `layers` carries no
        ///   `.project`-sourced layer.
        private static func projectDotfolderName(in layers: [DotfolderStack.Layer]) -> String? {
            guard let projectLayer = layers.last(where: { $0.source == .project }) else { return nil }
            let directoryName = projectLayer.root.lastPathComponent
            return directoryName.hasPrefix(".") ? String(directoryName.dropFirst()) : directoryName
        }
    }
}
