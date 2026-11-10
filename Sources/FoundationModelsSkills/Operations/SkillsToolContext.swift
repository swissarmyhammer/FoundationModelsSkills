import FoundationModelsExtras

/// The shared environment the three skill operations (`SearchSkill`,
/// `ListSkill`, `UseSkill`) dispatch against once fused into one
/// `OperationTool`.
///
/// This is the assembly seam: the
/// fused tool's action set is fixed by which operation structs are passed to
/// `OperationTool.init` -- `SkillsTool.make(context:catalogCharacterLimit:)`
/// picks them by `mode` -- while every remaining knob -- how `registry` was
/// constructed (render policy, tool mode, layer roots, watch) and how `searchAgent`'s
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
    /// user-facing surface instead.
    public let visibilityPredicate: @Sendable (SkillMetadata) -> Bool

    /// The follower that pumps `registry.onReload` into `searchAgent`, or
    /// `nil` when nothing follows the registry's reloads.
    ///
    /// Held for its lifetime alone. `SkillsReloadFollower` stops forwarding
    /// as soon as its last reference goes away, thus holding it here is what
    /// makes the forwarding loop live exactly as long as the tool this
    /// context was built for.
    ///
    /// `nil` for a host that asked the factory for `followReloads: false`
    /// because it pumps the stream itself, and for a context that a host
    /// builds without one.
    public let reloadFollower: SkillsReloadFollower?

    /// The follower that posts a catalog-change notice for each reload that
    /// changes the listed catalog, or `nil` when no notice is posted.
    ///
    /// Held for its lifetime alone, the same as `reloadFollower`. `nil` only
    /// for a context that a host builds without one.
    public let catalogNoticeFollower: SkillsCatalogNoticeFollower?

    /// The board of the catalog notices. `SkillsTool.make(context:)` gives it
    /// to each tool it makes, and each session that mounts such a tool joins
    /// it.
    ///
    /// It is the board of `catalogNoticeFollower`, thus the follower posts to
    /// the board that the sessions join. With no follower, it is a board that
    /// gets no notice.
    public let catalogNoticeBoard: CatalogNoticeBoard

    /// The mode of the tools of the host: the mode of `registry`.
    ///
    /// `SkillsTool.make(context:catalogCharacterLimit:)` reads it. In
    /// `ToolMode.sandboxed` the tool has no `run script` operation, and no
    /// operation of the tool starts a process.
    public let mode: ToolMode

    /// The error of the initializer when its `mode` is not the mode of the
    /// registry.
    ///
    /// The registry renders each body in its own mode, and the context gives
    /// the operations of the tool in its mode. Two different modes would give
    /// a tool that starts a process in `ToolMode.sandboxed`, or a tool that
    /// has `run script` while the body renders start no process. Thus the
    /// context refuses them.
    public struct ModeMismatchError: Error, Equatable, Sendable {
        /// The mode of the registry.
        public let registryMode: ToolMode

        /// The mode that the context got.
        public let contextMode: ToolMode

        /// Creates a `ModeMismatchError`.
        ///
        /// - Parameters:
        ///   - registryMode: The mode of the registry.
        ///   - contextMode: The mode that the context got.
        public init(registryMode: ToolMode, contextMode: ToolMode) {
            self.registryMode = registryMode
            self.contextMode = contextMode
        }
    }

    /// Creates a `SkillsToolContext` bundling a registry, its search agent,
    /// and which surface's visibility rules `ListSkill`/`UseSkill` enforce.
    ///
    /// This is the composition point of the `skills` tool, thus it calls
    /// `ToolMode.validate(probe:)` before a tool is made: `ToolMode.open` in a
    /// sandboxed process fails here, not at the first tool call.
    ///
    /// - Parameters:
    ///   - registry: The registry every operation dereferences at dispatch
    ///     time.
    ///   - searchAgent: The search agent `SearchSkill` delegates to,
    ///     typically wrapping a `MetadataSearcher` seeded from the same
    ///     subset `visibilityPredicate` accepts.
    ///   - mode: The mode of the tools of the host. It must be
    ///     `registry.mode`. It has no default: each host states its mode.
    ///   - sandboxProbe: The probe that tells if the process is sandboxed.
    ///     Defaults to `SandboxProbe.live`, which reads the current process.
    ///   - visibilityPredicate: Which catalog entries `ListSkill` and
    ///     `UseSkill` treat as usable. Defaults to
    ///     `SkillMetadata.isModelVisible`, the model-facing surface.
    ///   - reloadFollower: The follower this context keeps alive. Defaults
    ///     to `nil`, which leaves the host responsible for forwarding
    ///     `registry.onReload` into `searchAgent` itself.
    ///   - catalogNoticeFollower: The notice follower this context keeps
    ///     alive. Its board becomes `catalogNoticeBoard`. Defaults to `nil`,
    ///     which posts no notice.
    /// - Throws: `ToolModeError.openModeInSandbox` when `mode` is
    ///   `ToolMode.open` and `sandboxProbe` tells that the process is
    ///   sandboxed; `ModeMismatchError` when `mode` is not `registry.mode`.
    public init(
        registry: SkillsRegistry,
        searchAgent: SkillSearchAgent,
        mode: ToolMode,
        sandboxProbe: SandboxProbe = .live,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool = { $0.isModelVisible },
        reloadFollower: SkillsReloadFollower? = nil,
        catalogNoticeFollower: SkillsCatalogNoticeFollower? = nil
    ) throws {
        try mode.validate(probe: sandboxProbe)
        guard mode == registry.mode else {
            throw ModeMismatchError(registryMode: registry.mode, contextMode: mode)
        }
        self.mode = mode
        self.registry = registry
        self.searchAgent = searchAgent
        self.visibilityPredicate = visibilityPredicate
        self.reloadFollower = reloadFollower
        self.catalogNoticeFollower = catalogNoticeFollower
        catalogNoticeBoard = catalogNoticeFollower?.board ?? CatalogNoticeBoard()
    }
}
