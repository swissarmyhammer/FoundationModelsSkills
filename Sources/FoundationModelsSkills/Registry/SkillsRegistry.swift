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

/// The Layer-3 source of truth: composes discovery, decoding, validation,
/// and the render pipeline into a catalog, built once at construction and
/// optionally kept fresh thereafter (plan.md §3, §6, §7, §7.1; decisions
/// #13/#25/#28/#29).
///
/// `SkillsRegistry` holds no opinion about where skills live: `roots` is
/// entirely the caller's choice, ordered from lowest to highest precedence,
/// the same contract `SkillDiscovery` and `SkillWatcher` already follow
/// (decision #29, amended). A skill `SkillValidator` hides entirely (the
/// retired `partial: true` flag) never enters the catalog at all -- every
/// method below only ever sees the skills that survived validation
/// un-hidden.
///
/// With `watch: false` (the default), the catalog never changes after
/// `init` returns. With `watch: true`, a `SkillWatcher` observes every
/// layer root and rebuilds the catalog on its coalesced signal; the rebuild
/// swaps in a whole new catalog atomically, so `metadata()`,
/// `commandListing()`, `preloadedBodies()`, `call(id:arguments:)`, and
/// `diagnostics` always read one complete generation of the catalog, never
/// a partially-rebuilt one, regardless of how many readers query
/// concurrently with a rebuild. `onReload` publishes the refreshed
/// `[SkillMetadata]` once per rebuild -- the seam a future
/// `SkillSearchAgent`'s `update(items:)` and preload refresh hang off
/// (plan.md §7.1). The watcher this registry wires is owned by it: every
/// copy of a `watch: true` registry shares one underlying watcher, stopped
/// (and `onReload` finished) once the last copy is deinitialized.
public struct SkillsRegistry: Sendable {
    /// The layer roots this registry was constructed over, lowest
    /// precedence first -- exactly as given to `init(roots:policy:watch:)`,
    /// or derived from a `DotfolderStack` by `init(stack:policy:watch:)`.
    public var roots: [URL]

    /// The render policy every render call this registry makes honors
    /// (plan.md decisions #25/#28).
    public var policy: RenderPolicy

    /// Every diagnostic `SkillValidator` raised while building this
    /// registry's current catalog generation, each carrying the winning
    /// root's provenance.
    ///
    /// Reflects the same catalog generation `metadata()`,
    /// `commandListing()`, and `preloadedBodies()` currently read --
    /// refreshed after every watcher-driven rebuild, same as they are.
    public var diagnostics: [SkillDiagnostic] {
        catalogBox.snapshot.diagnostics
    }

    /// Pushed publications of this registry's refreshed metadata list, one
    /// per watcher-driven rebuild (plan.md §7's reload seam; §7.1's future
    /// `SkillSearchAgent.update(items:)` and preload-refresh consumers hang
    /// off this).
    ///
    /// Each element is the full, current `metadata()` list -- not an
    /// incremental diff, the same full-catalog contract `metadata()` itself
    /// carries. `nil` when this registry was constructed with `watch:
    /// false`, since a registry that never reloads has nothing to publish;
    /// finishes once this registry (and every copy sharing its watcher) is
    /// deinitialized.
    public let onReload: AsyncStream<[SkillMetadata]>?

    /// This registry's render pipeline, wired to the real passes 1-3.
    private let pipeline: RenderPipeline

    /// The atomically-swappable holder for this registry's current catalog
    /// generation and its diagnostics.
    ///
    /// Every copy of a given `SkillsRegistry` shares the same `CatalogBox`
    /// instance, so a rebuild triggered through one copy's watcher is
    /// immediately visible to every other copy.
    private let catalogBox: CatalogBox

    /// Owns the `SkillWatcher` and `onReload` continuation for a `watch:
    /// true` registry; `nil` for `watch: false`.
    ///
    /// Retained purely for its lifetime: `ReloadCoordinator.deinit` stops
    /// the watcher and finishes `onReload`, so keeping this field alive for
    /// as long as any copy of the registry exists is what makes the
    /// watcher's lifecycle "owned by the registry" a real guarantee rather
    /// than a comment.
    private let reloadCoordinator: ReloadCoordinator?

