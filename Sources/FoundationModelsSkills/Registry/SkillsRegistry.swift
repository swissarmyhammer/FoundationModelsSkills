import Foundation
import FoundationModelsExtras

/// One catalog row `SkillsRegistry.metadata()` returns: a skill's id, its
/// rendered description and `metadata.*` values, parameter placeholder
/// summaries, and whether it is currently eligible for the model-facing
/// surface (plan.md §6, §7.1).
///
/// Seeds a future `SkillSearchAgent`'s `MetadataSearcher<SkillMetadata>` --
/// a caller building that catalog filters on `isModelVisible` itself
/// (plan.md §10's public API sketch), since `metadata()` returns every
/// catalog entry regardless of surface, model-hidden ones included.
/// `description` and every string scalar inside `metadata` (at any depth)
/// are rendered through `RenderPipeline.renderMetadata` (§5 passes 1 and 3
/// only -- shell injection never runs while building this catalog, since
/// it would otherwise fire on every watcher-driven rebuild rather than
/// once per `use skill`/`/command`/CLI call).
public struct SkillMetadata: Sendable, Equatable {
    /// The canonical id -- the directory name (plan.md §4).
    public var id: String

    /// The rendered `description:`, or an empty string when the skill's
    /// frontmatter carries none.
    public var description: String

    /// Every frontmatter `metadata.*` entry, with every string scalar --
    /// at the top level or nested inside an `.array`/`.dictionary` value --
    /// rendered through the same §5 pass 1+3 rules as `description`.
    ///
    /// Every non-string YAML shape (bool, number, null) is carried through
    /// unchanged, since only a string scalar is meaningful
    /// Stencil/`$`-substitution input.
    public var metadata: [String: FrontmatterValue]

    /// Placeholder summaries of this skill's parameters, e.g. `"<message>"`,
    /// `"[env]"` (plan.md §7's `SkillRow.parameters` shape).
    public var parameters: [String]

    /// Whether this skill is currently eligible for the model-facing
    /// surface: `search skill`/`list skill`/`use skill` (plan.md §6).
    public var isModelVisible: Bool

    /// Creates a `SkillMetadata` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - id: The canonical id -- the directory name.
    ///   - description: The rendered `description:`.
    ///   - metadata: Every frontmatter `metadata.*` entry, every string
    ///     scalar (at any depth) rendered. Defaults to empty.
    ///   - parameters: Placeholder summaries of this skill's parameters.
    ///     Defaults to empty.
    ///   - isModelVisible: Whether this skill is currently eligible for the
    ///     model-facing surface.
    public init(
        id: String, description: String, metadata: [String: FrontmatterValue] = [:],
        parameters: [String] = [], isModelVisible: Bool
    ) {
        self.id = id
        self.description = description
        self.metadata = metadata
        self.parameters = parameters
        self.isModelVisible = isModelVisible
    }
}

/// The error `SkillsRegistry.call(id:arguments:)` throws for an id that is
/// not currently callable.
///
/// Covers both an id the catalog never had at all and one a skill is fully
/// hidden under (plan.md §6's bottom row) -- `SkillsRegistry` never adds a
/// fully hidden skill to its catalog in the first place, so the two cases
/// collapse into the same lookup miss here.
public struct UnknownSkillError: Error, Sendable, Equatable {
    /// The id that was not found.
    public var id: String

    /// Every id currently callable, sorted.
    ///
    /// Lets a caller retry against the live catalog or build its own
    /// corrective message (plan.md §7's "carrying the current id list",
    /// realized generically here -- a model-facing operation layer, a
    /// later task, converts this into its own corrective text).
    public var validIDs: [String]

    /// Creates an `UnknownSkillError`.
    ///
    /// - Parameters:
    ///   - id: The id that was not found.
    ///   - validIDs: Every id currently callable, sorted.
    public init(id: String, validIDs: [String]) {
        self.id = id
        self.validIDs = validIDs
    }
}

