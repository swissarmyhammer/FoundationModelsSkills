import Foundation
import FoundationModels
import Operations

/// The outcome of a `search skill` operation: either the ranked matches or a
/// corrective message (plan.md §7).
///
/// A blank or whitespace-only `query` is the one condition
/// `SearchSkill.execute(in:)` fails correctively on; every other query --
/// including one matching nothing -- succeeds with an empty `matches`
/// array.
public typealias SearchSkillOutput = CorrectiveOutcome<SearchSkillResult>

/// Searches the calling context's visible skill catalog by query, ranked
/// best match first (plan.md §7, decision #26).
///
/// Delegates to the shared `SkillSearchAgent`; a blank or whitespace-only
/// `query` returns a corrective message instead of searching, since the
/// underlying `MetadataSearcher` has nothing meaningful to rank against
/// empty input. Every other query -- including one matching nothing --
/// succeeds with an empty `matches` array.
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
    public static let operationDescription =
        "Search the skill library by query, returning ranked matches best-first."

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
    /// corrective for blank input.
    ///
    /// - Parameter context: The shared context supplying the search agent
    ///   and which entries `context.visibilityPredicate` accepts.
    /// - Returns: `.success(_:)` carrying the ranked results on success, or
    ///   `.corrective(_:)` when `query` is blank.
    /// - Throws: Nothing recoverable; the signature carries `throws` to
    ///   satisfy the `OperationDefinition` protocol requirement. Rethrows
    ///   whatever `SkillSearchAgent.search(query:limit:)` throws -- a
    ///   genuinely fatal search-tier failure the host app must handle, not a
    ///   corrective one.
    public func execute(in context: SkillsToolContext) async throws -> SearchSkillOutput {
        guard !query.isBlank else {
            return .corrective(Self.blankQueryMessage)
        }

        let resolvedLimit = limit ?? Self.defaultLimit
        // Search with a generous, effectively-unbounded limit rather than
        // `resolvedLimit` -- `SkillSearchAgent.search` (via `HybridRanker.
        // topMatches`) only ever returns genuine matches, never zero-score
        // padding, so this recovers the real match count before the
        // `limit` cap, not merely the number of rows displayed. Deriving
        // the bound from `context.registry` instead would be wrong: the
        // registry and the search agent's own catalog are independently
        // configurable (`SkillsToolContext`'s own doc comment), so nothing
        // guarantees they're the same size.
        let allMatches = try await context.searchAgent
            .search(query: query, limit: Self.unboundedSearchLimit)
            .filter(context.visibilityPredicate)
        let rows = allMatches.prefix(resolvedLimit).map(SkillRow.init(metadata:))
        return .success(SearchSkillResult(matches: Array(rows), total: allMatches.count))
    }

    /// The corrective message returned for a blank or whitespace-only
    /// `query`.
    private static let blankQueryMessage = "The `query` parameter must not be blank."

    /// The limit passed to `SkillSearchAgent.search` to recover every
    /// genuine match, not just `resolvedLimit`'s display cap.
    ///
    /// Far beyond any realistic skill catalog's size, so this is
    /// effectively "no cap" without risking `Int.max`-scale arithmetic in
    /// the underlying ranker.
    private static let unboundedSearchLimit = 10_000
}
