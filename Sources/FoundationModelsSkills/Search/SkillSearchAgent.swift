import FoundationModelsMetadataRegistry
import os

/// A thin wrapper over `MetadataSearcher<SkillMetadata>` that searches and
/// hot-reloads a chosen surface's skill catalog (plan.md §7, §7.1, §7.2;
/// decision #26).
///
/// Every retrieval/selection knob -- the selection model, `SearchMode`, and
/// signal weights -- lives entirely in how the caller constructs the
/// `MetadataSearcher` passed to `init(searcher:retrievalFallback:
/// visibilityPredicate:)`; this wrapper never configures the searcher itself,
/// only forwards `search(query:limit:)` and filters `update(items:)`'s input
/// to `visibilityPredicate`'s subset.
///
/// A caller can also give a second searcher in `.retrieval` mode, the
/// retrieval fallback. Then an answer of the selection model that does not
/// decode does not fail the search: the fallback ranks the same query, and
/// the failure goes to the log (plan.md decision #31).
public struct SkillSearchAgent: Sendable {
    /// The wrapped searcher, already seeded and configured (selection
    /// model, mode, weights) by the caller before this wrapper ever sees
    /// it.
    private let searcher: MetadataSearcher<SkillMetadata>

    /// The searcher that ranks a query when `searcher` throws, or `nil` when
    /// a failure of `searcher` goes to the caller.
    ///
    /// Seeded over the same subset as `searcher`, and updated with it, thus
    /// the two always rank the same catalog.
    private let retrievalFallback: MetadataSearcher<SkillMetadata>?

    /// Which catalog entries `update(items:)` forwards to the wrapped
    /// searcher -- the same surface `searcher` was originally seeded over,
    /// so a later hot reload never silently drifts onto a different
    /// surface than the one this agent was built for.
    private let visibilityPredicate: @Sendable (SkillMetadata) -> Bool

    /// Where a search records a failure of `searcher` that the retrieval
    /// fallback answered.
    private static let logger = Logger(subsystem: "FoundationModelsSkills", category: "SkillSearchAgent")

    /// Creates a `SkillSearchAgent` over an already-configured searcher.
    ///
    /// - Parameters:
    ///   - searcher: The `MetadataSearcher` to wrap, typically seeded with
    ///     `SkillsRegistry.metadata()`'s `visibilityPredicate` subset
    ///     (plan.md §10's public API sketch).
    ///   - retrievalFallback: A searcher in `.retrieval` mode over the same
    ///     subset, which ranks the query when `searcher` throws. Defaults to
    ///     `nil`, which gives every failure of `searcher` to the caller. The
    ///     `SkillsTool.make(registry:session:embedder:followReloads:
    ///     visibilityPredicate:)` factory always gives one.
    ///   - visibilityPredicate: Which catalog entries `update(items:)`
    ///     forwards to `searcher`. Defaults to `SkillMetadata.isModelVisible`,
    ///     the model-facing surface -- a caller presenting a different
    ///     surface (e.g. `SkillsCLI`'s user-facing one, plan.md §7.2) passes
    ///     the matching predicate so a later reload stays on that surface.
    public init(
        searcher: MetadataSearcher<SkillMetadata>,
        retrievalFallback: MetadataSearcher<SkillMetadata>? = nil,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool = { $0.isModelVisible }
    ) {
        self.searcher = searcher
        self.retrievalFallback = retrievalFallback
        self.visibilityPredicate = visibilityPredicate
    }

    /// Searches the wrapped catalog for `query`, ranked best first.
    ///
    /// When the wrapped searcher throws and a retrieval fallback is set, the
    /// fallback ranks `query` instead, and the failure goes to the log. A
    /// selection model that answers `[explore]`, not `{"ids": ["explore"]}`,
    /// thus gives the keyword rank, not a failed call. A cancellation is not
    /// a failure of the model, thus it always goes to the caller.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: The maximum number of matches to return.
    /// - Returns: At most `limit` matching skills' metadata, best first.
    /// - Throws: With no retrieval fallback: `SelectionTierUnavailable` when
    ///   the wrapped searcher's mode is `.selection` with no selection tier
    ///   configured, otherwise whatever the underlying selection session
    ///   throws. With a retrieval fallback: a cancellation, or whatever the
    ///   fallback throws.
    public func search(query: String, limit: Int) async throws -> [SkillMetadata] {
        do {
            return try await searcher.search(intent: query, limit: limit).map(\.item)
        } catch {
            guard let retrievalFallback, !Self.isCancellation(error) else { throw error }
            Self.logger.notice(
                "The selection tier failed, thus the retrieval rank answers this search. Cause: \(String(describing: error))"
            )
            return try await retrievalFallback.search(intent: query, limit: limit).map(\.item)
        }
    }

    /// Hot-reloads the wrapped searcher's catalog, and the retrieval
    /// fallback's catalog, from `items`, forwarding only
    /// `visibilityPredicate`'s subset.
    ///
    /// - Parameter items: The catalog's refreshed metadata rows, in
    ///   first-seen-wins duplicate-id order -- typically a `SkillsRegistry`
    ///   reload's full, unfiltered `metadata()` list (plan.md §7 "Reload &
    ///   metadata injection").
    public func update(items: [SkillMetadata]) async {
        let visibleItems = items.filter(visibilityPredicate)
        await searcher.update(items: visibleItems)
        await retrievalFallback?.update(items: visibleItems)
    }

    /// Whether `error` stops the search because its task was cancelled.
    ///
    /// - Parameter error: The error the wrapped searcher threw.
    /// - Returns: `true` for a `CancellationError`, or for any error that a
    ///   cancelled task threw.
    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || Task.isCancelled
    }
}