/// The Layer-3 source of truth's static half: composes discovery, decoding,
/// validation, and the render pipeline into one catalog built once at
/// construction (plan.md §3, §6, §7.1; decisions #13/#25/#28/#29).
///
/// Reload -- watching every root and rebuilding the catalog on change -- is
/// a separate follow-up type; this one builds its catalog exactly once, at
/// `init`, and never again. `SkillsRegistry` holds no opinion about where
/// skills live: `roots` is entirely the caller's choice, ordered from
/// lowest to highest precedence, the same contract `SkillDiscovery` and
/// `SkillWatcher` already follow (decision #29, amended). A skill
/// `SkillValidator` hides entirely (the retired `partial: true` flag) never
/// enters the catalog at all -- every method below only ever sees the
/// skills that survived validation un-hidden.
public struct SkillsRegistry: Sendable {
    /// The layer roots this registry was constructed over, lowest
    /// precedence first -- exactly as given to `init(roots:policy:)`, or
    /// derived from a `DotfolderStack` by `init(stack:policy:)`.
    public var roots: [URL]

    /// The render policy every render call this registry makes honors
    /// (plan.md decisions #25/#28).
    public var policy: RenderPolicy

    /// Every diagnostic `SkillValidator` raised while building this
    /// registry's catalog, each carrying the winning root's provenance.
    public var diagnostics: [SkillDiagnostic]

    /// This registry's render pipeline, wired to the real passes 1-3.
    private let pipeline: RenderPipeline

    /// Every skill that survived validation un-hidden, keyed by id.
    private let catalog: [String: CatalogEntry]

    /// This registry's catalog entries matching `predicate`, sorted by id.
    ///
    /// The shared iteration order every public listing method builds its
    /// rows from, so `metadata()`, `commandListing()`, and
    /// `preloadedBodies()` can never drift out of sync on how they sort or
    /// filter the same underlying catalog.
    ///
    /// - Parameter predicate: Which catalog entries to include. Defaults to
    ///   every entry.
    /// - Returns: The matching entries, sorted by id.
    private func sortedCatalogEntries(where predicate: (CatalogEntry) -> Bool = { _ in true }) -> [CatalogEntry] {
        catalog.values.filter(predicate).sorted { $0.id < $1.id }
    }

    // MARK: - Construction

    /// Creates a `SkillsRegistry` over an explicit, ordered list of layer
    /// roots, building its catalog once, immediately.
    ///
    /// A bare `URL` carries no signal about whether it roots a trusted,
    /// consumer-shipped directory or an editable one, so every root here
    /// renders under Stencil's untrusted rule (plan.md §5.3) -- there is no
    /// "shipped defaults" concept this initializer can recognize on its
    /// own. A host that already tracks that distinction (e.g. by way of a
    /// `DotfolderStack`) uses `init(stack:policy:)` instead, which
    /// preserves each layer's own trust tag rather than assuming every
    /// root is untrusted.
    ///
    /// - Parameters:
    ///   - roots: The layer roots to build the catalog over, lowest
    ///     precedence first; a later root's copy of an id fully replaces an
    ///     earlier root's copy of the same id.
    ///   - policy: The render policy every render call this registry makes
    ///     honors. Defaults to the permissive `RenderPolicy()`.
    public init(roots: [URL], policy: RenderPolicy = RenderPolicy()) {
        self.init(layers: Self.untrustedLayers(for: roots), policy: policy)
    }

    /// Creates a `SkillsRegistry` over a `DotfolderStack`'s own layers,
    /// building its catalog once, immediately.
    ///
    /// A one-line convenience for hosts that already use `DotfolderStack`
    /// to compute their layer roots -- and, unlike `init(roots:policy:)`,
    /// this one preserves each layer's real trust tag rather than
    /// assuming every root is untrusted: the layer the host tagged as its
    /// shipped-defaults directory renders trusted, every other layer
    /// renders untrusted, exactly Stencil's default trust rule (plan.md
    /// §5.3, decision #29).
    ///
    /// - Parameters:
    ///   - stack: The dotfolder stack to build the catalog over.
    ///   - policy: The render policy every render call this registry makes
    ///     honors. Defaults to the permissive `RenderPolicy()`.
    public init(stack: DotfolderStack, policy: RenderPolicy = RenderPolicy()) {
        self.init(layers: stack.layers, policy: policy)
    }

