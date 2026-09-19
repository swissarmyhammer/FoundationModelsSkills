import Foundation
import FoundationModels
import Operations

/// The operations of the fused `skills` tool whose answer the model reads as
/// plain text, not as JSON.
///
/// The `Operations` runtime encodes the output of each operation as JSON.
/// The output of `use skill` is one string, the rendered body or a
/// corrective sentence, thus its JSON is a quoted string with escapes. The
/// model must read the body as a procedure, thus `SkillsCatalogTool` gives
/// it the decoded text.
///
/// To find the payloads of these operations, this type holds a second
/// `OperationTool` over one marker for each operation, with the resolver of
/// the fused tool. Thus a payload matches with the same rules as the real
/// dispatch: the verb aliases, the "noun verb" order, and the separators.
/// A marker has no parameters and does nothing, thus the match never runs
/// an operation and never counts against the retry cap of the fused tool.
internal struct PlainTextOperations: Sendable {
    /// The tool that resolves a payload against the markers only.
    private let matcher: OperationTool<PlainTextMarkerContext>

    /// Builds the matcher over the operations whose answer is plain text.
    ///
    /// - Parameter resolver: The resolver of the fused tool.
    /// - Throws: Whatever `OperationTool.init` throws for the markers.
    internal init(resolver: OperationResolver) throws {
        matcher = try OperationTool(
            name: Self.matcherName,
            description: Self.matcherName,
            context: PlainTextMarkerContext(),
            operations: [AnyOperation(PlainTextMarker<UseSkill>.self)],
            resolver: resolver
        )
    }

    /// Gives the answer that the model reads for `arguments`.
    ///
    /// - Parameters:
    ///   - answer: The answer of the fused tool for `arguments`.
    ///   - arguments: The payload that the fused tool dispatched.
    /// - Returns: The decoded text when `arguments` names a plain-text
    ///   operation and `answer` is one JSON string. Otherwise `answer` as it
    ///   is: the JSON of another operation, or a resolver corrective, which
    ///   is plain text already.
    internal func text(of answer: String, for arguments: GeneratedContent) async -> String {
        guard await isPlainTextOperation(arguments), let text = Self.decodedString(from: answer) else {
            return answer
        }
        return text
    }

    /// Whether `arguments` resolves to an operation whose answer is plain
    /// text.
    ///
    /// - Parameter arguments: The payload that the fused tool dispatched.
    /// - Returns: `true` when a marker matches the payload.
    private func isPlainTextOperation(_ arguments: GeneratedContent) async -> Bool {
        do {
            _ = try await matcher.perform(arguments)
            return true
        } catch {
            // `perform` throws `OperationError.unknownOperation` for each
            // payload that no marker matches. A marker has no parameters and
            // decodes each payload, thus no other error can come here.
            return false
        }
    }

    /// Decodes `json` when it is one JSON string.
    ///
    /// - Parameter json: The answer of the fused tool.
    /// - Returns: The string value, or `nil` when `json` is not one JSON
    ///   string, for example a plain resolver corrective.
    private static func decodedString(from json: String) -> String? {
        try? JSONDecoder().decode(String.self, from: Data(json.utf8))
    }

    /// The name and the description of the matcher tool. No model and no
    /// host sees the matcher.
    private static let matcherName = "plain-text-operations"
}

/// The context of a `PlainTextMarker`: nothing, because a marker does no
/// work.
internal struct PlainTextMarkerContext: Sendable {}

/// A marker with the verb and the noun of `Target`, no parameters, and no
/// work.
///
/// `PlainTextOperations` resolves a payload against markers to find the
/// operation that the payload names, and it never runs `Target`.
internal struct PlainTextMarker<Target: OperationDefinition>: OperationDefinition {
    /// A marker does no work, thus it needs no context.
    internal typealias Context = PlainTextMarkerContext

    /// The verb of `Target`.
    internal static var verb: String { Target.verb }

    /// The noun of `Target`.
    internal static var noun: String { Target.noun }

    /// The description of `Target`.
    internal static var operationDescription: String { Target.operationDescription }

    /// No parameters, thus the resolver never reports a missing parameter
    /// for a marker.
    internal static var parameterMetadata: [ParamMeta] { [] }

    /// Creates a marker from any payload. A marker reads no field.
    ///
    /// - Parameter content: The payload, which the marker does not read.
    internal init(_ content: GeneratedContent) {}

    /// An empty payload, because a marker has no parameters.
    internal var generatedContent: GeneratedContent {
        GeneratedContent(properties: [:])
    }

    /// Does nothing.
    ///
    /// - Parameter context: The empty context.
    /// - Returns: `true`, a value with no meaning.
    internal func execute(in context: PlainTextMarkerContext) async -> Bool {
        true
    }
}
