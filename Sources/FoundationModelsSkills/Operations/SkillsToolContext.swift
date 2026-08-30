/// The shared environment the three skill operations (`SearchSkill`,
/// `ListSkill`, `UseSkill`) dispatch against once fused into one
/// `OperationTool` (plan.md §7, §10).
///
/// This is the assembly seam plan.md's "Assembly" section describes: the
/// fused tool's action set is fixed by which operation structs are passed to
/// `OperationTool.init`, while every remaining knob -- how `registry` was
/// constructed (render policy, layer roots, watch) and how `searchAgent`'s
/// wrapped `MetadataSearcher` was configured (selection model, mode, signal
/// weights) -- lives entirely in how this context's properties were built,
/// not in this type itself.
public struct SkillsToolContext: Sendable {
    /// The source-of-truth registry every operation dereferences at dispatch
    /// time, never a snapshot taken once at construction.
    ///
    /// `SkillsRegistry` is a value type that shares its underlying catalog
    /// storage across copies, so reading `registry.metadata()` /
    /// `registry.call(id:arguments:)` from an operation's `execute(in:)`
    /// always observes the registry's current catalog generation, including
    /// one refreshed by a hot reload since this context was built.
    public let registry: SkillsRegistry

    /// The search agent `SearchSkill` delegates to.
    public let searchAgent: SkillSearchAgent

    /// The catalog-entry predicate `ListSkill` and `UseSkill` gate on:
    /// which surface this context presents.
    ///
    /// Defaults to `SkillMetadata.isModelVisible` -- the model-facing
    /// surface every existing caller of this `init` already got before this
    /// property existed. `SkillsCLI` supplies a different predicate (`id`
    /// membership in `registry.commandListing()`) to present the
    /// user-facing surface instead (plan.md §7.2's "Dual-use CLI").
    public let visibilityPredicate: @Sendable (SkillMetadata) -> Bool

    /// The follower that pumps `registry.onReload` into `searchAgent`, or
    /// `nil` when nothing follows the registry's reloads.
    ///
    /// Held for its lifetime alone. `SkillsReloadFollower` stops forwarding
    /// as soon as its last reference goes away, thus holding it here is what
    /// makes the forwarding loop live exactly as long as the tool this
    /// context was built for.
    ///
    /// `nil` for a `watch: false` registry, which never reloads, and for a
    /// host that asked the factory for `followReloads: false` because it
    /// pumps the stream itself.
    public let reloadFollower: SkillsReloadFollower?

    /// Creates a `SkillsToolContext` bundling a registry, its search agent,
    /// and which surface's visibility rules `ListSkill`/`UseSkill` enforce.
    ///
    /// - Parameters:
    ///   - registry: The registry every operation dereferences at dispatch
    ///     time.
    ///   - searchAgent: The search agent `SearchSkill` delegates to,
    ///     typically wrapping a `MetadataSearcher` seeded from the same
    ///     subset `visibilityPredicate` accepts.
    ///   - visibilityPredicate: Which catalog entries `ListSkill` and
    ///     `UseSkill` treat as usable. Defaults to
    ///     `SkillMetadata.isModelVisible`, the model-facing surface.
    ///   - reloadFollower: The follower this context keeps alive. Defaults
    ///     to `nil`, which leaves the host responsible for forwarding
    ///     `registry.onReload` into `searchAgent` itself.
    public init(
        registry: SkillsRegistry,
        searchAgent: SkillSearchAgent,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool = { $0.isModelVisible },
        reloadFollower: SkillsReloadFollower? = nil
    ) {
        self.registry = registry
        self.searchAgent = searchAgent
        self.visibilityPredicate = visibilityPredicate
        self.reloadFollower = reloadFollower
    }
}
