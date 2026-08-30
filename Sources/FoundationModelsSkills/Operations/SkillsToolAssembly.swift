import FoundationModelsMetadataRegistry
import Operations

/// One-call factories that assemble the fused `skills` tool for a host.
///
/// Before these factories, a host had to build four things by hand: a
/// `SkillsRegistry`, a `MetadataSearcher`, a `SkillSearchAgent`, and a
/// `SkillsToolContext`. Each factory below does those steps in one call, and
/// takes the selection session as a parameter. Thus the host gives the model
/// its session, and no factory here makes a session of its own.
///
/// The result goes straight into `LanguageModelSession(tools:)`, because
/// `OperationTool` conforms to the FoundationModels `Tool` protocol.
///
/// `SkillsTool.make(context:)` stays as it is. It is the low-level door for
/// a host that tunes the searcher itself: a different `SearchMode`, other
/// signal weights, or its own diagnostic sink.
extension SkillsTool {
    /// Builds the fused `skills` tool over `registry`, with a selection tier
    /// that makes a new session for each assembled candidate prefix.
    ///
    /// Matches `SelectionConfig.init(model:preamble:capacityCharacterLimit:
    /// candidateLimit:)`. The searcher runs in `.auto` mode, thus the
    /// selection tier answers every search, and the retrieval tier ranks the
    /// candidates the tier chooses among.
    ///
    /// This factory is `async` because a non-`nil` `embedder` needs
    /// `MetadataSearcher`'s own `async` initializer, which embeds every
    /// item's block while it builds the index.
    ///
    /// - Parameters:
    ///   - registry: The registry every operation dereferences at dispatch
    ///     time.
    ///   - session: Makes a session seeded with the given instructions text.
    ///     Every selection call goes to a session this closure made.
    ///   - embedder: The embedder that embeds every item's block at build
    ///     time, and the query at search time. Defaults to `nil`, which
    ///     leaves the cosine signal out.
    ///   - followReloads: Whether the tool follows `registry.onReload`
    ///     itself. Defaults to `true`. See `assemble(registry:mode:embedder:
    ///     selection:followReloads:visibilityPredicate:)`.
    ///   - visibilityPredicate: Which catalog entries this tool presents.
    ///     Defaults to `SkillMetadata.isModelVisible`, the model-facing
    ///     surface.
    /// - Returns: The fused `skills` tool, ready to register on a
    ///   `LanguageModelSession`.
    /// - Throws: Whatever `SkillsTool.make(context:)` throws.
    public static func make(
        registry: SkillsRegistry,
        session: @escaping @Sendable (String) -> any AgentSession,
        embedder: (any TextEmbedding)? = nil,
        followReloads: Bool = true,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool = { $0.isModelVisible }
    ) async throws -> OperationTool<SkillsToolContext> {
        try await assemble(
            registry: registry,
            mode: .auto,
            embedder: embedder,
            selection: SelectionConfig(model: session),
            followReloads: followReloads,
            visibilityPredicate: visibilityPredicate)
    }

    /// Builds the fused `skills` tool over `registry`, with a selection tier
    /// that reuses one live session the host already holds.
    ///
    /// Matches `SelectionConfig.init(session:preamble:
    /// capacityCharacterLimit:candidateLimit:)`. A live session takes no new
    /// instructions, thus the tier forks it for each call and puts the
    /// assembled prefix in the prompt. The searcher runs in `.auto` mode,
    /// thus the selection tier answers every search.
    ///
    /// This factory is `async` for the same reason as the one above: a
    /// non-`nil` `embedder` needs `MetadataSearcher`'s `async` initializer.
    ///
    /// - Parameters:
    ///   - registry: The registry every operation dereferences at dispatch
    ///     time.
    ///   - session: The session every selection call forks a child from.
    ///   - embedder: The embedder that embeds every item's block at build
    ///     time, and the query at search time. Defaults to `nil`, which
    ///     leaves the cosine signal out.
    ///   - followReloads: Whether the tool follows `registry.onReload`
    ///     itself. Defaults to `true`. See `assemble(registry:mode:embedder:
    ///     selection:followReloads:visibilityPredicate:)`.
    ///   - visibilityPredicate: Which catalog entries this tool presents.
    ///     Defaults to `SkillMetadata.isModelVisible`, the model-facing
    ///     surface.
    /// - Returns: The fused `skills` tool, ready to register on a
    ///   `LanguageModelSession`.
    /// - Throws: Whatever `SkillsTool.make(context:)` throws.
    public static func make(
        registry: SkillsRegistry,
        session: any AgentSession,
        embedder: (any TextEmbedding)? = nil,
        followReloads: Bool = true,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool = { $0.isModelVisible }
    ) async throws -> OperationTool<SkillsToolContext> {
        try await assemble(
            registry: registry,
            mode: .auto,
            embedder: embedder,
            selection: SelectionConfig(session: session),
            followReloads: followReloads,
            visibilityPredicate: visibilityPredicate)
    }

