import FoundationModelsMetadataRegistry

/// A thin wrapper over `MetadataSearcher<SkillMetadata>` that searches and
/// hot-reloads a chosen surface's skill catalog (plan.md §7, §7.1, §7.2;
/// decision #26).
///
/// Every retrieval/selection knob -- the selection model, `SearchMode`, and
/// signal weights -- lives entirely in how the caller constructs the
/// `MetadataSearcher` passed to `init(searcher:visibilityPredicate:)`; this
/// wrapper never configures the searcher itself, only forwards
/// `search(query:limit:)` and filters `update(items:)`'s input to
/// `visibilityPredicate`'s subset.
public struct SkillSearchAgent: Sendable {
    /// The wrapped searcher, already seeded and configured (selection
    /// model, mode, weights) by the caller before this wrapper ever sees
    /// it.
    private let searcher: MetadataSearcher<SkillMetadata>

    /// Which catalog entries `update(items:)` forwards to the wrapped
    /// searcher -- the same surface `searcher` was originally seeded over,
    /// so a later hot reload never silently drifts onto a different
    /// surface than the one this agent was built for.
    private let visibilityPredicate: @Sendable (SkillMetadata) -> Bool

    /// Creates a `SkillSearchAgent` over an already-configured searcher.
    ///
    /// - Parameters:
    ///   - searcher: The `MetadataSearcher` to wrap, typically seeded with
    ///     `SkillsRegistry.metadata()`'s `visibilityPredicate` subset
    ///     (plan.md §10's public API sketch).
    ///   - visibilityPredicate: Which catalog entries `update(items:)`
    ///     forwards to `searcher`. Defaults to `SkillMetadata.isModelVisible`,
    ///     the model-facing surface -- a caller presenting a different
    ///     surface (e.g. `SkillsCLI`'s user-facing one, plan.md §7.2) passes
    ///     the matching predicate so a later reload stays on that surface.
    public init(
        searcher: MetadataSearcher<SkillMetadata>,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool = { $0.isModelVisible }
    ) {
        self.searcher = searcher
        self.visibilityPredicate = visibilityPredicate
    }

    /// Searches the wrapped catalog for `query`, ranked best first.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: The maximum number of matches to return.
    /// - Returns: At most `limit` matching skills' metadata, best first.
    /// - Throws: `SelectionTierUnavailable` when the wrapped searcher's mode
    ///   is `.selection` with no selection tier configured; otherwise
    ///   whatever the underlying selection session throws.
    public func search(query: String, limit: Int) async throws -> [SkillMetadata] {
        try await searcher.search(intent: query, limit: limit).map(\.item)
    }

    /// Hot-reloads the wrapped searcher's catalog from `items`, forwarding
    /// only `visibilityPredicate`'s subset.
    ///
    /// - Parameter items: The catalog's refreshed metadata rows, in
    ///   first-seen-wins duplicate-id order -- typically a `SkillsRegistry`
    ///   reload's full, unfiltered `metadata()` list (plan.md §7 "Reload &
    ///   metadata injection").
    public func update(items: [SkillMetadata]) async {
        await searcher.update(items: items.filter(visibilityPredicate))
    }
}