    /// Builds a `SkillsRegistry` from its already-resolved layers, shared
    /// by both public initializers so `init(roots:policy:)`'s synthesized,
    /// uniformly untrusted layers and `init(stack:policy:)`'s real,
    /// per-layer-trusted ones flow through exactly one construction path.
    ///
    /// - Parameters:
    ///   - layers: The layers to build the catalog over, lowest precedence
    ///     first.
    ///   - policy: The render policy every render call this registry makes
    ///     honors.
    private init(layers: [DotfolderStack.Layer], policy: RenderPolicy) {
        roots = layers.map(\.root)
        self.policy = policy

        let built = Self.buildCatalog(layers: layers)
        catalog = built.catalog
        diagnostics = built.diagnostics
        pipeline = RenderPipeline(
            argumentSubstitution: ArgumentSubstitution(), shellInjection: ShellInjection(),
            stencil: StencilPass(layers: layers))
    }

    /// Wraps every root in a `DotfolderStack.Layer` under Stencil's
    /// untrusted source, so `StencilPass` (partials resolution and the
    /// per-skill trust lookup) and each catalog entry's `winningLayer` have
    /// a `Layer` to work with despite a bare `roots` list carrying no trust
    /// signal of its own.
    ///
    /// - Parameter roots: The layer roots to wrap, in the order given.
    /// - Returns: One untrusted `Layer` per root, same order.
    private static func untrustedLayers(for roots: [URL]) -> [DotfolderStack.Layer] {
        roots.map { DotfolderStack.Layer(source: .project, root: $0) }
    }

    // MARK: - Catalog

    /// One skill that survived validation un-hidden, with everything a
    /// render call or a listing/metadata row needs.
    private struct CatalogEntry: Sendable {
        let id: String
        let frontmatter: SkillFrontmatter
        let body: String
        let skillDirectory: URL
        let winningLayer: DotfolderStack.Layer
        let isModelVisible: Bool
        let isUserInvocable: Bool
        let isPreloaded: Bool

        /// Builds a `CatalogEntry` from one validated, un-hidden skill.
        ///
        /// - Parameters:
        ///   - validated: The validated skill; `validated.isHidden` must
        ///     already be `false` -- the caller excludes hidden skills
        ///     before ever reaching this initializer.
        ///   - discovered: The same skill's discovery record, supplying its
        ///     own directory.
        ///   - winningLayer: The `Layer` `discovered.rootIndex` resolves
        ///     to.
        init(validated: ValidatedSkill, discovered: DiscoveredSkill, winningLayer: DotfolderStack.Layer) {
            id = validated.id
            frontmatter = validated.frontmatter
            body = validated.body
            skillDirectory = discovered.skillDirectory
            self.winningLayer = winningLayer

            let visibility = ResolvedVisibility(validated: validated)
            isModelVisible = visibility.isModelVisible
            isUserInvocable = visibility.isUserInvocable
            isPreloaded = visibility.isPreloaded
        }
    }

    /// Derived model/user/preload visibility for one validated, un-hidden
    /// skill (plan.md §6's table).
    ///
    /// Each axis independently combines the validator's own eligibility
    /// flag (whether the skill can appear on that surface at all -- e.g. an
    /// excluded-for-missing-description skill) with the skill's own
    /// frontmatter opt-out/opt-in for that axis:
    ///
    /// | plan.md §6 row | `isModelVisible` | `isUserInvocable` | `isPreloaded` |
    /// |---|---|---|---|
    /// | default | `true` | `true` | `false` |
    /// | `disable-model-invocation: true` | `false` | `true` | `false` |
    /// | `user-invocable: false` | `true` | `false` | `false` |
    /// | `preload: true` | `true` | `true` | `true` |
    ///
    /// The table's fifth row -- fully hidden -- never reaches this
    /// resolver: `SkillsRegistry` excludes a `ValidatedSkill.isHidden`
    /// skill from the catalog before visibility is ever computed, so every
    /// row this type actually produces is one of the four above.
    private struct ResolvedVisibility: Sendable {
        let isModelVisible: Bool
        let isUserInvocable: Bool
        let isPreloaded: Bool

