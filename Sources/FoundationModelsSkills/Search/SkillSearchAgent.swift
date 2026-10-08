import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import Logging
import Tracing

/// A thin wrapper over `MetadataSearcher<SkillMetadata>` that searches and
/// hot-reloads a chosen surface's skill catalog.
///
/// Every retrieval/selection knob -- the selection model, `SearchMode`, and
/// signal weights -- lives entirely in how the caller constructs the
/// `MetadataSearcher` passed to `init(searcher:retrievalFallback:
/// visibilityPredicate:)`; this wrapper never configures the searcher itself,
/// only forwards `search(query:limit:)` and `answer(query:limit:)`, and filters
/// `update(items:)`'s input to `visibilityPredicate`'s subset.
///
/// A caller can also give a second searcher in `.retrieval` mode, the
/// retrieval fallback. Then an answer of the selection model that does not
/// decode does not fail the search: the fallback ranks the same query, and
/// the failure goes to the log.
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

    /// The tracer, the metrics factory and the logger of each search.
    ///
    /// A search opens one ``SkillsTracing/SpanName/search`` span, writes one
    /// "enter" record, and records one ``SkillsTracing/MetricName/searchDuration``
    /// value. A failure of `searcher` that the retrieval fallback answered
    /// also writes one record. That record holds a fixed message and the type
    /// name of the error, and never the description of the error: the error
    /// of a selection session can hold the query or the model response (see
    /// the no-content rule of ``SkillsTracing``).
    private let telemetry: SkillsTracing.Telemetry

    /// The message of the record that a fallback writes. It is fixed, thus it
    /// holds no content.
    private static let fallbackMessage: Logging.Logger.Message =
        "The selection tier failed, thus the retrieval rank answers this search."

    /// Creates a `SkillSearchAgent` over an already-configured searcher.
    ///
    /// - Parameters:
    ///   - searcher: The `MetadataSearcher` to wrap, typically seeded with
    ///     `SkillsRegistry.metadata()`'s `visibilityPredicate` subset.
    ///   - retrievalFallback: A searcher in `.retrieval` mode over the same
    ///     subset, which ranks the query when `searcher` throws. Defaults to
    ///     `nil`, which gives every failure of `searcher` to the caller. The
    ///     `SkillsTool.make(registry:model:embedder:followReloads:
    ///     visibilityPredicate:)` factory always gives one.
    ///   - visibilityPredicate: Which catalog entries `update(items:)`
    ///     forwards to `searcher`. Defaults to `SkillMetadata.isModelVisible`,
    ///     the model-facing surface -- a caller presenting a different
    ///     surface (e.g. `SkillsCLI`'s user-facing one) passes
    ///     the matching predicate so a later reload stays on that surface.
    public init(
        searcher: MetadataSearcher<SkillMetadata>,
        retrievalFallback: MetadataSearcher<SkillMetadata>? = nil,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool = { $0.isModelVisible }
    ) {
        self.init(
            searcher: searcher,
            retrievalFallback: retrievalFallback,
            visibilityPredicate: visibilityPredicate,
            telemetry: SkillsTracing.Telemetry())
    }

    /// Creates a `SkillSearchAgent` with explicit telemetry.
    ///
    /// The public initializer calls this one with the default telemetry,
    /// which reads the bootstrapped tracer, the factory of the current task
    /// and a new logger of the label `SkillsTracing.LoggerLabel.search` when
    /// a search starts. A test gives its own tracer, factory or logger, and
    /// reads the records back.
    ///
    /// - Parameters:
    ///   - searcher: The `MetadataSearcher` to wrap.
    ///   - retrievalFallback: A searcher in `.retrieval` mode over the same
    ///     subset, or `nil`.
    ///   - visibilityPredicate: Which catalog entries `update(items:)`
    ///     forwards to `searcher`.
    ///   - telemetry: The tracer, the metrics factory and the logger of each
    ///     search.
    init(
        searcher: MetadataSearcher<SkillMetadata>,
        retrievalFallback: MetadataSearcher<SkillMetadata>?,
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool,
        telemetry: SkillsTracing.Telemetry
    ) {
        self.searcher = searcher
        self.retrievalFallback = retrievalFallback
        self.visibilityPredicate = visibilityPredicate
        self.telemetry = telemetry
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
        try await answer(query: query, limit: limit).matches
    }

    /// Searches the wrapped catalog for `query`, and tells which tier chose
    /// the matches.
    ///
    /// The same search as `search(query:limit:)`, with the same fallback.
    /// A match of the selection tier carries no retrieval signals, and a
    /// match of the retrieval tier always carries them (`Match.signals`).
    /// Thus a non-empty answer of the wrapped searcher whose matches carry no
    /// signals is a selection. An answer of the retrieval fallback is never a
    /// selection.
    ///
    /// The search runs in one ``SkillsTracing/SpanName/search`` span. The
    /// selection tier asks a language model and can wait for a long time,
    /// thus the span also writes one "enter" record when the search starts
    /// (`TracedCall`). The span holds the limit, the number of matches, the
    /// tier and whether the fallback answered, and never the query. A search
    /// that gives an answer records its duration in
    /// ``SkillsTracing/MetricName/searchDuration``, with the tier as its
    /// dimension. A search that throws gives the span the error status and the
    /// type name of the error, and records no duration, because no tier
    /// answered.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: The maximum number of matches to return.
    /// - Returns: At most `limit` matching skills' metadata, best first, and
    ///   whether the selection tier chose them.
    /// - Throws: The same errors as `search(query:limit:)`.
    public func answer(query: String, limit: Int) async throws -> SkillSearchAnswer {
        let clock = ContinuousClock()
        let start = clock.now
        let logger = telemetry.logger(label: SkillsTracing.LoggerLabel.search)
        return try await TracedCall.run(
            SkillsTracing.SpanName.search, tracer: telemetry.tracer, logger: logger,
            attributes: { $0[SkillsTracing.AttributeKey.searchLimit] = limit }
        ) { span in
            let answer = try await rankedAnswer(query: query, limit: limit, span: span, logger: logger)
            record(answer, on: span, duration: start.duration(to: clock.now))
            return answer
        }
    }

    /// Ranks `query` with the wrapped searcher, or with the retrieval
    /// fallback when the wrapped searcher fails, and marks on `span` which of
    /// the two answered.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: The maximum number of matches to return.
    ///   - span: The span of the search.
    ///   - logger: Where a fallback writes its record.
    /// - Returns: The matches, and whether the selection tier chose them.
    /// - Throws: The same errors as `search(query:limit:)`.
    private func rankedAnswer(
        query: String, limit: Int, span: any Span, logger: Logging.Logger
    ) async throws -> SkillSearchAnswer {
        do {
            let matches = try await searcher.search(intent: query, limit: limit)
            let isSelection = !matches.isEmpty && matches.allSatisfy { $0.signals == nil }
            span.attributes[SkillsTracing.AttributeKey.searchFallback] = false
            return SkillSearchAnswer(matches: matches.map(\.item), isSelection: isSelection)
        } catch {
            guard let retrievalFallback, !Self.isCancellation(error) else { throw error }
            let errorType = String(reflecting: type(of: error))
            span.attributes[SkillsTracing.AttributeKey.searchFallback] = true
            span.attributes[SkillsTracing.AttributeKey.errorType] = errorType
            logger.notice(Self.fallbackMessage, metadata: [SkillsTracing.MetadataKey.errorType: "\(errorType)"])
            let matches = try await retrievalFallback.search(intent: query, limit: limit)
            return SkillSearchAnswer(matches: matches.map(\.item), isSelection: false)
        }
    }

    /// Records the outcome of one search: the number of matches and the tier
    /// on `span`, and `duration` in the timer of that tier.
    ///
    /// - Parameters:
    ///   - answer: The answer of the search.
    ///   - span: The span of the search.
    ///   - duration: The time from the start of the search to the answer.
    private func record(_ answer: SkillSearchAnswer, on span: any Span, duration: Duration) {
        let tier: SkillsTracing.SearchTier = answer.isSelection ? .selection : .retrieval
        span.attributes[SkillsTracing.AttributeKey.searchResultCount] = answer.matches.count
        span.attributes[SkillsTracing.AttributeKey.searchTier] = tier.rawValue
        telemetry.recordSearchDuration(duration, tier: tier)
    }

    /// Hot-reloads the wrapped searcher's catalog, and the retrieval
    /// fallback's catalog, from `items`, forwarding only
    /// `visibilityPredicate`'s subset.
    ///
    /// - Parameter items: The catalog's refreshed metadata rows, in
    ///   first-seen-wins duplicate-id order -- typically a `SkillsRegistry`
    ///   reload's full, unfiltered `metadata()` list.
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
