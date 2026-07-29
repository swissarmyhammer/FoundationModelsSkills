import Foundation
import FoundationModels
import Operations

/// The outcome of a `use skill` operation: either the rendered body or a
/// corrective message (plan.md §7).
///
/// An unusable id (unknown, stale, or model-hidden) or a missing required
/// argument is the two conditions `UseSkill.execute(in:)` fails
/// correctively on.
public typealias UseSkillOutput = CorrectiveOutcome<UseSkillResult>

/// Renders and returns a skill's body by id, substituting the given
/// arguments (plan.md §5, §7).
///
/// Dereferences the *live* registry at dispatch time -- via `SkillsRegistry`'s
/// shared, atomically-swappable catalog storage -- so hot-reload between
/// turns is invisible to this operation: an id that only just appeared (or
/// disappeared) is resolved correctly on the very next dispatch. An
/// unknown, stale, or model-hidden id and a missing required argument both
/// return a corrective message rather than throwing (decision #22); extra
/// trailing arguments ride the §5 `ARGUMENTS:` auto-append and never fail.
public struct UseSkill: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: the rendered body, or a corrective message.
    public typealias Output = UseSkillOutput

    /// The skill id to use -- the directory name.
    ///
    /// Matched case-sensitively against the catalog (`$0.id == id`), unlike
    /// `ListSkill`'s deliberately case-insensitive `filter`: `filter` is a
    /// fuzzy discovery aid, but `id` names a specific catalog entry, and
    /// every id agentskills.io validation accepts is already
    /// lowercase-`[a-z0-9-]`-only (plan.md §4) -- there is no legitimate
    /// case-variant id to match loosely, so a mismatched-case `id` falls
    /// into the same "unusable id" corrective as an unknown one, which is
    /// itself actionable feedback.
    public var id: String

    /// Positional arguments substituted into the rendered body (plan.md §5).
    public var arguments: [String]?

    /// Creates a `UseSkill` operation by directly assigning its parameters,
    /// bypassing `GeneratedContent` decoding.
    ///
    /// - Parameters:
    ///   - id: The skill id to use.
    ///   - arguments: Positional arguments substituted into the rendered
    ///     body.
    public init(id: String, arguments: [String]? = nil) {
        self.id = id
        self.arguments = arguments
    }

    /// The action this operation performs: `"use"`.
    public static let verb = "use"

    /// The resource this operation acts on: `"skill"`.
    public static let noun = skillOperationNoun

    /// A human- and model-facing summary of what this operation does.
    public static let operationDescription =
        "Render and return a skill's body by id, substituting the given arguments."

    /// This operation's parameters, as the resolver and schema fusion need
    /// them: `id` (required) and `arguments` (optional).
    public static let parameterMetadata: [ParamMeta] = [
        ParamMeta(name: idKey, type: .string, required: true, description: "The skill id to use."),
        ParamMeta(
            name: argumentsKey, type: .array(of: .string), required: false,
            description: "Positional arguments substituted into the rendered body."),
    ]

    /// The `GeneratedContent` property name for `id`.
    ///
    /// The single source of truth shared by `parameterMetadata`, the
    /// decoding `init`, and `generatedContent`, so the three can never drift
    /// out of sync.
    private static let idKey = "id"

    /// The `GeneratedContent` property name for `arguments`.
    ///
    /// The single source of truth shared by `parameterMetadata`, the
    /// decoding `init`, and `generatedContent`, so the three can never drift
    /// out of sync.
    private static let argumentsKey = "arguments"

    /// Decodes a `UseSkill` from a resolved `GeneratedContent` payload.
    ///
    /// - Parameter content: The payload to decode, already resolved to this
    ///   operation's canonical parameter names.
    /// - Throws: Whatever `content.value(_:forProperty:)` throws for a
    ///   missing or mistyped `id`.
    public init(_ content: GeneratedContent) throws {
        id = try content.value(String.self, forProperty: Self.idKey)
        arguments = try? content.value([String].self, forProperty: Self.argumentsKey)
    }

    /// This operation's parameters re-encoded as `GeneratedContent`, e.g. for
    /// the CLI driver's round trip back to the model-facing payload shape.
    public var generatedContent: GeneratedContent {
        GeneratedContentBuilder.make(
            requiredKey: Self.idKey, requiredValue: id, optionalKey: Self.argumentsKey, optionalValue: arguments)
    }

    /// Renders the skill named by `id` with `arguments`, or returns a
    /// corrective message.
    ///
    /// - Parameter context: The shared context supplying the live registry
    ///   and which entries `context.visibilityPredicate` accepts.
    /// - Returns: `.success(_:)` carrying the rendered body on success;
    ///   `.corrective(_:)` for an unusable id or a missing required
    ///   argument.
    /// - Throws: Nothing recoverable; the signature carries `throws` to
    ///   satisfy the `OperationDefinition` protocol requirement. Rethrows
    ///   whatever `SkillsRegistry.call(id:arguments:)` throws other than
    ///   `UnknownSkillError` -- a genuinely fatal render-pipeline failure
    ///   the host app must handle, not a corrective one.
    public func execute(in context: SkillsToolContext) async throws -> UseSkillOutput {
        let catalog = context.registry.metadata()
        guard let entry = catalog.first(where: { $0.id == id }), context.visibilityPredicate(entry) else {
            return .corrective(
                Self.unusableIDMessage(id: id, catalog: catalog, visibilityPredicate: context.visibilityPredicate))
        }

        let supplied = arguments ?? []
        if let missingParameterName = Self.firstMissingRequiredParameterName(
            parameters: entry.parameters, suppliedCount: supplied.count)
        {
            return .corrective(Self.missingArgumentMessage(name: missingParameterName))
        }

        do {
            let body = try context.registry.call(id: id, arguments: supplied)
            return .success(UseSkillResult(id: id, body: body))
        } catch is UnknownSkillError {
            // The live catalog changed between the lookup above and this
            // call (a race with a hot reload) -- report it the same way as
            // an id that was already unusable at lookup time.
            return .corrective(
                Self.unusableIDMessage(id: id, catalog: catalog, visibilityPredicate: context.visibilityPredicate))
        }
    }

    // MARK: - Unusable id (unknown, stale, or not visible on this surface)

    /// The corrective message for an id that is unknown, stale, or not
    /// visible on the calling context's surface, carrying the current
    /// usable id list (decision #22).
    ///
    /// - Parameters:
    ///   - id: The id that could not be used.
    ///   - catalog: The full catalog snapshot to derive the current usable
    ///     id list from.
    ///   - visibilityPredicate: Which catalog entries count as usable on the
    ///     calling context's surface.
    /// - Returns: The corrective message.
    private static func unusableIDMessage(
        id: String, catalog: [SkillMetadata], visibilityPredicate: (SkillMetadata) -> Bool
    ) -> String {
        let prefix = "The skill id `\(id)` is not currently usable"
        let validIDs = catalog.filter(visibilityPredicate).map(\.id).sorted()
        guard !validIDs.isEmpty else {
            return "\(prefix), and no skills are currently usable."
        }
        return "\(prefix). Currently usable ids: \(validIDs.joined(separator: ", "))."
    }

    // MARK: - Missing required argument (plan.md §6.1)

    /// The corrective message naming a missing required argument.
    ///
    /// - Parameter name: The missing parameter's name.
    /// - Returns: The corrective message.
    private static func missingArgumentMessage(name: String) -> String {
        "Missing required argument `\(name)` for this skill."
    }

    /// The name of the first required parameter `suppliedCount` doesn't
    /// cover, or `nil` when every required parameter has a value.
    ///
    /// Reads the required/optional axis back out of each rendered
    /// placeholder summary (plan.md §6.1 grammar: `<x>` required, `[x]`
    /// optional, a bare unbracketed hint token also required) --
    /// `SkillMetadata.parameters` carries only the display placeholder, not
    /// the structured `SkillParameter.required` flag, so this is a
    /// best-effort inverse of `SkillsRegistry`'s own placeholder synthesis.
    /// The one case this can misread as optional is a skill whose own
    /// `argument-hint:` text happens not to use bracket syntax at all;
    /// harmless in practice, since the render pipeline still substitutes
    /// whatever was supplied.
    ///
    /// - Parameters:
    ///   - parameters: The target skill's parameter placeholder summaries,
    ///     in position order.
    ///   - suppliedCount: The number of arguments actually supplied.
    /// - Returns: The first missing required parameter's name, or `nil`.
    private static func firstMissingRequiredParameterName(parameters: [String], suppliedCount: Int) -> String? {
        for (position, placeholder) in parameters.enumerated() where position >= suppliedCount {
            guard placeholder.first != Self.optionalPlaceholderOpen else { continue }
            return Self.parameterName(fromPlaceholder: placeholder)
        }
        return nil
    }

    // MARK: - Placeholder grammar (plan.md §6.1)

    /// The bracket opening a required placeholder, e.g. the `<` in `<message>`.
    private static let requiredPlaceholderOpen: Character = "<"

    /// The bracket closing a required placeholder, e.g. the `>` in `<message>`.
    private static let requiredPlaceholderClose: Character = ">"

    /// The bracket opening an optional placeholder, e.g. the `[` in `[env]`.
    private static let optionalPlaceholderOpen: Character = "["

    /// The bracket closing an optional placeholder, e.g. the `]` in `[env]`.
    private static let optionalPlaceholderClose: Character = "]"

    /// The trailing marker of a variadic placeholder, e.g. the `...` in `<files...>`.
    private static let variadicPlaceholderSuffix = "..."

    /// Strips a placeholder summary's enclosing bracket and trailing
    /// ellipsis to recover its bare name.
    ///
    /// - Parameter placeholder: The placeholder summary, e.g. `"<message>"`,
    ///   `"[env]"`, or `"<files...>"`.
    /// - Returns: The bare parameter name, e.g. `"message"`, `"env"`,
    ///   `"files"`.
    private static func parameterName(fromPlaceholder placeholder: String) -> String {
        var inner = Substring(placeholder)
        let openBrackets: Set<Character> = [Self.requiredPlaceholderOpen, Self.optionalPlaceholderOpen]
        let closeBrackets: Set<Character> = [Self.requiredPlaceholderClose, Self.optionalPlaceholderClose]
        if let first = inner.first, let last = inner.last, openBrackets.contains(first), closeBrackets.contains(last)
        {
            inner = inner.dropFirst().dropLast()
        }
        if inner.hasSuffix(Self.variadicPlaceholderSuffix) {
            inner = inner.dropLast(Self.variadicPlaceholderSuffix.count)
        }
        return String(inner)
    }
}