    /// Builds the fused `skills` tool over `registry` with no model at all:
    /// keyword retrieval only.
    ///
    /// The searcher gets `mode: .retrieval` explicitly. The default is
    /// `.auto`, which is the same thing while no selection tier is
    /// configured, but `.retrieval` says what this factory promises: no
    /// session, no tokens, and an answer in milliseconds. A host with no
    /// model, such as a command-line driver or a typeahead field, uses this
    /// one.
    ///
    /// This factory is `async` for the same reason as the two above: a
    /// non-`nil` `embedder` needs `MetadataSearcher`'s `async` initializer.
    /// A `nil` `embedder` leaves the search keyword-only.
    ///
    /// - Parameters:
    ///   - registry: The registry every operation dereferences at dispatch
    ///     time.
    ///   - embedder: The embedder that embeds every item's block at build
    ///     time, and the query at search time. Defaults to `nil`, which
    ///     leaves the cosine signal out.
    ///   - followReloads: Whether the tool follows `registry.onReload`
    ///     itself. Defaults to `true`. See `assemble(registry:mode:embedder:
    ///     selection:followReloads:visibilityPredicate:)`.
    ///   - visibilityPredicate: Which catalog entries this tool presents.
    ///     Defaults to `SkillMetadata.isModelVisible`, the model-facing
    ///     surface.
    /// - Returns: The fused `skills` tool, ready to drive from a host with
    ///   no model.
    /// - Throws: Whatever `SkillsTool.make(context:)` throws.
    public static func make(
        registry: SkillsRegistry,
        embedder: (any TextEmbedding)? = nil,
        followReloads: Bool = true,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool = { $0.isModelVisible }
    ) async throws -> OperationTool<SkillsToolContext> {
        try await assemble(
            registry: registry,
            mode: .retrieval,
            embedder: embedder,
            selection: nil,
            followReloads: followReloads,
            visibilityPredicate: visibilityPredicate)
    }

    /// The assembly steps all three factories above share.
    ///
    /// Reads `registry.metadata()` and keeps the `visibilityPredicate`
    /// subset, builds the `MetadataSearcher` over that subset, wraps it in a
    /// `SkillSearchAgent` with the same predicate, and gives the resulting
    /// `SkillsToolContext` to `SkillsTool.make(context:)`.
    ///
    /// - Parameters:
    ///   - registry: The registry the assembled context wraps.
    ///   - mode: Which tier the searcher uses.
    ///   - embedder: The embedder to build the index with, or `nil`.
    ///   - selection: The selection tier configuration, or `nil` for no
    ///     selection tier.
    ///   - followReloads: Whether the assembled context carries a
    ///     `SkillsReloadFollower`.
    ///   - visibilityPredicate: Which catalog entries the assembled tool
    ///     presents.
    /// - Returns: The fused `skills` tool.
    /// - Throws: Whatever `SkillsTool.make(context:)` throws.
    private static func assemble(
        registry: SkillsRegistry,
        mode: SearchMode,
        embedder: (any TextEmbedding)?,
        selection: SelectionConfig?,
        followReloads: Bool,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool
    ) async throws -> OperationTool<SkillsToolContext> {
        let context = await makeContext(
            registry: registry,
            mode: mode,
            embedder: embedder,
            selection: selection,
            followReloads: followReloads,
            visibilityPredicate: visibilityPredicate)
        return try make(context: context)
    }

    /// Builds the `SkillsToolContext` `assemble(registry:mode:embedder:
    /// selection:followReloads:visibilityPredicate:)` hands to
    /// `SkillsTool.make(context:)`.
    ///
    /// The searcher, the agent, and the context all get the same
    /// `visibilityPredicate`. Thus one surface holds for the first search,
    /// for every later hot reload, and for the `list skill` and `use skill`
    /// operations.
    ///
    /// The reload stream is taken before the seed catalog is read, and that
    /// order matters: `registry.onReload` carries every publication from the
    /// point of subscription forward, thus reading `metadata()` first would
    /// drop a reload that lands between the two reads. A `watch: false`
    /// registry answers `nil` there, and gets no follower.
    ///
    /// - Parameters:
    ///   - registry: The registry the assembled context wraps.
    ///   - mode: Which tier the searcher uses.
    ///   - embedder: The embedder to build the index with, or `nil`.
    ///   - selection: The selection tier configuration, or `nil` for no
    ///     selection tier.
    ///   - followReloads: Whether the assembled context carries a
    ///     `SkillsReloadFollower`. A host that pumps `registry.onReload`
    ///     itself passes `false`, thus no publication reaches the agent
    ///     twice.
    ///   - visibilityPredicate: Which catalog entries the assembled tool
    ///     presents.
    /// - Returns: The assembled context.
    internal static func makeContext(
        registry: SkillsRegistry,
        mode: SearchMode,
        embedder: (any TextEmbedding)?,
        selection: SelectionConfig?,
        followReloads: Bool,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool
    ) async -> SkillsToolContext {
        let reloads = followReloads ? registry.onReload : nil
        let searcher = await MetadataSearcher(
            items: registry.metadata().filter(visibilityPredicate),
            mode: mode,
            embedder: embedder,
            selection: selection)
        let agent = SkillSearchAgent(searcher: searcher, visibilityPredicate: visibilityPredicate)
        return SkillsToolContext(
            registry: registry,
            searchAgent: agent,
            visibilityPredicate: visibilityPredicate,
            reloadFollower: reloads.map { SkillsReloadFollower(reloads: $0, agent: agent) })
    }
}
