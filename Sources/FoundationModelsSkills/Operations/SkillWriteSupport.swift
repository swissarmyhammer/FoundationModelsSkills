import Operations

/// The outcome of a write operation of the `skills` tool (`add skill`,
/// `edit skill`, `remove skill`): one plain-text sentence that names the
/// skill, the layer and the path, or a corrective message.
///
/// Both cases encode as one JSON string, and `SkillsCatalogTool` gives the
/// model that string as plain text (`PlainTextOperations`).
public typealias SkillWriteAnswer = CorrectiveOutcome<String>

/// The parts that `AddSkill`, `EditSkill` and `RemoveSkill` share: the
/// `layer` parameter, the `content` parameter, the check of the layer name,
/// and the sentence of a successful write.
///
/// Each write goes to `SkillWriter`. This type only reads the `layer` value
/// and turns the outcome of the writer into the answer of the tool.
internal enum SkillWriteSupport {
    /// The `GeneratedContent` property name for `id`.
    internal static let idKey = "id"

    /// The `GeneratedContent` property name for `content`.
    internal static let contentKey = "content"

    /// The `GeneratedContent` property name for `layer`.
    internal static let layerKey = "layer"

    /// The guide text of `layer`.
    ///
    /// The words are the same as the `layer` option of the `agents` tool
    /// (AG-9, FoundationModelsAgents), with `.skills` in place of `.agents`.
    /// When these words change, tell foundationmodelsagents-d7, so that the
    /// agents tool changes to match.
    internal static let layerGuide =
        "Optional. Where to write: user (the user folder, for all projects) or project "
        + "(the .skills folder of this project). Leave it out for user."

    /// The optional `layer` parameter of each write operation.
    internal static let layerParameter = ParamMeta(
        name: layerKey, type: .string, required: false, description: layerGuide)

    /// The required `content` parameter of `add skill` and `edit skill`.
    ///
    /// `add skill` declares `content` first, thus this text is the text of
    /// the fused `content` field. The text is correct for the two
    /// operations.
    internal static let contentParameter = ParamMeta(
        name: contentKey, type: .string, required: true,
        description: "The full new text of the file. For `add skill`, the whole `SKILL.md`.")

    /// The sentence of a successful write, for example
    /// ``Added the skill `review` to the user layer: `/path/review/SKILL.md`.``
    internal struct Sentence: Sendable {
        /// The first word of the sentence: what the write did.
        internal let action: String

        /// The word between the skill and the layer.
        internal let preposition: String

        /// The sentence for `result`.
        ///
        /// - Parameter result: What the write changed.
        /// - Returns: One sentence that names the skill, the layer and the
        ///   path.
        internal func text(for result: SkillWriteResult) -> String {
            "\(action) the skill `\(result.name)` \(preposition) the \(result.layer.rawValue) layer: `\(result.path)`."
        }
    }

    /// Reads `layerName`, runs `write` with a writer of the registry of
    /// `context`, and gives the answer of the tool.
    ///
    /// - Parameters:
    ///   - layerName: The `layer` value of the call, or `nil` when the call
    ///     names no layer. `nil` is ``SkillWriteLayer/default``.
    ///   - context: The shared context that gives the registry.
    ///   - sentence: The sentence of a successful write.
    ///   - write: The write, with the writer and the layer to write.
    /// - Returns: `.success(_:)` with the sentence; `.corrective(_:)` for a
    ///   layer name that is not a writable layer, or with the corrective of
    ///   the writer.
    /// - Throws: Whatever `write` throws: a failure of the file system.
    internal static func answer(
        layerName: String?, context: SkillsToolContext, sentence: Sentence,
        write: (SkillWriter, SkillWriteLayer) throws -> SkillWriteOutcome
    ) rethrows -> SkillWriteAnswer {
        let name = layerName ?? SkillWriteLayer.default.rawValue
        guard let layer = SkillWriteLayer(rawValue: name) else {
            return .corrective(invalidLayerMessage(name))
        }
        switch try write(SkillWriter(registry: context.registry), layer) {
        case .success(let result):
            return .success(sentence.text(for: result))
        case .corrective(let message):
            return .corrective(message)
        }
    }

    /// The corrective message for a `layer` value that is not a writable
    /// layer.
    ///
    /// - Parameter name: The refused value.
    /// - Returns: The message, which names each writable layer and the
    ///   default.
    private static func invalidLayerMessage(_ name: String) -> String {
        let layers = SkillWriteLayer.allCases.map { "`\($0.rawValue)`" }.joined(separator: " or ")
        return "The layer `\(name)` is not valid. Give \(layers), or leave it out for "
            + "`\(SkillWriteLayer.default.rawValue)`."
    }
}
