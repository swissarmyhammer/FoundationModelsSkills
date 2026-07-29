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
/// Trust is derived per render from `RenderRequest.winningLayer`: the
/// `trustOverrides` table is consulted first (root -> `Trust`, so a host can
/// override any individual root), falling back to the plan.md decision #29
/// default -- the layer the host tagged `.defaults` renders `.trusted`;
/// `.user`/`.project` layers render `.untrusted`.
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

    /// Per-root `Trust` overrides, consulted before the default rule.
    ///
    /// Empty by default -- every root then renders under the default rule
    /// (`layer.source == .defaults` -> `.trusted`, otherwise `.untrusted`).
    /// A host that wants a specific root to render trusted (or untrusted)
    /// regardless of its `Source` tag sets an entry here, keyed by that
    /// root's `URL`.
    public var trustOverrides: [URL: TemplateEngine.Trust]

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
    ///   - trustOverrides: Per-root `Trust` overrides, consulted before the
    ///     default rule. Defaults to empty.
    ///   - environment: The environment dictionary for the ladder's middle
    ///     rung. Defaults to the real process environment.
    ///   - wellKnownValues: The well-known values for the ladder's lowest
    ///     rung. Defaults to `WellKnownValues.current(layers:)` computed
    ///     from `layers` when `nil`.
    public init(
        layers: [DotfolderStack.Layer] = [],
        trustOverrides: [URL: TemplateEngine.Trust] = [:],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        wellKnownValues: WellKnownValues? = nil
    ) {
        self.layers = layers
        self.trustOverrides = trustOverrides
        self.environment = environment
        self.wellKnownValues = wellKnownValues ?? .current(layers: layers)
    }

    /// Renders `text`'s `.original` spans as Stencil templates through
    /// Extras' `TemplateEngine`, leaving every `.quarantined` span untouched.
    ///
    /// A `.quarantined` span (an earlier pass's substituted argument value
    /// or shell output) is never handed to `TemplateEngine` at all, so
    /// `{{ HOME }}`/`{% include %}` syntax it happens to contain stays
    /// literal -- plan.md §5's no-re-scan contract, enforced for pass 3 the
    /// same way pass 2 enforces it for `` !`command` ``. Each `.original`
    /// span renders as its own independent template; a Stencil construct
    /// (e.g. `{% if %}...{% endif %}`) cannot legitimately span across a
    /// quarantined splice, since substituted data must never drive new
    /// template structure.
    ///
    /// - Parameters:
    ///   - text: The input text to render -- pass 2's output (body renders)
    ///     or pass 1's output (metadata renders), since this pass always
    ///     runs last in both `RenderPipeline` pass-sets.
    ///   - request: The render request this pass runs under;
    ///     `winningLayer` selects the trust mode, `arguments`/
    ///     `argumentNames` populate the explicit context's declared skill
    ///     arguments.
    /// - Returns: `text` with every `.original` span rendered as a Stencil
    ///   template.
    /// - Throws: `TemplateEngineError.renderingFailed` when Stencil fails to
    ///   parse or render an `.original` span, or when the resolved
    ///   `Trust.untrusted` validation rejects it (a disallowed tag/filter,
    ///   an include-depth bomb, an output-size bomb, or an iteration bomb).
    public func render(_ text: QuarantinedText, request: RenderRequest) throws -> QuarantinedText {
        let engine = TemplateEngine(partials: Self.partialsStack(layers: layers))
        let context = templateContext(for: request)
        let trust = resolvedTrust(for: request.winningLayer)
        return try text.mappingOriginalSpans { spanText in
            [.original(try engine.render(spanText, context: context, trust: trust))]
        }
    }

    /// Resolves `layer`'s `Trust`: `trustOverrides` first, the default rule
    /// otherwise.
    ///
    /// - Parameter layer: The winning layer to resolve trust for.
    /// - Returns: `trustOverrides[layer.root]` when present; otherwise
    ///   `.trusted` for a `.defaults` layer and `.untrusted` for any other
    ///   source.
    private func resolvedTrust(for layer: DotfolderStack.Layer) -> TemplateEngine.Trust {
        trustOverrides[layer.root] ?? (layer.source == .defaults ? .trusted : .untrusted)
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
        /// `.project`-sourced layer's root directory name
        /// (`<workingDirectory>/.myagent`), mirroring
        /// `DotfolderStack.projectDotfolderName`.
        ///
        /// - Parameter layers: The host-supplied layer roots to search.
        /// - Returns: The dotfolder name, or `nil` when `layers` carries no
        ///   `.project`-sourced layer.
        private static func projectDotfolderName(in layers: [DotfolderStack.Layer]) -> String? {
            guard let projectLayer = layers.first(where: { $0.source == .project }) else { return nil }
            let directoryName = projectLayer.root.lastPathComponent
            return directoryName.hasPrefix(".") ? String(directoryName.dropFirst()) : directoryName
        }
    }
}
