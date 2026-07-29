/// The shared environment the three skill operations (`SearchSkill`,
/// `ListSkill`, `UseSkill`) dispatch against once fused into one
/// `OperationTool` (plan.md §7, §10).
///
/// This is the assembly seam plan.md's "Assembly" section describes: the
/// fused tool's action set is fixed by which operation structs are passed to
/// `OperationTool.init`, while every remaining knob -- how `registry` was
/// constructed (render policy, layer roots, watch) and how `searchAgent`'s
/// wrapped `MetadataSearcher` was configured (selection model, mode, signal
/// weights) -- lives entirely in how this context's two properties were
/// built, not in this type itself.
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

    /// Creates a `SkillsToolContext` bundling a registry and its search
    /// agent.
    ///
    /// - Parameters:
    ///   - registry: The registry every operation dereferences at dispatch
    ///     time.
    ///   - searchAgent: The search agent `SearchSkill` delegates to,
    ///     typically wrapping a `MetadataSearcher` seeded from
    ///     `registry.metadata()`'s model-visible subset.
    public init(registry: SkillsRegistry, searchAgent: SkillSearchAgent) {
        self.registry = registry
        self.searchAgent = searchAgent
    }
}
