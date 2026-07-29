import FoundationModelsMetadataRegistry

/// A thin wrapper over `MetadataSearcher<SkillMetadata>` that searches and
/// hot-reloads the model-visible skill catalog (plan.md §7, §7.1; decision
/// #26).
///
/// Every retrieval/selection knob -- the selection model, `SearchMode`, and
/// signal weights -- lives entirely in how the caller constructs the
/// `MetadataSearcher` passed to `init(searcher:)`; this wrapper never
/// configures the searcher itself, only forwards `search(query:limit:)` and
/// filters `update(items:)`'s input to the model-visible subset.
public struct SkillSearchAgent: Sendable {
    /// The wrapped searcher, already seeded and configured (selection
    /// model, mode, weights) by the caller before this wrapper ever sees
    /// it.
    private let searcher: MetadataSearcher<SkillMetadata>

    /// Creates a `SkillSearchAgent` over an already-configured searcher.
    ///
    /// - Parameter searcher: The `MetadataSearcher` to wrap, typically
    ///   seeded with `SkillsRegistry.metadata()`'s model-visible subset
    ///   (plan.md §10's public API sketch).
    public init(searcher: MetadataSearcher<SkillMetadata>) {
        self.searcher = searcher
    }

    /// Searches the wrapped catalog for `query`, ranked best first.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: The maximum number of matches to return.
    /// - Returns: At most `limit` matching skills' metadata, best first --
    ///   a caller reports the result's own `count` alongside it as the
    ///   `total` a `search skill` response carries (plan.md §7's
    ///   `SearchSkillResult.total`).
    /// - Throws: `SelectionTierUnavailable` when the wrapped searcher's mode
    ///   is `.selection` with no selection tier configured; otherwise
    ///   whatever the underlying selection session throws.
    public func search(query: String, limit: Int) async throws -> [SkillMetadata] {
        try await searcher.search(intent: query, limit: limit).map(\.item)
    }

    /// Hot-reloads the wrapped searcher's catalog from `items`, forwarding
    /// only the model-visible subset.
    ///
    /// - Parameter items: The catalog's refreshed metadata rows, in
    ///   first-seen-wins duplicate-id order -- typically a `SkillsRegistry`
    ///   reload's full, unfiltered `metadata()` list (plan.md §7 "Reload &
    ///   metadata injection").
    public func update(items: [SkillMetadata]) async {
        await searcher.update(items: items.filter(\.isModelVisible))
    }
}
