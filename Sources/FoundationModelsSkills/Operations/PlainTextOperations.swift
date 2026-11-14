import Foundation
import FoundationModels
import Operations

/// The operations of the fused `skills` tool whose answer the model reads as
/// plain text, not as JSON.
///
/// The `Operations` runtime encodes the output of each operation as JSON.
/// The output of `search skill`, `list skill`, `use skill`, `add skill`,
/// `edit skill`, and `remove skill` is one string: the lines of the skills
/// with the load instruction, the rendered body, the sentence of a write, or
/// a corrective sentence. Thus its JSON is a quoted string with
/// escapes. The model must read the text as text, thus `SkillsCatalogTool`
/// gives it the decoded text.
///
/// To find the operation of a payload, this type holds a second
/// `OperationTool`, the matcher, with the resolver of the fused tool and one
/// marker for each operation of the fused tool. A marker has the verb, the
/// noun, and the parameters of its operation, and its work is to give the op
/// of that operation. Thus the matcher resolves each payload to the same op
/// as the real dispatch does, by every rule of the resolver: the verb
/// aliases, the "noun verb" order, the separators, the unwrap of a lone
/// `arguments` object, and the inference of a missing `op` from the keys,
/// with the `defaultOp` tie-break (^vm78pnz). The answer is plain text when
/// that op is one of `plainTextOpStrings`.
///
/// The markers mirror every operation, not only the plain-text ones, because
/// the inference of an op depends on the whole set: `{"id": …}` fits
/// `use skill` and `list resource`, and `defaultOp` settles it only among the
/// operations that fit. A marker reads no field and does no work, thus the
/// match never runs an operation and never counts against the retry cap of
/// the fused tool.
internal struct PlainTextOperations: Sendable {
    /// The op of each operation whose answer is plain text.
    private static let plainTextOpStrings: Set<String> = [
        SearchSkill.opString,
        ListSkill.opString,
        UseSkill.opString,
        AddSkill.opString,
        EditSkill.opString,
        RemoveSkill.opString,
    ]

    /// The tool that resolves a payload against the markers only.
    private let matcher: OperationTool<PlainTextMarkerContext>

    /// Builds the matcher over one marker for each operation of the fused
    /// tool.
    ///
    /// - Parameters:
    ///   - operations: The operations of the fused tool.
    ///   - resolver: The resolver of the fused tool.
    /// - Throws: Whatever `OperationTool.init` throws for the markers.
    internal init<Context>(mirroring operations: [AnyOperation<Context>], resolver: OperationResolver) throws {
        matcher = try OperationTool(
            name: Self.matcherName,
            description: Self.matcherName,
            context: PlainTextMarkerContext(),
            operations: operations.map { Self.marker(of: $0.definitionType) },
            resolver: resolver
        )
    }

    /// The marker of `target`.
    ///
    /// - Parameter target: The operation type that the marker mirrors.
    /// - Returns: The type-erased marker.
    private static func marker<Target: OperationDefinition>(
        of target: Target.Type
    ) -> AnyOperation<PlainTextMarkerContext> {
        AnyOperation(PlainTextMarker<Target>.self)
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
    /// - Returns: `true` when the matcher resolves the payload to an op of
    ///   `plainTextOpStrings`.
    private func isPlainTextOperation(_ arguments: GeneratedContent) async -> Bool {
        do {
            let opJSON = try await matcher.perform(arguments)
            return Self.decodedString(from: opJSON).map(Self.plainTextOpStrings.contains) ?? false
        } catch {
            // `perform` throws `OperationError.unknownOperation` for a
            // payload that resolves to no operation, and
            // `OperationError.missingRequired` for a payload that lacks a
            // required parameter. The fused tool answers each one with a
            // corrective, which is plain text already. A marker decodes each
            // payload and does no work, thus no other error can come here.
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

/// A marker with the verb, the noun, and the parameters of `Target`, whose
/// work is to give the op of `Target`.
///
/// `PlainTextOperations` resolves a payload against markers to find the
/// operation that the payload names or that its keys fit, and it never runs
/// `Target`.
internal struct PlainTextMarker<Target: OperationDefinition>: OperationDefinition {
    /// A marker does no work, thus it needs no context.
    internal typealias Context = PlainTextMarkerContext

    /// The verb of `Target`.
    internal static var verb: String { Target.verb }

    /// The noun of `Target`.
    internal static var noun: String { Target.noun }

    /// The description of `Target`.
    internal static var operationDescription: String { Target.operationDescription }

    /// The parameters of `Target`, thus the resolver infers a missing `op`
    /// over the markers as it does over the operations, and reports the same
    /// missing parameters.
    internal static var parameterMetadata: [ParamMeta] { Target.parameterMetadata }

    /// Creates a marker from any payload. A marker reads no field.
    ///
    /// - Parameter content: The payload, which the marker does not read.
    internal init(_ content: GeneratedContent) {}

    /// An empty payload, because a marker stores no field.
    internal var generatedContent: GeneratedContent {
        GeneratedContent(properties: [:])
    }

    /// Gives the op of `Target`.
    ///
    /// - Parameter context: The empty context.
    /// - Returns: `Target.opString`, the op that the payload resolved to.
    internal func execute(in context: PlainTextMarkerContext) async -> String {
        Target.opString
    }
}