        /// Derives this visibility from one validated skill.
        ///
        /// - Parameter validated: The validated skill to derive visibility
        ///   for.
        init(validated: ValidatedSkill) {
            isModelVisible =
                validated.isModelVisibleEligible && validated.frontmatter.disableModelInvocation != true
            isUserInvocable = validated.isUserInvocableEligible && validated.frontmatter.userInvocable != false
            isPreloaded = validated.frontmatter.preload == true
        }
    }

    /// Discovers, decodes, and validates every skill across `layers`'
    /// roots, folding the un-hidden survivors into a catalog keyed by id.
    ///
    /// - Parameter layers: The layers to build the catalog over, lowest
    ///   precedence first.
    /// - Returns: The catalog, keyed by id, plus every diagnostic raised
    ///   while validating (including for skills excluded from the
    ///   catalog).
    private static func buildCatalog(
        layers: [DotfolderStack.Layer]
    ) -> (catalog: [String: CatalogEntry], diagnostics: [SkillDiagnostic]) {
        var catalog: [String: CatalogEntry] = [:]
        var diagnostics: [SkillDiagnostic] = []

        for discovered in SkillDiscovery(roots: layers.map(\.root)).discover() {
            guard let validated = Self.validate(discovered, diagnostics: &diagnostics), !validated.isHidden else {
                continue
            }
            catalog[discovered.id] = CatalogEntry(
                validated: validated, discovered: discovered, winningLayer: layers[discovered.rootIndex])
        }

        return (catalog, diagnostics)
    }

    /// Reads `discovered`'s `SKILL.md` and runs it through `SkillValidator`,
    /// appending every diagnostic raised (including its own read-failure
    /// diagnostic, when reading fails) to `diagnostics`.
    ///
    /// - Parameters:
    ///   - discovered: The skill's discovery record.
    ///   - diagnostics: Accumulates every diagnostic raised.
    /// - Returns: The validated skill, or `nil` for unparseable YAML
    ///   (`SkillValidator`'s own `.skipped` outcome) or an unreadable
    ///   `SKILL.md`.
    private static func validate(
        _ discovered: DiscoveredSkill, diagnostics: inout [SkillDiagnostic]
    ) -> ValidatedSkill? {
        do {
            let text = try String(contentsOf: discovered.skillFileURL, encoding: .utf8)
            let result = SkillValidator.validate(discovered: discovered, text: text)
            diagnostics.append(contentsOf: result.diagnostics)
            return result.skill
        } catch {
            diagnostics.append(
                SkillDiagnostic(
                    severity: .skip, skillID: discovered.id,
                    provenance: SkillDiagnostic.Provenance(discovered: discovered),
                    message: "SKILL.md could not be read: \(error.localizedDescription)"))
            return nil
        }
    }

    // MARK: - Rendering helpers

    /// Renders `text` (a `description`/`metadata.*` value) through passes 1
    /// and 3, falling back to `text` unchanged if rendering fails.
    ///
    /// `metadata()`/`commandListing()` are not declared `throws` -- unlike
    /// `call(id:arguments:)`, they build ambient listing/search data rather
    /// than answer one specific, actionable call -- so a render failure
    /// here is absorbed rather than propagated, matching this package's
    /// lenient, never-fatal-in-isolation posture elsewhere (`SkillValidator`,
    /// `FrontmatterDecoder`).
    ///
    /// - Parameters:
    ///   - text: The `description`/`metadata.*` source text to render.
    ///   - entry: The catalog entry `text` belongs to, supplying the render
    ///     request's directory and winning layer.
    /// - Returns: The rendered text, or `text` unchanged on render failure.
    private func renderedMetadataText(_ text: String, entry: CatalogEntry) -> String {
        let request = RenderRequest(
            text: text, skillDirectory: entry.skillDirectory, winningLayer: entry.winningLayer, policy: policy)
        return (try? pipeline.renderMetadata(request)) ?? text
    }

