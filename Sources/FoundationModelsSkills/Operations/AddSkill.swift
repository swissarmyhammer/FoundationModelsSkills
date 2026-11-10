import FoundationModels
import Operations

/// Makes a new skill: the folder `<root>/<id>/` and its `SKILL.md`, in the
/// user layer or the project layer.
///
/// The write goes to `SkillWriter.add(name:skillMarkdown:layer:)`, which
/// checks the name and the file, writes the file, and reloads the registry.
/// Thus `use skill` of the new id gives its body in the same session. A
/// refused write changes no file and gives a corrective message. No gate
/// stands in front of the write.
public struct AddSkill: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: one sentence that names the skill, the
    /// layer and the path, or a corrective message.
    public typealias Output = SkillWriteAnswer

    /// The id of the new skill: the name of its folder.
    public var id: String

    /// The full text of the `SKILL.md`.
    public var content: String

    /// The layer to write, `user` or `project`; `nil` is `user`.
    public var layer: String?

    /// Creates an `AddSkill` operation by directly assigning its parameters,
    /// bypassing `GeneratedContent` decoding.
    ///
    /// - Parameters:
    ///   - id: The id of the new skill.
    ///   - content: The full text of the `SKILL.md`.
    ///   - layer: The layer to write; `nil` is `user`.
    public init(id: String, content: String, layer: String? = nil) {
        self.id = id
        self.content = content
        self.layer = layer
    }

    /// The action this operation performs: `"add"`.
    public static let verb = "add"

    /// The resource this operation acts on: `"skill"`.
    public static let noun = skillOperationNoun

    /// A human- and model-facing summary of what this operation does.
    public static let operationDescription = "Make a new skill. Give the id and the full text of its `SKILL.md`."

    /// This operation's parameters, as the resolver and schema fusion need
    /// them: `id` and `content` (required), `layer` (optional).
    public static let parameterMetadata: [ParamMeta] = [
        ParamMeta(
            name: SkillWriteSupport.idKey, type: .string, required: true,
            description: "The id of the new skill: the name of its folder."),
        SkillWriteSupport.contentParameter,
        SkillWriteSupport.layerParameter,
    ]

    /// The sentence of a successful `add skill`.
    private static let sentence = SkillWriteSupport.Sentence(action: "Added", preposition: "to")

    /// Decodes an `AddSkill` from a resolved `GeneratedContent` payload.
    ///
    /// - Parameter content: The payload to decode, already resolved to this
    ///   operation's canonical parameter names.
    /// - Throws: Whatever `content.value(_:forProperty:)` throws for a
    ///   missing or mistyped field.
    public init(_ content: GeneratedContent) throws {
        id = try content.value(String.self, forProperty: SkillWriteSupport.idKey)
        self.content = try content.value(String.self, forProperty: SkillWriteSupport.contentKey)
        layer = try content.value(String?.self, forProperty: SkillWriteSupport.layerKey)
    }

    /// This operation's parameters re-encoded as `GeneratedContent`, e.g. for
    /// the CLI driver's round trip back to the model-facing payload shape.
    public var generatedContent: GeneratedContent {
        GeneratedContentBuilder.make(
            required: [(SkillWriteSupport.idKey, id), (SkillWriteSupport.contentKey, content)],
            optional: [(SkillWriteSupport.layerKey, layer)])
    }

    /// Writes the new skill, or returns a corrective message.
    ///
    /// - Parameter context: The shared context that gives the registry.
    /// - Returns: `.success(_:)` with the sentence; `.corrective(_:)` for a
    ///   bad layer, or with the corrective of `SkillWriter`.
    /// - Throws: Whatever the file system throws when it writes the skill.
    public func execute(in context: SkillsToolContext) async throws -> SkillWriteAnswer {
        try SkillWriteSupport.answer(layerName: layer, context: context, sentence: Self.sentence) { writer, layer in
            try writer.add(name: id, skillMarkdown: content, layer: layer)
        }
    }
}
