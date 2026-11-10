import FoundationModels
import Operations

/// Writes one file of a skill in the user layer or the project layer:
/// `SKILL.md`, or another file of the skill folder.
///
/// The write goes to `SkillWriter.edit(name:path:content:layer:)`. The skill
/// folder must be in the layer, and the path uses the rules of
/// `ReadResource`. A write of `SKILL.md` must be a valid skill file. The
/// writer then reloads the registry. A refused write changes no file and
/// gives a corrective message. No gate stands in front of the write.
public struct EditSkill: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: one sentence that names the skill, the
    /// layer and the path, or a corrective message.
    public typealias Output = SkillWriteAnswer

    /// The id of the skill: the name of its folder.
    public var id: String

    /// The path of the file, relative to the skill folder; `nil` is
    /// `SKILL.md`.
    public var path: String?

    /// The full new text of the file.
    public var content: String

    /// The layer to write, `user` or `project`; `nil` is `user`.
    public var layer: String?

    /// Creates an `EditSkill` operation by directly assigning its
    /// parameters, bypassing `GeneratedContent` decoding.
    ///
    /// - Parameters:
    ///   - id: The id of the skill.
    ///   - path: The path of the file, relative to the skill folder; `nil`
    ///     is `SKILL.md`.
    ///   - content: The full new text of the file.
    ///   - layer: The layer to write; `nil` is `user`.
    public init(id: String, path: String? = nil, content: String, layer: String? = nil) {
        self.id = id
        self.path = path
        self.content = content
        self.layer = layer
    }

    /// The action this operation performs: `"edit"`.
    public static let verb = "edit"

    /// The resource this operation acts on: `"skill"`.
    public static let noun = skillOperationNoun

    /// A human- and model-facing summary of what this operation does.
    public static let operationDescription =
        "Write one file of a skill: `SKILL.md`, or another file of the skill folder. "
        + "The skill must be in the layer that you write."

    /// This operation's parameters, as the resolver and schema fusion need
    /// them: `id` and `content` (required), `path` and `layer` (optional).
    public static let parameterMetadata: [ParamMeta] = [
        ParamMeta(
            name: SkillWriteSupport.idKey, type: .string, required: true,
            description: "The id of the skill to change."),
        ParamMeta(
            name: pathKey, type: .string, required: false,
            description: "The path of the file, relative to the skill folder. Leave it out for `\(defaultPath)`."),
        SkillWriteSupport.contentParameter,
        SkillWriteSupport.layerParameter,
    ]

    /// The `GeneratedContent` property name for `path`.
    private static let pathKey = "path"

    /// The file that a call with no `path` writes: the skill file.
    private static let defaultPath = SkillDiscovery.skillFileName

    /// The sentence of a successful `edit skill`.
    private static let sentence = SkillWriteSupport.Sentence(action: "Edited", preposition: "in")

    /// Decodes an `EditSkill` from a resolved `GeneratedContent` payload.
    ///
    /// - Parameter content: The payload to decode, already resolved to this
    ///   operation's canonical parameter names.
    /// - Throws: Whatever `content.value(_:forProperty:)` throws for a
    ///   missing or mistyped field.
    public init(_ content: GeneratedContent) throws {
        id = try content.value(String.self, forProperty: SkillWriteSupport.idKey)
        path = try content.value(String?.self, forProperty: Self.pathKey)
        self.content = try content.value(String.self, forProperty: SkillWriteSupport.contentKey)
        layer = try content.value(String?.self, forProperty: SkillWriteSupport.layerKey)
    }

    /// This operation's parameters re-encoded as `GeneratedContent`, e.g. for
    /// the CLI driver's round trip back to the model-facing payload shape.
    public var generatedContent: GeneratedContent {
        GeneratedContentBuilder.make(
            required: [(SkillWriteSupport.idKey, id), (SkillWriteSupport.contentKey, content)],
            optional: [(Self.pathKey, path), (SkillWriteSupport.layerKey, layer)])
    }

    /// Writes the file, or returns a corrective message.
    ///
    /// - Parameter context: The shared context that gives the registry.
    /// - Returns: `.success(_:)` with the sentence; `.corrective(_:)` for a
    ///   bad layer, or with the corrective of `SkillWriter`.
    /// - Throws: Whatever the file system throws when it writes the file.
    public func execute(in context: SkillsToolContext) async throws -> SkillWriteAnswer {
        try SkillWriteSupport.answer(layerName: layer, context: context, sentence: Self.sentence) { writer, layer in
            try writer.edit(name: id, path: path ?? Self.defaultPath, content: content, layer: layer)
        }
    }
}
