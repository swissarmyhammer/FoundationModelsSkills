import Foundation
import FoundationModels
import Operations

/// Lists the model-visible skill catalog, optionally filtered (plan.md §7).
///
/// Never fails correctively: a `filter` matching nothing returns an empty
/// `skills` array with `total: 0`, not an error. Reads the live registry's
/// rendered metadata directly -- no session, no ranking, no tokens.
public struct ListSkill: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: the matching rows, always a success.
    public typealias Output = ListSkillResult

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
    public static let operationDescription =
        "List the skill library, optionally filtered by a case-insensitive substring over id and description."

    /// This operation's parameters, as the resolver and schema fusion need
    /// them: an optional `filter`.
    public static let parameterMetadata: [ParamMeta] = [
        ParamMeta(
            name: "filter", type: .string, required: false,
            description: "Case-insensitive substring to match against a skill's id or description.")
    ]

    /// Decodes a `ListSkill` from a resolved `GeneratedContent` payload.
    ///
    /// - Parameter content: The payload to decode, already resolved to this
    ///   operation's canonical parameter names.
    /// - Throws: Whatever `content.value(_:forProperty:)` throws for a
    ///   mistyped `filter`.
    public init(_ content: GeneratedContent) throws {
        filter = try content.value(String?.self, forProperty: "filter")
    }

    /// This operation's parameters re-encoded as `GeneratedContent`, e.g. for
    /// the CLI driver's round trip back to the model-facing payload shape.
    public var generatedContent: GeneratedContent {
        guard let filter else { return GeneratedContent(properties: [:]) }
        return GeneratedContent(properties: ["filter": filter])
    }

    /// Lists the model-visible catalog, filtered by `filter` when present.
    ///
    /// - Parameter context: The shared context supplying the registry.
    /// - Returns: The matching rows in catalog order, with `total` reporting
    ///   their count.
    /// - Throws: Nothing; the signature carries `throws` to satisfy the
    ///   `OperationDefinition` protocol requirement.
    public func execute(in context: SkillsToolContext) async throws -> ListSkillResult {
        let visible = context.registry.metadata().filter(\.isModelVisible)
        let rows = Self.matching(visible, where: filter).map(SkillRow.init(metadata:))
        return ListSkillResult(skills: rows, total: rows.count)
    }

    /// Filters `catalog` to entries whose id or description contains
    /// `filter`, case-insensitively.
    ///
    /// - Parameters:
    ///   - catalog: The model-visible catalog entries to filter.
    ///   - filter: A case-insensitive substring, or `nil`/blank for no
    ///     filtering.
    /// - Returns: `catalog` unchanged when `filter` is `nil` or blank;
    ///   otherwise only the entries whose id or description contains it.
    private static func matching(_ catalog: [SkillMetadata], where filter: String?) -> [SkillMetadata] {
        guard let filter, !filter.isBlank else {
            return catalog
        }
        let needle = filter.lowercased()
        return catalog.filter { $0.id.lowercased().contains(needle) || $0.description.lowercased().contains(needle) }
    }
}