    /// This registry's current catalog generation, keyed by id.
    private var catalog: [String: CatalogEntry] {
        catalogBox.snapshot.catalog
    }

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
    ///   - watch: Whether to watch every root and rebuild the catalog on
    ///     change (plan.md §7). Defaults to `false` -- a static catalog,
    ///     matching this initializer's prior behavior.
    public init(roots: [URL], policy: RenderPolicy = RenderPolicy(), watch: Bool = false) {
        self.init(layers: Self.untrustedLayers(for: roots), policy: policy, watch: watch)
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
    ///   - watch: Whether to watch every layer root and rebuild the catalog
    ///     on change (plan.md §7). Defaults to `false` -- a static catalog,
    ///     matching this initializer's prior behavior.
    public init(stack: DotfolderStack, policy: RenderPolicy = RenderPolicy(), watch: Bool = false) {
        self.init(layers: stack.layers, policy: policy, watch: watch)
    }

    /// Builds a `SkillsRegistry` from its already-resolved layers, shared by
    /// both public initializers so `init(roots:policy:watch:)`'s
    /// synthesized, uniformly untrusted layers and
    /// `init(stack:policy:watch:)`'s real, per-layer-trusted ones flow
    /// through exactly one construction path.
    ///
    /// - Parameters:
    ///   - layers: The layers to build the catalog over, lowest precedence
    ///     first.
    ///   - policy: The render policy every render call this registry makes
    ///     honors.
    ///   - watch: Whether to watch every layer root and rebuild the catalog
    ///     on change.
    private init(layers: [DotfolderStack.Layer], policy: RenderPolicy, watch: Bool) {
        roots = layers.map(\.root)
        self.policy = policy

        let built = Self.buildCatalog(layers: layers)
        catalogBox = CatalogBox(catalog: built.catalog, diagnostics: built.diagnostics)
        pipeline = RenderPipeline(
            argumentSubstitution: ArgumentSubstitution(), shellInjection: ShellInjection(),
            stencil: StencilPass(layers: layers))

        guard watch else {
            onReload = nil
            reloadCoordinator = nil
            return
        }

        let (stream, continuation) = AsyncStream<[SkillMetadata]>.makeStream()
        onReload = stream
        // A read-only view sharing this registry's own `catalogBox`, given
        // to `ReloadCoordinator` so it can recompute `metadata()` after
        // every rebuild through the exact same rendering path every other
        // reader uses, without duplicating any of it.
        let reader = SkillsRegistry(catalogBox: catalogBox, pipeline: pipeline, policy: policy, roots: roots)
        let coordinator = ReloadCoordinator(
            layers: layers, catalogBox: catalogBox, reader: reader, continuation: continuation)
        coordinator.start()
        reloadCoordinator = coordinator
    }

    /// Builds a read-only view of an existing registry's live catalog, with
    /// reload disabled -- `ReloadCoordinator`'s own vantage point for
    /// recomputing `metadata()` after a rebuild via the registry's real
    /// rendering path, rather than a duplicate of it.
    ///
    /// - Parameters:
    ///   - catalogBox: The catalog holder to share with the registry this
    ///     view was built from.
    ///   - pipeline: The render pipeline to share.
    ///   - policy: The render policy to share.
    ///   - roots: The layer roots to share.
    private init(catalogBox: CatalogBox, pipeline: RenderPipeline, policy: RenderPolicy, roots: [URL]) {
        self.roots = roots
        self.policy = policy
        self.catalogBox = catalogBox
        self.pipeline = pipeline
        onReload = nil
        reloadCoordinator = nil
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
            guard let validated = Self.validate(discovered: discovered, diagnostics: &diagnostics), !validated.isHidden else {
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
        discovered: DiscoveredSkill, diagnostics: inout [SkillDiagnostic]
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

    /// Builds a `RenderRequest` for `text` rendered under `entry`.
    ///
    /// Threads `entry.skillDirectory`/`entry.winningLayer` and this
    /// registry's own `policy` -- the fields every render call site shares
    /// -- so a call site only ever supplies what actually varies for it
    /// (`text`, and, where relevant, `arguments`/`argumentNames`).
    ///
    /// - Parameters:
    ///   - text: The text to render.
    ///   - entry: The catalog entry supplying `skillDirectory`/`winningLayer`.
    ///   - arguments: The arguments supplied at call time, in order.
    ///     Defaults to empty -- a `description`/`metadata.*` render carries
    ///     no per-call arguments.
    ///   - argumentNames: The skill's `arguments:` frontmatter names, in
    ///     declared order. Defaults to empty -- a `description`/`metadata.*`
    ///     render has no `$name` substitution target.
    /// - Returns: The assembled `RenderRequest`.
    private func renderRequest(
        text: String, entry: CatalogEntry, arguments: [String] = [], argumentNames: [String] = []
    ) -> RenderRequest {
        RenderRequest(
            text: text, arguments: arguments, argumentNames: argumentNames, skillDirectory: entry.skillDirectory,
            winningLayer: entry.winningLayer, policy: policy)
    }

    /// Renders `text` under `entry` through `render`, falling back to `text`
    /// unchanged if rendering fails.
    ///
    /// Shared by every render call site that is not declared `throws` --
    /// unlike `call(id:arguments:)`, which propagates a render failure
    /// instead of absorbing it -- so each of those call sites need only
    /// name which `RenderPipeline` method to render through and, where
    /// relevant, its `argumentNames`.
    ///
    /// - Parameters:
    ///   - text: The text to render.
    ///   - entry: The catalog entry `text` belongs to.
    ///   - argumentNames: The skill's `arguments:` frontmatter names, in
    ///     declared order. Defaults to empty.
    ///   - render: The `RenderPipeline` method to render `text` through.
    /// - Returns: The rendered text, or `text` unchanged on render failure.
    private func renderedFallback(
        text: String, entry: CatalogEntry, argumentNames: [String] = [],
        using render: (RenderRequest) throws -> String
    ) -> String {
        let request = renderRequest(text: text, entry: entry, argumentNames: argumentNames)
        return (try? render(request)) ?? text
    }

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
    private func renderedMetadataText(text: String, entry: CatalogEntry) -> String {
        renderedFallback(text: text, entry: entry, using: pipeline.renderMetadata)
    }

    /// Renders every entry in `entry.frontmatter.metadata` via
    /// `renderedMetadataValue(value:entry:)`, so a string scalar nested at
    /// any depth (e.g. an element of a `metadata.tags:` list) renders too,
    /// not just a top-level scalar.
    ///
    /// - Parameter entry: The catalog entry whose `metadata.*` entries to
    ///   render.
    /// - Returns: `entry.frontmatter.metadata` with every string scalar,
    ///   at any depth, rendered.
    private func renderedMetadataFields(entry: CatalogEntry) -> [String: FrontmatterValue] {
        entry.frontmatter.metadata.mapValues { renderedMetadataValue(value: $0, entry: entry) }
    }

    /// Renders one `FrontmatterValue`: a `.string` renders through
    /// `renderedMetadataText(text:entry:)`; `.array`/`.dictionary` recurse
    /// into every element/value; every other shape (bool, number, null)
    /// passes through unchanged, since only a string scalar is meaningful
    /// Stencil/`$`-substitution input.
    ///
    /// - Parameters:
    ///   - value: The value to render.
    ///   - entry: The catalog entry `value` belongs to.
    /// - Returns: `value` with every nested string scalar rendered.
    private func renderedMetadataValue(value: FrontmatterValue, entry: CatalogEntry) -> FrontmatterValue {
        switch value {
        case .string(let raw):
            return .string(renderedMetadataText(text: raw, entry: entry))
        case .array(let items):
            return .array(items.map { renderedMetadataValue(value: $0, entry: entry) })
        case .dictionary(let mapping):
            return .dictionary(mapping.mapValues { renderedMetadataValue(value: $0, entry: entry) })
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
    internal static func parameterSummary(parameter: SkillParameter) -> String {
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
                    description: renderedMetadataText(text: entry.frontmatter.description ?? "", entry: entry),
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
            listing.description = renderedMetadataText(text: description, entry: entry)
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
    /// `renderedMetadataText(text:entry:)` uses, since `preloadedBodies()`
    /// is not declared `throws` either.
    ///
    /// - Parameter entry: The catalog entry whose body to render.
    /// - Returns: The rendered body, or the unrendered body on render
    ///   failure.
    private func renderedBody(for entry: CatalogEntry) -> String {
        renderedFallback(
            text: entry.body, entry: entry, argumentNames: entry.frontmatter.arguments, using: pipeline.renderBody)
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
        // Read `catalogBox.snapshot` exactly once and reuse it for both the
        // lookup and `validIDs`, so a reload racing between two separate
        // reads can never make them internally inconsistent (an `id`
        // reported unknown that `validIDs` also lists as valid, or vice
        // versa).
        let snapshot = catalogBox.snapshot
        guard let entry = snapshot.catalog[id] else {
            throw UnknownSkillError(id: id, validIDs: snapshot.catalog.keys.sorted())
        }
        let request = renderRequest(
            text: entry.body, entry: entry, arguments: arguments, argumentNames: entry.frontmatter.arguments)
        return try pipeline.renderBody(request)
    }

    /// The unrendered body text of `id`'s current catalog entry.
    ///
    /// None of the §5 render passes have run on this text -- it is exactly
    /// the `SKILL.md` body as read from disk, `$`-argument placeholders,
    /// shell-injection syntax, and Stencil tags all still present verbatim.
    ///
    /// - Parameter id: The skill id to look up.
    /// - Returns: The raw body text, or `nil` when `id` is not currently in
    ///   the catalog.
    internal func rawBody(id: String) -> String? {
        catalogBox.snapshot.catalog[id]?.body
    }

    /// The absolute directory `id`'s current catalog entry lives in --
    /// where the resource operations (plan.md §7.3) enumerate and read
    /// under.
    ///
    /// - Parameter id: The skill id to look up.
    /// - Returns: The skill's directory, or `nil` when `id` is not
    ///   currently in the catalog.
    internal func skillDirectory(id: String) -> URL? {
        catalogBox.snapshot.catalog[id]?.skillDirectory
    }

    // MARK: - Reload (plan.md §7)

    /// The atomically-swappable holder for one catalog generation and its
    /// diagnostics, shared by every copy of a `SkillsRegistry`.
    ///
    /// `@unchecked Sendable`: both stored properties are only ever read or
    /// replaced while holding `lock`, and `snapshot`/`replace(catalog:diagnostics:)`
    /// are its only access points -- no caller ever reaches `catalog` or
    /// `diagnostics` without going through the lock.
    private final class CatalogBox: @unchecked Sendable {
        private let lock = NSLock()
        private var catalog: [String: CatalogEntry]
        private var diagnostics: [SkillDiagnostic]

        /// Creates a `CatalogBox` holding one initial catalog generation.
        ///
        /// - Parameters:
        ///   - catalog: The initial catalog, keyed by id.
        ///   - diagnostics: The initial catalog's diagnostics.
        init(catalog: [String: CatalogEntry], diagnostics: [SkillDiagnostic]) {
            self.catalog = catalog
            self.diagnostics = diagnostics
        }

        /// The current catalog and its diagnostics, read together
        /// atomically so a caller can never observe one paired with the
        /// other's prior or next generation.
        var snapshot: (catalog: [String: CatalogEntry], diagnostics: [SkillDiagnostic]) {
            withLock { (catalog, diagnostics) }
        }

        /// Atomically replaces both the catalog and its diagnostics with a
        /// freshly-rebuilt generation.
        ///
        /// - Parameters:
        ///   - catalog: The rebuilt catalog, keyed by id.
        ///   - diagnostics: The rebuilt catalog's diagnostics.
        func replace(catalog: [String: CatalogEntry], diagnostics: [SkillDiagnostic]) {
            withLock {
                self.catalog = catalog
                self.diagnostics = diagnostics
            }
        }

        /// Runs `body` while holding `lock`, releasing it via `defer` before
        /// returning under any control-flow path, so `snapshot` and
        /// `replace(catalog:diagnostics:)` share one lock-acquire/release
        /// point instead of each repeating `lock()`/`defer { unlock() }`
        /// verbatim.
        ///
        /// - Parameter body: The work to run under the lock.
        /// - Returns: `body`'s result.
        private func withLock<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }
    }

    /// Owns the `SkillWatcher` and `onReload` continuation for a `watch:
    /// true` registry: rebuilds `catalogBox` on every coalesced watcher
    /// signal and publishes the refreshed metadata list.
    ///
    /// A `final class` rather than a value type since its lifetime -- when
    /// the watcher starts and, more importantly, when it stops -- is what
    /// `SkillsRegistry` needs to own; a struct has no `deinit` to hang that
    /// stop on.
    ///
    /// `@unchecked Sendable`: both stored properties (`watcher`,
    /// `continuation`) are immutable `let`s referring to types that are
    /// themselves safe under concurrent use -- `SkillWatcher` is
    /// `@unchecked Sendable` and serializes its own mutable state on a
    /// private queue, and `AsyncStream.Continuation` is documented safe to
    /// call from multiple threads concurrently. This class itself declares
    /// no other stored state: the watcher's `onChange` closure wired up in
    /// `init` captures `layers`/`catalogBox`/`reader`/`continuation`
    /// directly rather than `self`, so no `ReloadCoordinator` instance
    /// property is ever read or written outside of `init`/`start()`/`deinit`,
    /// none of which race with each other (`start()` and `deinit` are only
    /// ever called from the owning `SkillsRegistry`'s single construction
    /// and deinitialization points).
    private final class ReloadCoordinator: @unchecked Sendable {
        private let watcher: SkillWatcher
        private let continuation: AsyncStream<[SkillMetadata]>.Continuation

        /// Creates a `ReloadCoordinator` and wires (but does not yet start)
        /// its watcher.
        ///
        /// The watcher's `onChange` closure captures `layers`, `catalogBox`,
        /// `reader`, and `continuation` directly rather than `self`, so
        /// wiring it up here creates no retain cycle between this
        /// coordinator and its own watcher.
        ///
        /// - Parameters:
        ///   - layers: The layer roots to watch and to rebuild the catalog
        ///     from on every coalesced signal.
        ///   - catalogBox: The catalog holder to atomically replace on
        ///     every rebuild.
        ///   - reader: A read-only registry view sharing `catalogBox`, used
        ///     to recompute `metadata()` after each rebuild via the real
        ///     rendering path.
        ///   - continuation: The `onReload` continuation to publish the
        ///     refreshed metadata list to after every rebuild.
        init(
            layers: [DotfolderStack.Layer], catalogBox: CatalogBox, reader: SkillsRegistry,
            continuation: AsyncStream<[SkillMetadata]>.Continuation
        ) {
            self.continuation = continuation
            watcher = SkillWatcher(roots: layers.map(\.root)) {
                let rebuilt = SkillsRegistry.buildCatalog(layers: layers)
                catalogBox.replace(catalog: rebuilt.catalog, diagnostics: rebuilt.diagnostics)
                continuation.yield(reader.metadata())
            }
        }

        /// Starts the underlying watcher.
        func start() {
            watcher.start()
        }

        /// Stops the underlying watcher and finishes `onReload`, so no
        /// further rebuilds or publications happen once every copy of the
        /// owning registry has gone out of scope.
        deinit {
            watcher.stop()
            continuation.finish()
        }
    }
}