    /// Renders every entry in `entry.frontmatter.metadata` via
    /// `renderedMetadataValue(_:entry:)`, so a string scalar nested at any
    /// depth (e.g. an element of a `metadata.tags:` list) renders too, not
    /// just a top-level scalar.
    ///
    /// - Parameter entry: The catalog entry whose `metadata.*` entries to
    ///   render.
    /// - Returns: `entry.frontmatter.metadata` with every string scalar,
    ///   at any depth, rendered.
    private func renderedMetadataFields(entry: CatalogEntry) -> [String: FrontmatterValue] {
        entry.frontmatter.metadata.mapValues { renderedMetadataValue($0, entry: entry) }
    }

    /// Renders one `FrontmatterValue`: a `.string` renders through
    /// `renderedMetadataText(_:entry:)`; `.array`/`.dictionary` recurse
    /// into every element/value; every other shape (bool, number, null)
    /// passes through unchanged, since only a string scalar is meaningful
    /// Stencil/`$`-substitution input.
    ///
    /// - Parameters:
    ///   - value: The value to render.
    ///   - entry: The catalog entry `value` belongs to.
    /// - Returns: `value` with every nested string scalar rendered.
    private func renderedMetadataValue(_ value: FrontmatterValue, entry: CatalogEntry) -> FrontmatterValue {
        switch value {
        case .string(let raw):
            return .string(renderedMetadataText(raw, entry: entry))
        case .array(let items):
            return .array(items.map { renderedMetadataValue($0, entry: entry) })
        case .dictionary(let mapping):
            return .dictionary(mapping.mapValues { renderedMetadataValue($0, entry: entry) })
        case .int, .double, .bool, .null:
            return value
        }
    }

    /// Infers `entry`'s parameters (plan.md §6.1) and summarizes each as a
    /// display placeholder.
    ///
    /// - Parameter entry: The catalog entry to summarize parameters for.
    /// - Returns: One placeholder summary per inferred parameter, in
    ///   position order.
    private func parameterSummaries(entry: CatalogEntry) -> [String] {
        ParameterInference.infer(frontmatter: entry.frontmatter, body: entry.body)
            .parameters
            .map(Self.parameterSummary)
    }

    /// Summarizes one parameter as a display placeholder: its own
    /// `argument-hint:` token text when it has one, otherwise a
    /// synthesized `<name>`/`[name]` (optionally `...`-suffixed for a
    /// variadic parameter) built from `required`/`variadic`.
    ///
    /// - Parameter parameter: The parameter to summarize.
    /// - Returns: The placeholder summary text.
    private static func parameterSummary(_ parameter: SkillParameter) -> String {
        if let placeholder = parameter.placeholder { return placeholder }
        let name = parameter.variadic ? "\(parameter.name)..." : parameter.name
        return parameter.required ? "<\(name)>" : "[\(name)]"
    }

    // MARK: - metadata()

    /// Every catalog entry's rendered metadata, regardless of surface.
    ///
    /// Includes model-hidden entries (e.g. `disable-model-invocation:
    /// true`) alongside model-visible ones -- a caller filters on
    /// `SkillMetadata.isModelVisible` itself (plan.md §10's public API
    /// sketch), rather than this method pre-filtering. `description` and
    /// every string scalar inside `metadata.*` (at any depth) are rendered
    /// through §5 passes 1 and 3 only, via `RenderPipeline.renderMetadata`
    /// -- never pass 2.
    ///
    /// - Returns: One `SkillMetadata` per catalog entry, sorted by id.
    public func metadata() -> [SkillMetadata] {
        sortedCatalogEntries()
            .map { entry in
                SkillMetadata(
                    id: entry.id,
                    description: renderedMetadataText(entry.frontmatter.description ?? "", entry: entry),
                    metadata: renderedMetadataFields(entry: entry),
                    parameters: parameterSummaries(entry: entry),
                    isModelVisible: entry.isModelVisible)
            }
    }

