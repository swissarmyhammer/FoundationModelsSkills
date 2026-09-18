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
/// `SkillsCatalogTool` conforms to the FoundationModels `Tool` protocol.
///
/// `SkillsTool.make(context:catalogCharacterLimit:)` is the low-level door
/// for a host that tunes the searcher itself: a different `SearchMode`,
/// other signal weights, or its own diagnostic sink. Each factory here
/// forwards `catalogCharacterLimit` to it.
extension SkillsTool {
    /// Builds the fused `skills` tool over `registry`, with a selection tier
    /// that asks the host for a new session for each assembled candidate
    /// prefix.
    ///
    /// The package owns the shape of the selection answer (plan.md decision
    /// #31). Each `SelectionSessionRequest` carries the JSON Schema that
    /// limits an answer to `{"ids": [String]}` over the candidate skill ids,
    /// and the host makes a session that applies it. A session with no
    /// constraint can still answer with another shape, and that answer does
    /// not fail the call: the search then gives the rank of the retrieval
    /// tier.
    ///
    /// The searcher runs in `.auto` mode, thus the selection tier answers
    /// every search. A second searcher in `.retrieval` mode shares the first
    /// one's index, and is the fallback of `SkillSearchAgent`. With an
    /// `embedder`, the index is embedded one time for both searchers. A hot
    /// reload updates both searchers, thus a block that the reload changed is
    /// embedded one time for each searcher.
    ///
    /// This factory is `async` because a non-`nil` `embedder` embeds every
    /// item's block while it builds the index.
    ///
    /// - Parameters:
    ///   - registry: The registry every operation dereferences at dispatch
    ///     time.
    ///   - session: Makes a session from a `SelectionSessionRequest`. Every
    ///     selection call goes to a session this closure made. A session
    ///     whose model takes a JSON Schema grammar applies
    ///     `request.jsonSchema`. A `LanguageModelSession` needs only
    ///     `request.instructions`, because its guided generation constrains
    ///     the answer shape itself.
    ///   - embedder: The embedder that embeds every item's block at build
    ///     time, and the query at search time. Defaults to `nil`, which
    ///     leaves the cosine signal out.
    ///   - followReloads: Whether the tool follows `registry.onReload`
    ///     itself. Defaults to `true`. See `assemble(registry:mode:embedder:
    ///     selection:followReloads:catalogCharacterLimit:visibilityPredicate:)`.
    ///   - catalogCharacterLimit: The most characters the catalog list of
    ///     the tool description may have. Defaults to
    ///     `defaultCatalogCharacterLimit`. See `make(context:catalogCharacterLimit:)`.
    ///   - visibilityPredicate: Which catalog entries this tool presents.
    ///     Defaults to `SkillMetadata.isModelVisible`, the model-facing
    ///     surface.
    /// - Returns: The fused `skills` tool, ready to register on a
    ///   `LanguageModelSession`.
    /// - Throws: Whatever `SkillsTool.make(context:catalogCharacterLimit:)`
    ///   throws.
    public static func make(
        registry: SkillsRegistry,
        session: @escaping @Sendable (SelectionSessionRequest) -> any AgentSession,
        embedder: (any TextEmbedding)? = nil,
        followReloads: Bool = true,
        catalogCharacterLimit: Int = defaultCatalogCharacterLimit,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool = { $0.isModelVisible }
    ) async throws -> SkillsCatalogTool {
        try await assemble(
            registry: registry,
            mode: .auto,
            embedder: embedder,
            selection: makeSelection(registry: registry, session: session, visibilityPredicate: visibilityPredicate),
            followReloads: followReloads,
            catalogCharacterLimit: catalogCharacterLimit,
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
    /// This factory is `async` for the same reason as the one above: a
    /// non-`nil` `embedder` embeds every item's block while it builds the
    /// index. A `nil` `embedder` leaves the search keyword-only.
    ///
    /// - Parameters:
    ///   - registry: The registry every operation dereferences at dispatch
    ///     time.
    ///   - embedder: The embedder that embeds every item's block at build
    ///     time, and the query at search time. Defaults to `nil`, which
    ///     leaves the cosine signal out.
    ///   - followReloads: Whether the tool follows `registry.onReload`
    ///     itself. Defaults to `true`. See `assemble(registry:mode:embedder:
    ///     selection:followReloads:catalogCharacterLimit:visibilityPredicate:)`.
    ///   - catalogCharacterLimit: The most characters the catalog list of
    ///     the tool description may have. Defaults to
    ///     `defaultCatalogCharacterLimit`. See `make(context:catalogCharacterLimit:)`.
    ///   - visibilityPredicate: Which catalog entries this tool presents.
    ///     Defaults to `SkillMetadata.isModelVisible`, the model-facing
    ///     surface.
    /// - Returns: The fused `skills` tool, ready to drive from a host with
    ///   no model.
    /// - Throws: Whatever `SkillsTool.make(context:catalogCharacterLimit:)`
    ///   throws.
    public static func make(
        registry: SkillsRegistry,
        embedder: (any TextEmbedding)? = nil,
        followReloads: Bool = true,
        catalogCharacterLimit: Int = defaultCatalogCharacterLimit,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool = { $0.isModelVisible }
    ) async throws -> SkillsCatalogTool {
        try await assemble(
            registry: registry,
            mode: .retrieval,
            embedder: embedder,
            selection: nil,
            followReloads: followReloads,
            catalogCharacterLimit: catalogCharacterLimit,
            visibilityPredicate: visibilityPredicate)
    }

    /// Makes the selection tier configuration that asks `session` for each
    /// new session.
    ///
    /// The tier's factory takes the instructions alone, thus the candidate
    /// ids come from the live `registry` through `visibilityPredicate` when
    /// the tier asks. The tier asks when it makes its root session, and a
    /// reload replaces the tier, thus the ids follow each reload. Over the
    /// character budget, the tier prompts one run of candidates at a time
    /// while the schema permits every visible id. The tier drops an answered
    /// id that is not in the prompt's run.
    ///
    /// When the request cannot be made, the tier gets an
    /// `UnavailableSelectionSession`. Its failure reaches `SkillSearchAgent`,
    /// which records it and gives the retrieval rank.
    ///
    /// - Parameters:
    ///   - registry: The registry the candidate ids come from.
    ///   - session: The host's session factory.
    ///   - visibilityPredicate: Which catalog entries are candidates.
    /// - Returns: The selection tier configuration.
    private static func makeSelection(
        registry: SkillsRegistry,
        session: @escaping @Sendable (SelectionSessionRequest) -> any AgentSession,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool
    ) -> SelectionConfig {
        SelectionConfig(model: { instructions in
            let candidateIDs = registry.metadata().filter(visibilityPredicate).map(\.id)
            do {
                return session(try SelectionSessionRequest(instructions: instructions, candidateIDs: candidateIDs))
            } catch {
                return UnavailableSelectionSession(cause: error)
            }
        })
    }

    /// The assembly steps both factories above share.
    ///
    /// Reads `registry.metadata()` and keeps the `visibilityPredicate`
    /// subset, builds the `MetadataSearcher` over that subset, wraps it in a
    /// `SkillSearchAgent` with the same predicate, and gives the resulting
    /// `SkillsToolContext` to `SkillsTool.make(context:catalogCharacterLimit:)`.
    ///
    /// - Parameters:
    ///   - registry: The registry the assembled context wraps.
    ///   - mode: Which tier the searcher uses.
    ///   - embedder: The embedder to build the index with, or `nil`.
    ///   - selection: The selection tier configuration, or `nil` for no
    ///     selection tier.
    ///   - followReloads: Whether the assembled context carries a
    ///     `SkillsReloadFollower`.
    ///   - catalogCharacterLimit: The most characters the catalog list of
    ///     the tool description may have.
    ///   - visibilityPredicate: Which catalog entries the assembled tool
    ///     presents.
    /// - Returns: The fused `skills` tool.
    /// - Throws: Whatever `SkillsTool.make(context:catalogCharacterLimit:)`
    ///   throws.
    private static func assemble(
        registry: SkillsRegistry,
        mode: SearchMode,
        embedder: (any TextEmbedding)?,
        selection: SelectionConfig?,
        followReloads: Bool,
        catalogCharacterLimit: Int,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool
    ) async throws -> SkillsCatalogTool {
        let context = await makeContext(
            registry: registry,
            mode: mode,
            embedder: embedder,
            selection: selection,
            followReloads: followReloads,
            visibilityPredicate: visibilityPredicate)
        return try make(context: context, catalogCharacterLimit: catalogCharacterLimit)
    }

    /// Builds the `SkillsToolContext` `assemble(registry:mode:embedder:
    /// selection:followReloads:catalogCharacterLimit:visibilityPredicate:)`
    /// hands to `SkillsTool.make(context:catalogCharacterLimit:)`.
    ///
    /// The searcher, the agent, and the context all get the same
    /// `visibilityPredicate`. Thus one surface holds for the first search,
    /// for every later hot reload, and for the `list skill` and `use skill`
    /// operations.
    ///
    /// With a `selection` configuration, the agent also gets a retrieval
    /// fallback: a second searcher in `.retrieval` mode over the same index.
    /// The index is built one time, thus an `embedder` embeds each block one
    /// time for both searchers.
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
        let index = await MetadataIndex.build(
            items: registry.metadata().filter(visibilityPredicate),
            embedder: embedder)
        let searcher = MetadataSearcher(index: index, mode: mode, embedder: embedder, selection: selection)
        let retrievalFallback = selection.map { _ in
            MetadataSearcher(index: index, mode: .retrieval, embedder: embedder)
        }
        let agent = SkillSearchAgent(
            searcher: searcher, retrievalFallback: retrievalFallback, visibilityPredicate: visibilityPredicate)
        return SkillsToolContext(
            registry: registry,
            searchAgent: agent,
            visibilityPredicate: visibilityPredicate,
            reloadFollower: reloads.map { SkillsReloadFollower(reloads: $0, agent: agent) })
    }
}
