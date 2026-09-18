import Foundation
import FoundationModels
import Operations
import os

/// The outcome of a `search skill` operation: either the ranked matches or a
/// corrective message (plan.md §7).
///
/// `SearchSkill.execute(in:)` fails correctively on two conditions only: a
/// blank or whitespace-only `query`, and a catalog in which the context's
/// visibility predicate accepts no skill. Every other query -- including one
/// matching nothing -- succeeds with an empty `matches` array.
public typealias SearchSkillOutput = CorrectiveOutcome<SearchSkillResult>

/// Searches the calling context's visible skill catalog by query, ranked
/// best match first (plan.md §7, decision #26).
///
/// Delegates to the shared `SkillSearchAgent`; a blank or whitespace-only
/// `query` returns a corrective message instead of searching, since the
/// underlying `MetadataSearcher` has nothing meaningful to rank against
/// empty input. A visible catalog with no skill also returns a corrective
/// message instead of searching, since a search over zero skills has no
/// meaning, and a selection tier would still send the model a prompt. Every
/// other query -- including one matching nothing -- succeeds with an empty
/// `matches` array.
public struct SearchSkill: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: the ranked matches, or a corrective message.
    public typealias Output = SearchSkillOutput

    /// The search query.
    public var query: String

    /// The maximum number of matches to return; `nil` uses `defaultLimit`.
    public var limit: Int?

    /// Creates a `SearchSkill` operation by directly assigning its
    /// parameters, bypassing `GeneratedContent` decoding.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: The maximum number of matches to return; `nil` uses
    ///     `defaultLimit`.
    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }

    /// The action this operation performs: `"search"`.
    public static let verb = "search"

    /// The resource this operation acts on: `"skill"`.
    public static let noun = skillOperationNoun

    /// A human- and model-facing summary of what this operation does.
    ///
    /// It tells the model what to search for: the kind of work it does
    /// next, not the topic of its task.
    public static let operationDescription =
        "Find the skills for the kind of work that you will do next, for example explore code, "
        + "find callers, or run tests. Search by the kind of work, not by the topic of the task."

    /// This operation's parameters, as the resolver and schema fusion need
    /// them: `query` (required) and `limit` (optional).
    public static let parameterMetadata: [ParamMeta] = [
        ParamMeta(name: queryKey, type: .string, required: true, description: "The search query."),
        ParamMeta(
            name: limitKey, type: .integer, required: false,
            description: "The maximum number of matches to return. Defaults to \(defaultLimit)."),
    ]

    /// The `GeneratedContent` property name for `query`.
    ///
    /// The single source of truth shared by `parameterMetadata`, the
    /// decoding `init`, and `generatedContent`, so the three can never drift
    /// out of sync.
    private static let queryKey = "query"

    /// The `GeneratedContent` property name for `limit`.
    ///
    /// The single source of truth shared by `parameterMetadata`, the
    /// decoding `init`, and `generatedContent`, so the three can never drift
    /// out of sync.
    private static let limitKey = "limit"

    /// The `limit` used when the caller omits one.
    public static let defaultLimit = 5

    /// Decodes a `SearchSkill` from a resolved `GeneratedContent` payload.
    ///
    /// - Parameter content: The payload to decode, already resolved to this
    ///   operation's canonical parameter names.
    /// - Throws: Whatever `content.value(_:forProperty:)` throws for a
    ///   missing or mistyped `query`.
    public init(_ content: GeneratedContent) throws {
        query = try content.value(String.self, forProperty: Self.queryKey)
        limit = try content.value(Int?.self, forProperty: Self.limitKey)
    }

    /// This operation's parameters re-encoded as `GeneratedContent`, e.g. for
    /// the CLI driver's round trip back to the model-facing payload shape.
    public var generatedContent: GeneratedContent {
        GeneratedContentBuilder.make(
            requiredKey: Self.queryKey, requiredValue: query, optionalKey: Self.limitKey, optionalValue: limit)
    }

    /// Searches `context`'s visible catalog for `query`, or returns a
    /// corrective for blank input or an empty visible catalog.
    ///
    /// - Parameter context: The shared context supplying the registry, the
    ///   search agent, and which entries `context.visibilityPredicate`
    ///   accepts.
    /// - Returns: `.success(_:)` carrying the ranked results on success, or
    ///   `.corrective(_:)` when `query` is blank or when
    ///   `context.visibilityPredicate` accepts no skill in
    ///   `context.registry`. Each row carries the `use` call that loads its
    ///   skill, and a result with a match carries a `next` instruction.
    ///   When the selection tier chose the first match, the result also
    ///   carries the body `use skill` renders for it with no argument.
    /// - Throws: Nothing recoverable; the signature carries `throws` to
    ///   satisfy the `OperationDefinition` protocol requirement. Rethrows
    ///   whatever `SkillSearchAgent.answer(query:limit:)` throws -- a
    ///   genuinely fatal search-tier failure the host app must handle, not a
    ///   corrective one. An agent with a retrieval fallback, which the
    ///   `SkillsTool.make` factories build, answers a selection answer that
    ///   does not decode with the retrieval rank, thus that answer does not
    ///   reach this method as an error.
    public func execute(in context: SkillsToolContext) async throws -> SearchSkillOutput {
        guard !query.isBlank else {
            return .corrective(Self.blankQueryMessage)
        }
        // A search over zero skills has no meaning. Stop here, before the
        // search agent: a selection tier over an empty catalog still sends a
        // prompt with no candidate, and the model's prose answer does not
        // decode, thus the call would throw.
        guard context.registry.metadata().contains(where: context.visibilityPredicate) else {
            return .corrective(Self.emptyCatalogMessage)
        }

        let resolvedLimit = limit ?? Self.defaultLimit
        // Search with a generous, effectively-unbounded limit rather than
        // `resolvedLimit` -- `SkillSearchAgent.answer` (via `HybridRanker.
        // topMatches`) only ever returns genuine matches, never zero-score
        // padding, so this recovers the real match count before the
        // `limit` cap, not merely the number of rows displayed. Deriving
        // the bound from `context.registry` instead would be wrong: the
        // registry and the search agent's own catalog are independently
        // configurable (`SkillsToolContext`'s own doc comment), so nothing
        // guarantees they're the same size.
        let answer = try await context.searchAgent.answer(query: query, limit: Self.unboundedSearchLimit)
        let allMatches = answer.matches.filter(context.visibilityPredicate)
        let rows = allMatches.prefix(resolvedLimit).map { SkillRow(metadata: $0, use: SkillUseCall(id: $0.id)) }
        // Only a choice of the selection tier loads a body. A retrieval rank
        // gives the list and the instruction to load a skill.
        let skill: UseSkillResult? =
            if answer.isSelection { await Self.loadedBody(of: rows.first, in: context) } else { nil }
        return .success(SearchSkillResult(matches: Array(rows), total: allMatches.count, skill: skill))
    }

    /// Renders the body of `row` with the same path as `use skill`, called
    /// with no argument.
    ///
    /// A skill with a required argument gets a corrective from `use skill`,
    /// thus it gets no body here, and the model loads it with its `use` call.
    /// A render failure also gives no body: the search itself worked, and
    /// the failure must not fail the `skills` call. The failure goes to the
    /// log, and the same `use` call gives the model the same error.
    ///
    /// - Parameters:
    ///   - row: The first match, or `nil` when there is no match.
    ///   - context: The shared context `use skill` renders against.
    /// - Returns: The rendered body, or `nil` when there is no body to give.
    private static func loadedBody(of row: SkillRow?, in context: SkillsToolContext) async -> UseSkillResult? {
        guard let row else { return nil }
        do {
            guard case .success(let result) = try await UseSkill(id: row.id).execute(in: context) else { return nil }
            return result
        } catch {
            logger.error(
                "The body of the selected skill \(row.id, privacy: .public) did not render, thus the search result carries no body. Cause: \(String(describing: error))"
            )
            return nil
        }
    }

    /// Where a search records a body render that failed.
    private static let logger = Logger(subsystem: "FoundationModelsSkills", category: "SearchSkill")

    /// The corrective message returned for a blank or whitespace-only
    /// `query`.
    private static let blankQueryMessage = "The `query` parameter must not be blank."

    /// The corrective message returned when `context.visibilityPredicate`
    /// accepts no skill in the registry's catalog.
    private static let emptyCatalogMessage = "No skills are available."

    /// The limit passed to `SkillSearchAgent.answer` to recover every
    /// genuine match, not just `resolvedLimit`'s display cap.
    ///
    /// Far beyond any realistic skill catalog's size, so this is
    /// effectively "no cap" without risking `Int.max`-scale arithmetic in
    /// the underlying ranker.
    private static let unboundedSearchLimit = 10_000
}
