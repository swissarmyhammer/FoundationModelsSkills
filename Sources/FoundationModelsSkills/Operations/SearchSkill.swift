import Foundation
import FoundationModels
import Operations

/// The outcome of a `search skill` operation: either the plain text of the
/// ranked matches or a corrective message (plan.md §7).
///
/// `SearchSkill.execute(in:)` fails correctively on two conditions only: a
/// blank or whitespace-only `query`, and a catalog in which the context's
/// visibility predicate accepts no skill. Every other query -- including one
/// matching nothing -- succeeds.
///
/// Both cases encode as one JSON string, and `SkillsCatalogTool` gives the
/// model that string as plain text.
public typealias SearchSkillOutput = CorrectiveOutcome<String>

/// Searches the calling context's visible skill catalog by query, ranked
/// best match first (plan.md §7, decision #26).
///
/// Delegates to the shared `SkillSearchAgent`; a blank or whitespace-only
/// `query` returns a corrective message instead of searching, since the
/// underlying `MetadataSearcher` has nothing meaningful to rank against
/// empty input. A visible catalog with no skill also returns a corrective
/// message instead of searching, since a search over zero skills has no
/// meaning, and a selection tier would still send the model a prompt.
///
/// The answer is plain text: the query line, one `- <id>: <description>`
/// line for each match in rank order, and the load instruction, which names
/// the exact `use skill` call (`SkillCatalogText`). A query that matches
/// nothing gives the one line "No skill matches this search." The answer
/// holds no body: `use skill` is the one way to get a skill.
public struct SearchSkill: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: the plain text of the ranked matches, or a
    /// corrective message.
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
    /// - Returns: `.success(_:)` carrying the plain text of the ranked
    ///   matches, or `.corrective(_:)` when `query` is blank or when
    ///   `context.visibilityPredicate` accepts no skill in
    ///   `context.registry`.
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

        // Search with a generous, effectively-unbounded limit rather than
        // `limit`, and cap after the visibility filter below. The registry
        // and the search agent's own catalog are independently configurable
        // (`SkillsToolContext`'s own doc comment), thus the agent can rank a
        // skill that `context.visibilityPredicate` hides. A cap before the
        // filter would then give fewer lines than `limit`, although more
        // visible matches exist.
        let answer = try await context.searchAgent.answer(query: query, limit: Self.unboundedSearchLimit)
        let matches = answer.matches.filter(context.visibilityPredicate).prefix(limit ?? Self.defaultLimit)
        return .success(
            SkillCatalogText.listing(Array(matches), heading: Self.heading(for: query), emptyMessage: Self.noMatchMessage))
    }

    /// Gives the first line of a search answer with matches.
    ///
    /// - Parameter query: The query of the search, as the model wrote it.
    /// - Returns: The line that names the query.
    private static func heading(for query: String) -> String {
        "Skills that match \"\(query)\":"
    }

    /// The answer of a search that matches no skill. It gives no load
    /// instruction, thus it never tells the model to load a skill that is
    /// not there.
    private static let noMatchMessage = "No skill matches this search."

    /// The corrective message returned for a blank or whitespace-only
    /// `query`.
    private static let blankQueryMessage = "The `query` parameter must not be blank."

    /// The corrective message returned when `context.visibilityPredicate`
    /// accepts no skill in the registry's catalog.
    private static let emptyCatalogMessage = SkillCatalogText.emptyCatalogMessage

    /// The limit passed to `SkillSearchAgent.answer` to recover every
    /// genuine match before the visibility filter and the `limit` cap.
    ///
    /// Far beyond any realistic skill catalog's size, so this is
    /// effectively "no cap" without risking `Int.max`-scale arithmetic in
    /// the underlying ranker.
    private static let unboundedSearchLimit = 10_000
}
