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

/// Searches the model-visible skill catalog by query, ranked best match
/// first (plan.md §7, decision #26).
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
        ParamMeta(name: "query", type: .string, required: true, description: "The search query."),
        ParamMeta(
            name: "limit", type: .integer, required: false,
            description: "The maximum number of matches to return. Defaults to 5."),
    ]

    /// The `limit` used when the caller omits one.
    public static let defaultLimit = 5

    /// Decodes a `SearchSkill` from a resolved `GeneratedContent` payload.
    ///
    /// - Parameter content: The payload to decode, already resolved to this
    ///   operation's canonical parameter names.
    /// - Throws: Whatever `content.value(_:forProperty:)` throws for a
    ///   missing or mistyped `query`.
    public init(_ content: GeneratedContent) throws {
        query = try content.value(String.self, forProperty: "query")
        limit = try content.value(Int?.self, forProperty: "limit")
    }

    /// This operation's parameters re-encoded as `GeneratedContent`, e.g. for
    /// the CLI driver's round trip back to the model-facing payload shape.
    public var generatedContent: GeneratedContent {
        GeneratedContentBuilder.make(requiredKey: "query", requiredValue: query, optionalKey: "limit", optionalValue: limit)
    }

    /// Searches the model-visible catalog for `query`, or returns a
    /// corrective for blank input.
    ///
    /// - Parameter context: The shared context supplying the search agent.
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
        let matches = try await context.searchAgent.search(query: query, limit: resolvedLimit)
        let rows = matches.map(SkillRow.init(metadata:))
        return .success(SearchSkillResult(matches: rows, total: rows.count))
    }

    /// The corrective message returned for a blank or whitespace-only
    /// `query`.
    private static let blankQueryMessage = "The `query` parameter must not be blank."
}