    // MARK: - commandListing()

    /// The user `/` menu's rows: every catalog entry eligible for the user
    /// surface (plan.md §6.1).
    ///
    /// Includes a model-hidden-but-user-invocable entry (e.g. `deploy`,
    /// `disable-model-invocation: true`); excludes a `user-invocable:
    /// false` entry (e.g. `lint`) entirely. Each row's `description` is
    /// rendered the same §5 pass 1+3 way `metadata()` renders its own.
    ///
    /// - Returns: One `SkillListing` per user-invocable catalog entry,
    ///   sorted by id.
    public func commandListing() -> [SkillListing] {
        sortedCatalogEntries(where: \.isUserInvocable)
            .map(listing(for:))
    }

    /// Builds one `commandListing()` row for `entry`, with its description
    /// rendered.
    ///
    /// - Parameter entry: The catalog entry to build a row for.
    /// - Returns: The row, `description` rendered when present.
    private func listing(for entry: CatalogEntry) -> SkillListing {
        var listing = SkillListing(id: entry.id, frontmatter: entry.frontmatter, body: entry.body)
        if let description = entry.frontmatter.description {
            listing.description = renderedMetadataText(description, entry: entry)
        }
        return listing
    }

    // MARK: - preloadedBodies()

    /// The rendered bodies of every `preload: true` catalog entry, joined
    /// for injection into a root session's `Instructions` at startup
    /// (plan.md §6, §7.1).
    ///
    /// Each body renders through all three §5 passes (`RenderPipeline.renderBody`),
    /// so a `` !`command` `` in a preloaded skill's body re-executes on
    /// every call to this method, exactly as it would on a `use skill`
    /// dispatch -- "dynamic at render, static in transcript" (plan.md §5)
    /// applies here too, not just to `call(id:arguments:)`.
    ///
    /// - Returns: Every preloaded entry's rendered body, sorted by id and
    ///   joined by a blank line; empty when no entry has `preload: true`.
    public func preloadedBodies() -> String {
        sortedCatalogEntries(where: \.isPreloaded)
            .map(renderedBody(for:))
            .joined(separator: "\n\n")
    }

    /// Renders `entry`'s body through all three §5 passes, falling back to
    /// the unrendered body if rendering fails -- the same lenient posture
    /// `renderedMetadataText(_:entry:)` uses, since `preloadedBodies()` is
    /// not declared `throws` either.
    ///
    /// - Parameter entry: The catalog entry whose body to render.
    /// - Returns: The rendered body, or the unrendered body on render
    ///   failure.
    private func renderedBody(for entry: CatalogEntry) -> String {
        let request = RenderRequest(
            text: entry.body, argumentNames: entry.frontmatter.arguments, skillDirectory: entry.skillDirectory,
            winningLayer: entry.winningLayer, policy: policy)
        return (try? pipeline.renderBody(request)) ?? entry.body
    }

    // MARK: - call(id:arguments:)

    /// Dereferences the catalog by `id` and renders that skill's body
    /// through all three §5 passes with `arguments`.
    ///
    /// - Parameters:
    ///   - id: The skill id to call -- the directory name.
    ///   - arguments: The arguments to substitute into the rendered body
    ///     (plan.md §5 pass 1: `$ARGUMENTS`/`$N`/`$name`). Defaults to
    ///     empty.
    /// - Returns: The fully rendered body.
    /// - Throws: `UnknownSkillError` when `id` is not in the catalog --
    ///   unknown outright, or fully hidden from every surface. Otherwise,
    ///   any error a render pass raises (plan.md §5's three passes).
    public func call(id: String, arguments: [String] = []) throws -> String {
        guard let entry = catalog[id] else {
            throw UnknownSkillError(id: id, validIDs: catalog.keys.sorted())
        }
        let request = RenderRequest(
            text: entry.body, arguments: arguments, argumentNames: entry.frontmatter.arguments,
            skillDirectory: entry.skillDirectory, winningLayer: entry.winningLayer, policy: policy)
        return try pipeline.renderBody(request)
    }
}
