import FoundationModels
import Operations

/// Deletes the folder of a skill, with all its files, from the user layer or
/// the project layer.
///
/// The write goes to `SkillWriter.remove(name:layer:)`. A copy of the skill
/// in another layer stays. The writer then reloads the registry. A refused
/// write changes no file and gives a corrective message. No gate stands in
/// front of the write.
public struct RemoveSkill: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: one sentence that names the skill, the
    /// layer and the path, or a corrective message.
    public typealias Output = SkillWriteAnswer

    /// The id of the skill: the name of its folder.
    public var id: String

    /// The layer to write, `user` or `project`; `nil` is `user`.
    public var layer: String?

    /// Creates a `RemoveSkill` operation by directly assigning its
    /// parameters, bypassing `GeneratedContent` decoding.
    ///
    /// - Parameters:
    ///   - id: The id of the skill.
    ///   - layer: The layer to write; `nil` is `user`.
    public init(id: String, layer: String? = nil) {
        self.id = id
        self.layer = layer
    }

    /// The action this operation performs: `"remove"`.
    public static let verb = "remove"

    /// The resource this operation acts on: `"skill"`.
    public static let noun = skillOperationNoun

    /// A human- and model-facing summary of what this operation does.
    public static let operationDescription =
        "Delete a skill and all its files from one layer. A copy in another layer stays."

    /// This operation's parameters, as the resolver and schema fusion need
    /// them: `id` (required), `layer` (optional).
    public static let parameterMetadata: [ParamMeta] = [
        ParamMeta(
            name: SkillWriteSupport.idKey, type: .string, required: true,
            description: "The id of the skill to delete."),
        SkillWriteSupport.layerParameter,
    ]

    /// The sentence of a successful `remove skill`.
    private static let sentence = SkillWriteSupport.Sentence(action: "Removed", preposition: "from")

    /// Decodes a `RemoveSkill` from a resolved `GeneratedContent` payload.
    ///
    /// - Parameter content: The payload to decode, already resolved to this
    ///   operation's canonical parameter names.
    /// - Throws: Whatever `content.value(_:forProperty:)` throws for a
    ///   missing or mistyped field.
    public init(_ content: GeneratedContent) throws {
        id = try content.value(String.self, forProperty: SkillWriteSupport.idKey)
        layer = try content.value(String?.self, forProperty: SkillWriteSupport.layerKey)
    }

    /// This operation's parameters re-encoded as `GeneratedContent`, e.g. for
    /// the CLI driver's round trip back to the model-facing payload shape.
    public var generatedContent: GeneratedContent {
        GeneratedContentBuilder.make(
            requiredKey: SkillWriteSupport.idKey, requiredValue: id, optionalKey: SkillWriteSupport.layerKey,
            optionalValue: layer)
    }

    /// Deletes the skill folder, or returns a corrective message.
    ///
    /// - Parameter context: The shared context that gives the registry.
    /// - Returns: `.success(_:)` with the sentence; `.corrective(_:)` for a
    ///   bad layer, or with the corrective of `SkillWriter`.
    /// - Throws: Whatever the file system throws when it deletes the folder.
    public func execute(in context: SkillsToolContext) async throws -> SkillWriteAnswer {
        try SkillWriteSupport.answer(layerName: layer, context: context, sentence: Self.sentence) { writer, layer in
            try writer.remove(name: id, layer: layer)
        }
    }
}
