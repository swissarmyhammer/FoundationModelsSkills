import Foundation
import FoundationModelsExtras
import Tracing

/// One catalog row `SkillsRegistry.metadata()` returns: a skill's id, its
/// rendered description and `metadata.*` values, parameter placeholder
/// summaries, and whether it is currently eligible for the model-facing
/// surface (plan.md §6, §7.1).
///
/// Seeds `SkillSearchAgent`'s `MetadataSearcher<SkillMetadata>` --
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
    /// `"[env]"` (the placeholder shape of plan.md §6.1).
    public var parameters: [String]

    /// Whether this skill is currently eligible for the model-facing
    /// surface: `search skill`/`list skill`/`use skill` (plan.md §6).
    public var isModelVisible: Bool

    /// The marketplace this skill came from, for example
    /// `swissarmyhammer-skills@1.2.0`, or `nil` for a local skill
    /// (marketplace.md §9.1).
    ///
    /// Display only, for a host that reads `SkillsRegistry.metadata()`. The
    /// model-facing `list skill` and `search skill` lines do not show it. It
    /// stays out of `renderBlock()`, thus a marketplace name can never
    /// change how a search ranks a skill.
    public var source: String?

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
    ///   - source: The marketplace this skill came from. Defaults to `nil`,
    ///     a local skill.
    public init(
        id: String, description: String, metadata: [String: FrontmatterValue] = [:],
        parameters: [String] = [], isModelVisible: Bool, source: String? = nil
    ) {
        self.id = id
        self.description = description
        self.metadata = metadata
        self.parameters = parameters
        self.isModelVisible = isModelVisible
        self.source = source
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
    /// realized generically here -- the model-facing operations in
    /// `Operations/` convert this into their own corrective text).
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
/// the same contract `SkillDiscovery` and `DotfolderWatcher` already follow
/// (decision #29, amended). A skill `SkillValidator` hides entirely (the
/// retired `partial: true` flag) never enters the catalog at all -- every
/// method below only ever sees the skills that survived validation
/// un-hidden.
///
/// With `watch: false` (the default), the catalog never changes after
/// `init` returns. With `watch: true`, a `DotfolderWatcher` of
/// `FoundationModelsExtras` observes every layer root and rebuilds the
/// catalog on its coalesced signal; the rebuild swaps in a whole new
/// catalog atomically, so `metadata()`,
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
    ///
    /// A construction-time invariant (plan.md decisions #25/#28): fixed for
    /// this registry's lifetime, so no holder can silently repoint it at a
    /// different set of roots after the catalog and every render pass
    /// (`StencilPass`'s partials stack) have already captured it.
    public let roots: [URL]

    /// The render policy every render call this registry makes honors
    /// (plan.md decisions #25/#28).
    ///
    /// A construction-time invariant: fixed for this registry's lifetime, so
    /// a script/shell-disabled registry can never be re-enabled by a holder
    /// after construction.
    public let policy: RenderPolicy

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

    /// A fresh subscription to this registry's refreshed metadata list, one
    /// publication per watcher-driven rebuild (plan.md §7's reload seam,
    /// §7.1's "one registry, four simultaneous consumers"; `commandUpdates`
    /// is another).
    ///
    /// Each access registers an independent subscriber stream against the
    /// shared `ReloadCoordinator`, so any number of concurrent readers --
    /// this property accessed twice, or alongside `commandUpdates` -- each
    /// observe every publication in full; none steals another's elements.
    /// Each element is the full, current `metadata()` list -- not an
    /// incremental diff, the same full-catalog contract `metadata()` itself
    /// carries. `nil` when this registry was constructed with `watch:
    /// false` and no marketplace provider, since a registry that never
    /// reloads has nothing to publish; a marketplace-backed registry
    /// publishes on every provider update, thus `onReload` is never `nil`
    /// for `init(marketplaces:stack:policy:watch:)`, whatever `watch` is
    /// (marketplace.md §7.4). Every subscription finishes once this
    /// registry (and every copy sharing its coordinator) is deinitialized.
    public var onReload: AsyncStream<[SkillMetadata]>? {
        reloadCoordinator?.subscribe()
    }

    /// This registry's render pipeline, wired to the real passes 1-3.
    private let pipeline: RenderPipeline

    /// The atomically-swappable holder for this registry's current catalog
    /// generation and its diagnostics.
    ///
    /// Every copy of a given `SkillsRegistry` shares the same `CatalogBox`
    /// instance, so a rebuild triggered through one copy's watcher is
    /// immediately visible to every other copy.
    private let catalogBox: CatalogBox

    /// Owns the `DotfolderWatcher` and the `onReload` continuation for a
    /// `watch: true` registry; `nil` for `watch: false`.
    ///
    /// Retained purely for its lifetime: `ReloadCoordinator.deinit` stops
    /// the watcher and finishes `onReload`, so keeping this field alive for
    /// as long as any copy of the registry exists is what makes the
    /// watcher's lifecycle "owned by the registry" a real guarantee rather
    /// than a comment.
    private let reloadCoordinator: ReloadCoordinator?

    /// The tracer, the metrics factory and the logger of each catalog load
    /// and each skill load.
    ///
    /// A catalog load (the build at construction and the rebuild of each hot
    /// reload) opens one ``SkillsTracing/SpanName/catalogLoad`` span and
    /// records one ``SkillsTracing/MetricName/skillsLoaded`` value. A skill
    /// load (`call(id:arguments:)`) opens one
    /// ``SkillsTracing/SpanName/skillLoad`` span and writes one "enter"
    /// record. Every public initializer gives the default telemetry, which
    /// reads the bootstrapped tracer, the factory of the current task and a
    /// new logger of the label `SkillsTracing.LoggerLabel.registry` when a
    /// load starts. A test gives explicit values through
    /// `init(layers:policy:watch:telemetry:)`.
    private let telemetry: SkillsTracing.Telemetry

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

    /// Creates a `SkillsRegistry` over explicitly trust-labeled layers,
    /// building its catalog once, immediately.
    ///
    /// The general constructor `init(roots:policy:watch:)` and
    /// `init(stack:policy:watch:)` both funnel through: a host that wants a
    /// bare-`[URL]` root labeled `.defaults` (so its skills render Stencil-
    /// trusted, plan.md decision #29) without going through a full
    /// `DotfolderStack` builds its own `[DotfolderStack.Layer]` and calls
    /// this initializer directly -- the one sanctioned way to influence
    /// `StencilPass`'s trust mapping; there is no separate override
    /// mechanism.
    ///
    /// - Parameters:
    ///   - layers: The layers to build the catalog over, lowest precedence
    ///     first; a later layer's copy of an id fully replaces an earlier
    ///     layer's copy of the same id.
    ///   - policy: The render policy every render call this registry makes
    ///     honors. Defaults to the permissive `RenderPolicy()`.
    ///   - watch: Whether to watch every layer root and rebuild the catalog
    ///     on change (plan.md §7). Defaults to `false` -- a static catalog.
    public init(layers: [DotfolderStack.Layer], policy: RenderPolicy = RenderPolicy(), watch: Bool = false) {
        self.init(layers: layers, policy: policy, watch: watch, telemetry: SkillsTracing.Telemetry())
    }

    /// Creates a `SkillsRegistry` over explicitly trust-labeled layers, with
    /// explicit telemetry.
    ///
    /// `init(layers:policy:watch:)` calls this one with the default
    /// telemetry. A test gives its own tracer, metrics factory or logger, and
    /// reads the records back. The rebuild of a hot reload runs on the queue
    /// of the watcher, where no task-local tracer or factory reaches, thus a
    /// test of a reload gives them here.
    ///
    /// - Parameters:
    ///   - layers: The layers to build the catalog over, lowest precedence
    ///     first.
    ///   - policy: The render policy every render call this registry makes
    ///     honors.
    ///   - watch: Whether to watch every layer root and rebuild the catalog
    ///     on change.
    ///   - telemetry: The tracer, the metrics factory and the logger of each
    ///     catalog load and each skill load.
    init(layers: [DotfolderStack.Layer], policy: RenderPolicy, watch: Bool, telemetry: SkillsTracing.Telemetry) {
        self.init(
            source: LayerSource(plan: { LayerPlan(localLayers: layers) }, marketplaceUpdates: nil),
            policy: policy, watch: watch, telemetry: telemetry)
    }

    /// Creates a `SkillsRegistry` over a marketplace provider's layers in
    /// front of a `DotfolderStack`'s own layers, building its catalog once,
    /// immediately (marketplace.md §4.1, §4.2, §7.4).
    ///
    /// The layer order is `url[0] < … < url[n] < defaults < user <
    /// project`: a local skill always wins over a marketplace copy of the
    /// same id, and the last marketplace wins among themselves.
    ///
    /// The registry stays a pure disk reader: it reads only what the
    /// provider already materialized, and it never waits on the network. A
    /// marketplace layer root is the stable `<cache>/<id>/current` path,
    /// and a swap of that path sends no reliable file-system event, thus
    /// each value of `marketplaces.layerUpdates` -- not the watcher -- asks
    /// the provider for its layers again (the commit and the catalog
    /// version change) and then runs exactly the rebuild the watcher runs:
    /// one atomic catalog swap and one `onReload` publication, also when
    /// `watch` is `false`. Thus `onReload` is never `nil` here.
    ///
    /// - Parameters:
    ///   - marketplaces: The provider of the marketplace layers.
    ///   - stack: The dotfolder stack whose layers sit above them.
    ///   - policy: The render policy every render call this registry makes
    ///     honors. Defaults to the permissive `RenderPolicy()`.
    ///   - watch: Whether to watch every local layer root, and the root of
    ///     each marketplace layer that a folder on this computer backs, and
    ///     rebuild the catalog on change (plan.md §7, marketplace.md §7.4).
    ///     Defaults to `false`; a provider update still rebuilds, and a
    ///     cache-backed marketplace root rebuilds on that update only.
    public init(
        marketplaces: some MarketplaceLayerProviding, stack: DotfolderStack,
        policy: RenderPolicy = RenderPolicy(), watch: Bool = false
    ) {
        let localLayers = stack.layers
        self.init(
            source: LayerSource(
                plan: {
                    LayerPlan(
                        marketplaceLayers: marketplaces.marketplaceLayers(), localLayers: localLayers)
                },
                marketplaceUpdates: marketplaces.layerUpdates),
            policy: policy, watch: watch, telemetry: SkillsTracing.Telemetry())
    }

    /// Creates a `SkillsRegistry` over whatever computes its layers,
    /// building its catalog once, immediately -- the one designated
    /// initializer every other one funnels through.
    ///
    /// `roots` and the render pipeline are construction-time invariants
    /// (plan.md decisions #25/#28), thus they come from the first plan and
    /// never move; a later rebuild changes only the catalog and its
    /// diagnostics.
    ///
    /// - Parameters:
    ///   - source: How to compute the layers of each catalog generation,
    ///     and what makes them change.
    ///   - policy: The render policy every render call this registry makes
    ///     honors.
    ///   - watch: Whether to watch every layer root and rebuild the catalog
    ///     on change.
    ///   - telemetry: The tracer, the metrics factory and the logger of each
    ///     catalog load and each skill load.
    private init(source: LayerSource, policy: RenderPolicy, watch: Bool, telemetry: SkillsTracing.Telemetry) {
        let plan = source.plan()
        roots = plan.layers.map(\.root)
        self.policy = policy
        self.telemetry = telemetry

        let built = Self.loadCatalog(plan: plan, telemetry: telemetry)
        catalogBox = CatalogBox(catalog: built.catalog, diagnostics: built.diagnostics)
        // The stenciled stack of Extras keeps the process environment out of
        // its own ladder, thus this registry reads the environment one time,
        // here, and pass 3 interpolates it below the named arguments of a
        // skill. One read also keeps every render of one registry on one set
        // of values.
        pipeline = RenderPipeline(
            argumentSubstitution: ArgumentSubstitution(), shellInjection: ShellInjection(),
            stencil: StencilPass(layers: plan.layers, environment: ProcessInfo.processInfo.environment))

        guard watch || source.marketplaceUpdates != nil else {
            reloadCoordinator = nil
            return
        }

        // A read-only view sharing this registry's own `catalogBox`, given
        // to `ReloadCoordinator` so it can recompute `metadata()` after
        // every rebuild through the exact same rendering path every other
        // reader uses, without duplicating any of it.
        let reader = SkillsRegistry(
            catalogBox: catalogBox, pipeline: pipeline, policy: policy, roots: roots, telemetry: telemetry)
        let coordinator = ReloadCoordinator(
            source: source, watchedRoots: watch ? plan.watchedRoots : nil, catalogBox: catalogBox,
            reader: reader, telemetry: telemetry)
        coordinator.start()
        reloadCoordinator = coordinator
    }

    /// The ordered layers of one catalog generation, and which marketplace
    /// each of them came from.
    private struct LayerPlan: Sendable {
        /// The layers, lowest precedence first.
        let layers: [DotfolderStack.Layer]
        /// Which marketplace each entry of `layers` came from.
        let marketplaces: MarketplaceProvenanceIndex

        /// The roots that a `watch: true` registry watches: every local root,
        /// and the root of each marketplace layer that a folder on this
        /// computer backs (marketplace.md §7.4).
        ///
        /// A cache-backed marketplace root is not here: its snapshot swap
        /// sends no reliable file-system event, thus it rebuilds on a value of
        /// `LayerSource.marketplaceUpdates` instead.
        let watchedRoots: [URL]

        /// Creates a plan of local layers only, which names no marketplace.
        ///
        /// - Parameter localLayers: The layers, lowest precedence first.
        init(localLayers: [DotfolderStack.Layer]) {
            layers = localLayers
            marketplaces = MarketplaceProvenanceIndex()
            watchedRoots = localLayers.map(\.root)
        }

        /// Creates a plan of marketplace layers in front of local layers
        /// (marketplace.md §4.1).
        ///
        /// - Parameters:
        ///   - marketplaceLayers: The marketplace layers, lowest precedence
        ///     first; they all sit below `localLayers`.
        ///   - localLayers: The local layers, lowest precedence first.
        init(marketplaceLayers: [MarketplaceLayer], localLayers: [DotfolderStack.Layer]) {
            layers = marketplaceLayers.map(\.layer) + localLayers
            let named: [MarketplaceProvenanceIndex.Entry?] = marketplaceLayers.map {
                MarketplaceProvenanceIndex.Entry(provenance: $0.provenance)
            }
            let unnamed: [MarketplaceProvenanceIndex.Entry?] = localLayers.map { _ in nil }
            marketplaces = MarketplaceProvenanceIndex(byLayerIndex: named + unnamed)
            watchedRoots =
                marketplaceLayers.filter(\.isWatchable).map(\.layer.root) + localLayers.map(\.root)
        }

        /// The layer directories that give the files of `discovered`,
        /// lowest precedence first, each with the layer that gives it.
        ///
        /// Discovery names the layer of each contributing directory by its
        /// index in the layer list it ran over, which is this plan's own
        /// `layers`. An index this plan does not hold is dropped rather
        /// than trapped: the plan is recomputed for every rebuild, so a
        /// stale record must cost one directory and never the whole
        /// catalog.
        ///
        /// - Parameter discovered: The discovery record of one skill.
        /// - Returns: One entry per contributing directory, in the order
        ///   discovery gives them.
        func contributingDirectories(for discovered: DiscoveredSkill) -> [ContributingDirectory] {
            discovered.contributingDirectories.compactMap { contributing in
                guard layers.indices.contains(contributing.rootIndex) else { return nil }
                return ContributingDirectory(
                    directory: contributing.skillDirectory, layer: layers[contributing.rootIndex])
            }
        }

    }

    /// How one registry computes the layers of each catalog generation, and
    /// what makes them change.
    private struct LayerSource: Sendable {
        /// Computes the layers of the next catalog generation. Called once
        /// at construction, and again for every rebuild, because a
        /// marketplace's commit and catalog version change between calls.
        let plan: @Sendable () -> LayerPlan

        /// One value for each marketplace update, or `nil` when no provider
        /// backs this registry.
        let marketplaceUpdates: AsyncStream<Void>?
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
    ///   - telemetry: The telemetry to share.
    private init(
        catalogBox: CatalogBox, pipeline: RenderPipeline, policy: RenderPolicy, roots: [URL],
        telemetry: SkillsTracing.Telemetry
    ) {
        self.roots = roots
        self.policy = policy
        self.catalogBox = catalogBox
        self.pipeline = pipeline
        self.telemetry = telemetry
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

    /// One layer directory that gives files of a skill, with the layer that
    /// gives that directory.
    ///
    /// The unit of override is the file, thus a skill of the combined view
    /// has one of these for each layer that holds a directory of its id.
    /// A directory here gives every file that no higher layer holds, even
    /// when the winning `SKILL.md` is in another layer -- which is why the
    /// layer of each directory is here, and not the layer of `SKILL.md`
    /// alone.
    internal struct ContributingDirectory: Sendable {
        /// The layer directory itself, the directory of the skill's id
        /// under `layer.root`.
        internal let directory: URL

        /// The layer that gives `directory`. A resource operation reads its
        /// source to say which layer a file comes from.
        internal let layer: DotfolderStack.Layer
    }

    /// One skill that survived validation un-hidden, with everything a
    /// render call or a listing/metadata row needs.
    private struct CatalogEntry: Sendable {
        let id: String
        let frontmatter: SkillFrontmatter
        let body: String
        let skillDirectory: URL
        let winningLayer: DotfolderStack.Layer
        /// Every layer directory of this skill, lowest precedence first,
        /// each with the layer that gives it.
        ///
        /// `skillDirectory` and `winningLayer` name the one directory that
        /// gives `SKILL.md`; this list names each directory that gives any
        /// file at all, that one included.
        let contributingDirectories: [ContributingDirectory]
        /// The marketplace `winningLayer` came from, or `nil` for a local
        /// skill (marketplace.md §9.1).
        let marketplace: MarketplaceProvenance?
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
        ///   - contributingDirectories: Every layer directory of this
        ///     skill, lowest precedence first, each with the layer that
        ///     gives it.
        ///   - marketplace: The marketplace that layer came from, or `nil`
        ///     for a local skill.
        init(
            validated: ValidatedSkill, discovered: DiscoveredSkill, winningLayer: DotfolderStack.Layer,
            contributingDirectories: [ContributingDirectory], marketplace: MarketplaceProvenance?
        ) {
            id = validated.id
            frontmatter = validated.frontmatter
            body = validated.body
            skillDirectory = discovered.skillDirectory
            self.winningLayer = winningLayer
            self.contributingDirectories = contributingDirectories
            self.marketplace = marketplace

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

    /// Builds one catalog generation in one
    /// ``SkillsTracing/SpanName/catalogLoad`` span, and records its size.
    ///
    /// The construction of a registry and the rebuild of each hot reload
    /// both come here, thus each build gives one span and one
    /// ``SkillsTracing/MetricName/skillsLoaded`` value. The span holds the
    /// number of skills and the number of diagnostics. A build reads files
    /// and runs no shell command or model, thus it writes no "enter" record.
    ///
    /// - Parameters:
    ///   - plan: The layers to build the catalog over, lowest precedence
    ///     first, and the marketplace each of them came from.
    ///   - telemetry: The tracer and the metrics factory of the build.
    /// - Returns: The same value as ``buildCatalog(plan:)``.
    private static func loadCatalog(
        plan: LayerPlan, telemetry: SkillsTracing.Telemetry
    ) -> (catalog: [String: CatalogEntry], diagnostics: [SkillDiagnostic]) {
        telemetry.tracer.withSpan(SkillsTracing.SpanName.catalogLoad) { span in
            let built = buildCatalog(plan: plan)
            span.attributes[SkillsTracing.AttributeKey.skillCount] = built.catalog.count
            span.attributes[SkillsTracing.AttributeKey.diagnosticCount] = built.diagnostics.count
            telemetry.recordSkillsLoaded(built.catalog.count)
            return built
        }
    }

    /// Discovers, decodes, and validates every skill across `layers`'
    /// roots, folding the un-hidden survivors into a catalog keyed by id.
    ///
    /// - Parameter plan: The layers to build the catalog over, lowest
    ///   precedence first, and the marketplace each of them came from.
    /// - Returns: The catalog, keyed by id, plus every diagnostic raised
    ///   while validating (including for skills excluded from the
    ///   catalog).
    private static func buildCatalog(
        plan: LayerPlan
    ) -> (catalog: [String: CatalogEntry], diagnostics: [SkillDiagnostic]) {
        var catalog: [String: CatalogEntry] = [:]
        var diagnostics: [SkillDiagnostic] = []
        let documents = Self.skillDocuments(layers: plan.layers)

        for discovered in SkillDiscovery(layers: plan.layers).discover() {
            let validation = Self.validate(
                discovered: discovered, document: documents[discovered.id]?.value,
                marketplaces: plan.marketplaces, diagnostics: &diagnostics)
            guard let validated = validation, !validated.isHidden else {
                continue
            }
            diagnostics.append(
                contentsOf: Self.inferenceDiagnostics(
                    validated: validated, discovered: discovered, marketplaces: plan.marketplaces))
            catalog[discovered.id] = CatalogEntry(
                validated: validated, discovered: discovered,
                winningLayer: plan.layers[discovered.rootIndex],
                contributingDirectories: plan.contributingDirectories(for: discovered),
                marketplace: plan.marketplaces.provenance(atLayerIndex: discovered.rootIndex))
        }

        return (catalog, diagnostics)
    }

    /// Runs `ParameterInference` over `validated` and converts every
    /// resulting source-mismatch note (e.g. `arguments:`/`argument-hint:`
    /// arity disagreement) into a `SkillDiagnostic`, carrying `discovered`'s
    /// winning-root provenance (plan.md §6.1: "Diagnostics flag mismatches
    /// between sources").
    ///
    /// - Parameters:
    ///   - validated: The validated skill to infer parameters for.
    ///   - discovered: Its discovery record, for provenance.
    ///   - marketplaces: Which marketplace each layer came from, so the
    ///     provenance names it (marketplace.md §9.1).
    /// - Returns: One advisory `SkillDiagnostic` per inference note; empty
    ///   when the sources agree.
    private static func inferenceDiagnostics(
        validated: ValidatedSkill, discovered: DiscoveredSkill, marketplaces: MarketplaceProvenanceIndex
    ) -> [SkillDiagnostic] {
        let provenance = SkillDiagnostic.Provenance(
            discovered: discovered, marketplace: marketplaces.provenance(atLayerIndex: discovered.rootIndex))
        return ParameterInference.infer(frontmatter: validated.frontmatter, body: validated.body).diagnostics
            .map { message in
                SkillDiagnostic(
                    severity: .advisory, skillID: validated.id, provenance: provenance, message: message)
            }
    }

    /// The text of every skill that this package reads: one document per
    /// skill id, already split into its frontmatter and its body.
    ///
    /// `DotfolderStack` does each read, `FrontmatterDocumentStack` does each
    /// split, and `FrontmatterDecoder` does the decode of the frontmatter,
    /// which is the schema work of this package. Thus this registry opens no
    /// file of its own.
    ///
    /// The document stack sits over the plain stack, not over a stenciled
    /// one: the split runs on the raw text, because this registry renders the
    /// body and each `metadata.*` value later, with the arguments of the
    /// call.
    ///
    /// - Parameter layers: The layers of one catalog generation, lowest
    ///   precedence first.
    /// - Returns: The winning `SKILL.md` of each child directory of the
    ///   union of the layer roots. An id whose winning `SKILL.md` no layer
    ///   can read, or that is not UTF-8 text, has no entry.
    private static func skillDocuments(
        layers: [DotfolderStack.Layer]
    ) -> [String: Located<FrontmatterDocument<FrontmatterDecoder.MetadataOutcome>>] {
        FrontmatterDocumentStack(
            base: DotfolderStack(layers: layers),
            decode: { FrontmatterDecoder.decode(frontmatter: $0) }
        ).items(in: nil, named: SkillDiscovery.skillFileName)
    }

    /// Runs `discovered`'s already-split `SKILL.md` through `SkillValidator`,
    /// appending every diagnostic raised to `diagnostics`.
    ///
    /// Discovery lists a skill from the locations of its `SKILL.md`, and it
    /// reads no file. The document stack gives no entry for a copy it cannot
    /// read as UTF-8 text, thus `document` is `nil` exactly for such a skill,
    /// and that skill gets the `.skip` diagnostic below.
    ///
    /// - Parameters:
    ///   - discovered: The skill's discovery record.
    ///   - document: The winning `SKILL.md` of this id, or `nil` when the
    ///     stack could not read it.
    ///   - marketplaces: Which marketplace each layer came from, so every
    ///     diagnostic names it (marketplace.md §9.1).
    ///   - diagnostics: Accumulates every diagnostic raised.
    /// - Returns: The validated skill, or `nil` for unparseable YAML
    ///   (`SkillValidator`'s own `.skipped` outcome) or an unreadable
    ///   `SKILL.md`.
    private static func validate(
        discovered: DiscoveredSkill,
        document: FrontmatterDocument<FrontmatterDecoder.MetadataOutcome>?,
        marketplaces: MarketplaceProvenanceIndex, diagnostics: inout [SkillDiagnostic]
    ) -> ValidatedSkill? {
        guard let document else {
            diagnostics.append(
                SkillDiagnostic(
                    severity: .skip, skillID: discovered.id,
                    provenance: SkillDiagnostic.Provenance(
                        discovered: discovered,
                        marketplace: marketplaces.provenance(atLayerIndex: discovered.rootIndex)),
                    message: Self.unreadableSkillFileMessage))
            return nil
        }
        let result = SkillValidator.validate(
            discovered: discovered,
            outcome: FrontmatterDecoder.Outcome(metadata: document.metadata, body: document.content),
            marketplaces: marketplaces)
        diagnostics.append(contentsOf: result.diagnostics)
        return result.skill
    }

    /// The text of the `.skip` diagnostic for a discovered skill whose
    /// winning `SKILL.md` the stack cannot read.
    private static let unreadableSkillFileMessage = "SKILL.md could not be read"

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
        let request = renderRequest(text: text, entry: entry)
        return (try? pipeline.renderMetadata(request)) ?? text
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

    /// Infers `entry`'s structured parameters (plan.md §6.1).
    ///
    /// - Parameter entry: The catalog entry to infer parameters for.
    /// - Returns: One `SkillParameter` per inferred parameter, in position
    ///   order.
    private func parameters(entry: CatalogEntry) -> [SkillParameter] {
        ParameterInference.infer(frontmatter: entry.frontmatter, body: entry.body).parameters
    }

    /// Summarizes one parameter as a display placeholder: its own
    /// `argument-hint:` token text when it has one, otherwise the
    /// synthesized `[name]`.
    ///
    /// A skill demands no argument, thus the synthesized form is always the
    /// bracketed one. A hint token is shown as written.
    ///
    /// - Parameter parameter: The parameter to summarize.
    /// - Returns: The placeholder summary text.
    internal static func parameterSummary(parameter: SkillParameter) -> String {
        parameter.placeholder ?? "[\(parameter.name)]"
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
                let entryParameters = parameters(entry: entry)
                return SkillMetadata(
                    id: entry.id,
                    description: renderedMetadataText(text: entry.frontmatter.description ?? "", entry: entry),
                    metadata: renderedMetadataFields(entry: entry),
                    parameters: entryParameters.map(Self.parameterSummary),
                    isModelVisible: entry.isModelVisible,
                    source: entry.marketplace?.displayText)
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
    /// rendered and truncated for the menu.
    ///
    /// - Parameter entry: The catalog entry to build a row for.
    /// - Returns: The row, `description` rendered and menu-truncated when
    ///   present, and `source` naming the marketplace the skill came from.
    private func listing(for entry: CatalogEntry) -> SkillListing {
        var listing = SkillListing(id: entry.id, frontmatter: entry.frontmatter, body: entry.body)
        listing.source = entry.marketplace?.displayText
        if let description = entry.frontmatter.description {
            listing.description = Self.truncatedForMenu(renderedMetadataText(text: description, entry: entry))
        }
        return listing
    }

    /// The maximum `description` length `commandListing()` shows in the
    /// user `/` menu (plan.md §6.1: "rendered, truncated for the menu").
    /// `metadata()` renders the same description full-length -- this cap
    /// applies only to the menu surface and to the shortened step of the
    /// `skills` tool description (`SkillsToolDescription`).
    private static let menuDescriptionMaxLength = 200

    /// Truncates `text` to at most `menuDescriptionMaxLength` characters,
    /// breaking on the last word boundary at or before the limit where one
    /// exists and appending an ellipsis.
    ///
    /// The `/` menu and the shortened step of `SkillsToolDescription` both
    /// use this one function, thus the two surfaces shorten a description in
    /// the same way.
    ///
    /// - Parameter text: The rendered description to truncate.
    /// - Returns: `text` unchanged when it already fits within the limit;
    ///   otherwise the truncated, ellipsis-suffixed text.
    internal static func truncatedForMenu(_ text: String) -> String {
        guard text.count > menuDescriptionMaxLength else { return text }
        let limit = text.index(text.startIndex, offsetBy: menuDescriptionMaxLength)
        let breakIndex = text[..<limit].lastIndex(of: " ") ?? limit
        return text[..<breakIndex].trimmingCharacters(in: .whitespaces) + "…"
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
    public func preloadedBodies() async -> String {
        var bodies: [String] = []
        for entry in sortedCatalogEntries(where: \.isPreloaded) {
            bodies.append(await renderedBody(for: entry))
        }
        return bodies.joined(separator: "\n\n")
    }

    /// Renders `entry`'s body through all three §5 passes, falling back to
    /// the unrendered body if rendering fails -- the same lenient posture
    /// `renderedMetadataText(text:entry:)` uses, since `preloadedBodies()`
    /// is not declared `throws` either.
    ///
    /// - Parameter entry: The catalog entry whose body to render.
    /// - Returns: The rendered body, or the unrendered body on render
    ///   failure.
    private func renderedBody(for entry: CatalogEntry) async -> String {
        let request = renderRequest(text: entry.body, entry: entry, argumentNames: entry.frontmatter.arguments)
        return (try? await pipeline.renderBody(request)) ?? entry.body
    }

    // MARK: - call(id:arguments:)

    /// Dereferences the catalog by `id` and renders that skill's body
    /// through all three §5 passes with `arguments`.
    ///
    /// The call runs in one ``SkillsTracing/SpanName/skillLoad`` span that
    /// holds the skill id, and never the arguments or the rendered body. The
    /// shell pass can wait for a long time, thus the span also writes one
    /// "enter" record when the call starts (`TracedCall`). A thrown error gives
    /// the span the error status and the type name of the error, and never
    /// its description.
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
    public func call(id: String, arguments: [String] = []) async throws -> String {
        try await TracedCall.run(
            SkillsTracing.SpanName.skillLoad, tracer: telemetry.tracer,
            logger: telemetry.logger(label: SkillsTracing.LoggerLabel.registry),
            attributes: { $0[SkillsTracing.AttributeKey.skillID] = id }
        ) { _ in
            try await renderedCall(id: id, arguments: arguments)
        }
    }

    /// Renders the body of the skill `id` with `arguments`: the work of
    /// `call(id:arguments:)` in its span.
    ///
    /// - Parameters:
    ///   - id: The skill id to call.
    ///   - arguments: The arguments to substitute into the rendered body.
    /// - Returns: The fully rendered body.
    /// - Throws: The same errors as `call(id:arguments:)`.
    private func renderedCall(id: String, arguments: [String]) async throws -> String {
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
        return try await pipeline.renderBody(request)
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

    /// Every layer directory of `id`'s current catalog entry, lowest
    /// precedence first, each with the layer that gives it.
    ///
    /// The unit of override is the file, so a resource operation reads
    /// these directories from the highest down and takes the first copy of
    /// a file it finds. `skillDirectory(id:)` names one of them -- the one
    /// that gives `SKILL.md`.
    ///
    /// - Parameter id: The skill id to look up.
    /// - Returns: The contributing directories, or an empty list when `id`
    ///   is not currently in the catalog.
    internal func contributingDirectories(id: String) -> [ContributingDirectory] {
        catalogBox.snapshot.catalog[id]?.contributingDirectories ?? []
    }

    /// `id`'s current catalog entry's tokenized `allowed-tools:` frontmatter
    /// -- the `run script` operation's grant source (plan.md §7.3.1).
    ///
    /// - Parameter id: The skill id to look up.
    /// - Returns: The skill's tokenized `allowed-tools:` grants, or `nil`
    ///   when `id` is not currently in the catalog.
    internal func allowedTools(id: String) -> [String]? {
        catalogBox.snapshot.catalog[id]?.frontmatter.allowedTools
    }

    /// A read-only view of this registry sharing its live `catalogBox`, but
    /// with reload disabled (`reloadCoordinator == nil`).
    ///
    /// A background task (e.g. `commandUpdates`'s bridging `Task`) that
    /// needs to recompute `metadata()`/`commandListing()` fresh on every
    /// reload tick must capture *this*, never `self`, inside its closure:
    /// `SkillsRegistry` is a value type, so capturing `self` there would
    /// capture a whole copy of it -- including a strong reference to this
    /// registry's own `reloadCoordinator` class instance, keeping its
    /// watcher (and the `AsyncStream` the task loops over) alive for as
    /// long as the task runs, defeating "the watcher's lifecycle is owned
    /// by the registry, stopped once every copy is deinitialized."
    /// `detachedReader` still reflects every live rebuild (it shares the
    /// same `catalogBox`), it simply never itself keeps the coordinator
    /// alive.
    internal var detachedReader: SkillsRegistry {
        SkillsRegistry(catalogBox: catalogBox, pipeline: pipeline, policy: policy, roots: roots, telemetry: telemetry)
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
            lock.withLock { (catalog, diagnostics) }
        }

        /// Atomically replaces both the catalog and its diagnostics with a
        /// freshly-rebuilt generation.
        ///
        /// - Parameters:
        ///   - catalog: The rebuilt catalog, keyed by id.
        ///   - diagnostics: The rebuilt catalog's diagnostics.
        func replace(catalog: [String: CatalogEntry], diagnostics: [SkillDiagnostic]) {
            lock.withLock {
                self.catalog = catalog
                self.diagnostics = diagnostics
            }
        }
    }

    /// Owns the `DotfolderWatcher` and the `EventBroadcaster` for a
    /// `watch: true` registry: rebuilds `catalogBox` on every coalesced
    /// watcher signal and publishes the refreshed metadata list to every
    /// current subscriber.
    ///
    /// A `final class` rather than a value type since its lifetime -- when
    /// the watcher starts and, more importantly, when it stops -- is what
    /// `SkillsRegistry` needs to own; a struct has no `deinit` to hang that
    /// stop on.
    ///
    /// `@unchecked Sendable`: every stored property (`watcher`,
    /// `broadcaster`, `marketplaceUpdates`) is an immutable `let` referring
    /// to a type that is itself safe under concurrent use --
    /// `DotfolderWatcher` is `@unchecked Sendable` and serializes its own
    /// mutable state on a private queue, `EventBroadcaster` locks its own
    /// mutable state, and
    /// `Task` is `Sendable`. This class itself declares no other stored
    /// state: the rebuild closure wired up in `init` captures
    /// `source`/`catalogBox`/`reader`/`broadcaster`/`telemetry` directly rather than
    /// `self`, so no `ReloadCoordinator` instance property is ever read or
    /// written outside of `init`/`start()`/`subscribe()`/`deinit`, none of
    /// which race with each other (`start()` and `deinit` are only ever
    /// called from the owning `SkillsRegistry`'s single construction and
    /// deinitialization points).
    private final class ReloadCoordinator: @unchecked Sendable {
        /// The watcher over the local layer roots, or `nil` for a registry
        /// that only a marketplace update rebuilds.
        private let watcher: DotfolderWatcher?
        private let broadcaster: EventBroadcaster<[SkillMetadata]>
        /// The task that rebuilds on each marketplace update, or `nil` when
        /// no provider backs this registry.
        private let marketplaceUpdates: Task<Void, Never>?

        /// Creates a `ReloadCoordinator`, wires (but does not yet start)
        /// its watcher, and begins following the marketplace updates.
        ///
        /// One rebuild closure serves both the watcher and the marketplace
        /// updates, thus a marketplace update goes through exactly the
        /// catalog swap and the publication a file change goes through, and
        /// one update gives one `onReload` value. The closure captures
        /// `source`, `catalogBox`, `reader`, `broadcaster`, and `telemetry` directly
        /// rather than `self`, so it creates no retain cycle between this
        /// coordinator and its own watcher or task.
        ///
        /// - Parameters:
        ///   - source: How to compute the layers of each rebuild, and what
        ///     makes them change.
        ///   - watchedRoots: The roots to watch, or `nil` for no watching.
        ///   - catalogBox: The catalog holder to atomically replace on
        ///     every rebuild.
        ///   - reader: A read-only registry view sharing `catalogBox`, used
        ///     to recompute `metadata()` after each rebuild via the real
        ///     rendering path.
        ///   - telemetry: The tracer and the metrics factory of each
        ///     rebuild.
        init(
            source: LayerSource, watchedRoots: [URL]?, catalogBox: CatalogBox, reader: SkillsRegistry,
            telemetry: SkillsTracing.Telemetry
        ) {
            let broadcaster = EventBroadcaster<[SkillMetadata]>()
            self.broadcaster = broadcaster
            let rebuild: @Sendable () -> Void = {
                let rebuilt = SkillsRegistry.loadCatalog(plan: source.plan(), telemetry: telemetry)
                catalogBox.replace(catalog: rebuilt.catalog, diagnostics: rebuilt.diagnostics)
                broadcaster.publish(reader.metadata())
            }
            watcher = watchedRoots.map { DotfolderWatcher(roots: $0, onChange: rebuild) }
            marketplaceUpdates = source.marketplaceUpdates.map { updates in
                Task {
                    for await _ in updates {
                        rebuild()
                    }
                }
            }
        }

        /// Starts the underlying watcher, when there is one.
        func start() {
            watcher?.start()
        }

        /// Registers a fresh subscriber stream against this coordinator's
        /// broadcaster.
        ///
        /// - Returns: A stream receiving every publication from this point
        ///   forward, independent of any other subscriber.
        func subscribe() -> AsyncStream<[SkillMetadata]> {
            broadcaster.subscribe()
        }

        /// Stops the underlying watcher, cancels the marketplace-update
        /// task, and finishes every current and future subscriber, so no
        /// further rebuilds or publications happen once every copy of the
        /// owning registry has gone out of scope.
        deinit {
            watcher?.stop()
            marketplaceUpdates?.cancel()
            broadcaster.finishAll()
        }
    }
}
