import Foundation
import FoundationModels
import Operations

/// Lists the calling context's visible skill catalog, optionally filtered
/// (plan.md §7).
///
/// The answer is plain text: one `- <id>: <description>` line for each skill
/// in catalog order, and then the same load instruction as `search skill`
/// (`SkillCatalogText`). Never fails correctively: a `filter` matching
/// nothing gives the one line "No skill matches this filter.", not an error.
/// Reads the live registry's rendered metadata directly -- no session, no
/// ranking, no tokens. Which entries count as visible is
/// `context.visibilityPredicate`'s call, not this operation's -- model
/// dispatch and `SkillsCLI` supply different predicates over the same
/// registry (plan.md §7.2).
public struct ListSkill: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: the plain text of the matching skills,
    /// always a success. It encodes as one JSON string, and
    /// `SkillsCatalogTool` gives the model that string as plain text.
    public typealias Output = String

    /// A case-insensitive substring to match against a skill's id or
    /// description; `nil` or blank lists the whole catalog.
    public var filter: String?

    /// Creates a `ListSkill` operation by directly assigning its parameters,
    /// bypassing `GeneratedContent` decoding.
    ///
    /// - Parameter filter: A case-insensitive substring to match against a
    ///   skill's id or description; `nil` or blank lists the whole catalog.
    public init(filter: String? = nil) {
        self.filter = filter
    }

    /// The action this operation performs: `"list"`.
    public static let verb = "list"

    /// The resource this operation acts on: `"skill"`.
    public static let noun = skillOperationNoun

    /// A human- and model-facing summary of what this operation does.
    ///
    /// It says what the model gets: each skill with its description. The
    /// `filter` parameter describes the filter.
    public static let operationDescription = "List each skill with its description."

    /// This operation's parameters, as the resolver and schema fusion need
    /// them: an optional `filter`.
    public static let parameterMetadata: [ParamMeta] = [
        ParamMeta(
            name: filterKey, type: .string, required: false,
            description: "Case-insensitive substring to match against a skill's id or description.")
    ]

    /// The `GeneratedContent` property name for `filter`.
    ///
    /// The single source of truth shared by `parameterMetadata`, the
    /// decoding `init`, and `generatedContent`, so the three can never drift
    /// out of sync.
    private static let filterKey = "filter"

    /// Decodes a `ListSkill` from a resolved `GeneratedContent` payload.
    ///
    /// - Parameter content: The payload to decode, already resolved to this
    ///   operation's canonical parameter names.
    /// - Throws: Whatever `content.value(_:forProperty:)` throws for a
    ///   mistyped `filter`.
    public init(_ content: GeneratedContent) throws {
        filter = try content.value(String?.self, forProperty: Self.filterKey)
    }

    /// This operation's parameters re-encoded as `GeneratedContent`, e.g. for
    /// the CLI driver's round trip back to the model-facing payload shape.
    public var generatedContent: GeneratedContent {
        guard let filter else { return GeneratedContent(properties: [:]) }
        return GeneratedContent(properties: [Self.filterKey: filter])
    }

    /// Lists `context`'s visible catalog, filtered by `filter` when present.
    ///
    /// - Parameter context: The shared context supplying the registry and
    ///   which entries `context.visibilityPredicate` accepts.
    /// - Returns: The plain text of the matching skills in catalog order,
    ///   with the load instruction. With no match, one line: "No skill
    ///   matches this filter." for a filter, or "No skills are available."
    ///   with no filter.
    /// - Throws: Nothing; the signature carries `throws` to satisfy the
    ///   `OperationDefinition` protocol requirement.
    public func execute(in context: SkillsToolContext) async throws -> String {
        let visible = context.registry.metadata().filter(context.visibilityPredicate)
        let emptyMessage = Self.isFiltering(filter) ? Self.noMatchMessage : SkillCatalogText.emptyCatalogMessage
        return SkillCatalogText.listing(Self.matching(visible, where: filter), heading: nil, emptyMessage: emptyMessage)
    }

    /// The answer of a filter that matches no visible skill.
    private static let noMatchMessage = "No skill matches this filter."

    /// Whether `filter` narrows the catalog.
    ///
    /// - Parameter filter: The filter, or `nil`.
    /// - Returns: `false` for `nil` or a blank filter, which lists the whole
    ///   catalog.
    private static func isFiltering(_ filter: String?) -> Bool {
        guard let filter else { return false }
        return !filter.isBlank
    }

    /// Filters `catalog` to entries whose id or description contains
    /// `filter`, case-insensitively.
    ///
    /// - Parameters:
    ///   - catalog: The catalog entries to filter, already narrowed to
    ///     `context.visibilityPredicate`'s subset.
    ///   - filter: A case-insensitive substring, or `nil`/blank for no
    ///     filtering.
    /// - Returns: `catalog` unchanged when `filter` is `nil` or blank;
    ///   otherwise only the entries whose id or description contains it.
    private static func matching(_ catalog: [SkillMetadata], where filter: String?) -> [SkillMetadata] {
        guard let filter, isFiltering(filter) else {
            return catalog
        }
        let needle = filter.lowercased()
        return catalog.filter { $0.id.lowercased().contains(needle) || $0.description.lowercased().contains(needle) }
    }
}
