import FoundationModelsExtras

// The skill mutations of the `skills` endpoint (D190): `addSkill`,
// `updateSkill` and `removeSkill`. Each write goes to `SkillWriter`, the same
// writer as the `add skill`, `edit skill` and `remove skill` operations of the
// `skills` tool. The writer reloads the registry, thus the `changes`
// subscription gives one `SkillChange` for each mutation.

// MARK: - Enums

/// A layer that a mutation of the `skills` endpoint can write.
enum SkillsGraphLayer: String, Codable, CaseIterable, Sendable {
    /// The user layer, for all projects.
    case user = "USER"

    /// The project layer, for this project only.
    case project = "PROJECT"

    /// The layer of `SkillWriter` that this value names.
    var writeLayer: SkillWriteLayer {
        switch self {
        case .user: .user
        case .project: .project
        }
    }

    /// Gives the GraphQL name of a writable layer.
    ///
    /// - Parameter layer: The writable layer.
    init(_ layer: SkillWriteLayer) {
        switch layer {
        case .user: self = .user
        case .project: self = .project
        }
    }
}

// MARK: - Inputs and payloads

/// The one `input` argument of a mutation (rule 7 of EXTRAS-9).
struct SkillsGraphInputArguments<Input: Decodable & Sendable>: Decodable, Sendable {
    /// The `input` object of the mutation.
    let input: Input
}

/// The `input` object of `addSkill`.
struct AddSkillInput: Codable, Sendable {
    /// The id of the new skill: the name of its folder.
    let id: ToolkitID

    /// The description of the new skill.
    let description: String

    /// The Markdown body of the new skill, or `nil` for an empty body.
    let body: String?

    /// The layer to write, or `nil` for the user layer.
    let layer: SkillsGraphLayer?
}

/// The `input` object of `updateSkill`. A field that is `nil` does not
/// change.
struct UpdateSkillInput: Codable, Sendable {
    /// The id of the skill to change.
    let id: ToolkitID

    /// The new description, or `nil` for no change.
    let description: String?

    /// The new Markdown body, or `nil` for no change.
    let body: String?

    /// The layer to write, or `nil` for the writable layer of the highest
    /// precedence that holds the skill.
    let layer: SkillsGraphLayer?
}

/// The `input` object of `removeSkill`.
struct RemoveSkillInput: Codable, Sendable {
    /// The id of the skill to delete.
    let id: ToolkitID

    /// The layer to delete from, or `nil` for the writable layer of the
    /// highest precedence that holds the skill.
    let layer: SkillsGraphLayer?
}

/// The `RemoveSkillPayload` object: what `removeSkill` deleted.
struct RemoveSkillPayload: Codable, Sendable {
    /// The id of the deleted skill.
    let id: ToolkitID

    /// The layer that the mutation deleted the skill from.
    let layer: SkillsGraphLayer

    /// The copy of the skill in another layer that stays, or `nil` when no
    /// copy stays.
    let skill: SkillsGraphSkill?
}

// MARK: - Errors

/// The errors of the skill mutations of the `skills` endpoint. A mutation
/// for an id that no layer holds gives the `NOT_FOUND` of the toolkit.
enum SkillsGraphError: CodedError, Equatable {
    /// `SKILL_EXISTS`: `addSkill` of an id that the layer already holds.
    case skillExists(id: String, layer: SkillWriteLayer)

    /// `SKILL_READ_ONLY`: a change of a skill that only read-only layers
    /// hold.
    case skillReadOnly(id: String)

    /// `INVALID_SKILL`: the writer refused the skill. The message tells why.
    case invalidSkill(message: String)

    /// Each code of this type, for rule 8 of EXTRAS-9.
    static let codes = ["SKILL_EXISTS", "SKILL_READ_ONLY", "INVALID_SKILL"]

    /// The code of the error.
    var code: String {
        switch self {
        case .skillExists: Self.codes[0]
        case .skillReadOnly: Self.codes[1]
        case .invalidSkill: Self.codes[2]
        }
    }

    /// The message of the error: what is wrong, and how to correct the call.
    var message: String {
        switch self {
        case .skillExists(let id, let layer):
            "The skill \"\(id)\" is already in the \(SkillsGraphLayer(layer).rawValue) layer. "
                + "Use updateSkill to change it, or give another id."
        case .skillReadOnly(let id):
            "The skill \"\(id)\" is only in a read-only layer. To change it, use addSkill with the id \"\(id)\" "
                + "and the layer USER or PROJECT: that copy overrides it."
        case .invalidSkill(let message):
            message
        }
    }
}

// MARK: - Resolvers

extension SkillsGraphResolver {
    /// The kind of the id in a `NOT_FOUND` error.
    private static let notFoundKind = "skill"

    /// Resolves `Mutation.addSkill`: makes the folder and the `SKILL.md` of
    /// a new skill.
    ///
    /// - Parameter arguments: The new skill.
    /// - Returns: The skill that the registry gives for the id after the
    ///   write. A copy of a layer with a higher precedence wins.
    /// - Throws: ``SkillsGraphError/skillExists(id:layer:)`` when the layer
    ///   holds the id, ``SkillsGraphError/invalidSkill(message:)`` when the
    ///   writer refuses the skill, or an error of the file system.
    func addSkill(
        context _: SkillsGraphContext, arguments: SkillsGraphInputArguments<AddSkillInput>
    ) async throws -> SkillsGraphSkill? {
        let input = arguments.input
        let id = input.id.text
        let layer = input.layer?.writeLayer ?? .default
        if SkillWriter.isSinglePathComponent(id), holders(of: id).contains(layer.source) {
            throw SkillsGraphError.skillExists(id: id, layer: layer)
        }
        let text = try SkillFileText.make(name: id, description: input.description, body: input.body ?? "")
        try Self.check(try SkillWriter(registry: registry).add(name: id, skillMarkdown: text, layer: layer))
        return skill(id: id)
    }

    /// Resolves `Mutation.updateSkill`: writes a new description, a new
    /// body, or the two, into the `SKILL.md` of a skill.
    ///
    /// - Parameter arguments: The skill and the changes.
    /// - Returns: The skill that the registry gives for the id after the
    ///   write.
    /// - Throws: `NOT_FOUND` when no layer, or not the given layer, holds
    ///   the id, ``SkillsGraphError/skillReadOnly(id:)`` when only read-only
    ///   layers hold it, ``SkillsGraphError/invalidSkill(message:)`` when the
    ///   writer refuses the new file, or an error of the file system.
    func updateSkill(
        context _: SkillsGraphContext, arguments: SkillsGraphInputArguments<UpdateSkillInput>
    ) async throws -> SkillsGraphSkill? {
        let input = arguments.input
        let id = input.id.text
        let layer = try writableLayer(holding: id, requested: input.layer)
        guard input.description != nil || input.body != nil else {
            return skill(id: id)
        }
        try Self.check(
            try SkillWriter(registry: registry).update(
                name: id, description: input.description, body: input.body, layer: layer))
        return skill(id: id)
    }

    /// Resolves `Mutation.removeSkill`: deletes the folder of a skill from
    /// one layer.
    ///
    /// - Parameter arguments: The skill and the layer.
    /// - Returns: The id, the layer, and the copy of the skill that stays.
    /// - Throws: `NOT_FOUND` when no layer, or not the given layer, holds
    ///   the id, ``SkillsGraphError/skillReadOnly(id:)`` when only read-only
    ///   layers hold it, or an error of the file system.
    func removeSkill(
        context _: SkillsGraphContext, arguments: SkillsGraphInputArguments<RemoveSkillInput>
    ) async throws -> RemoveSkillPayload? {
        let input = arguments.input
        let id = input.id.text
        let layer = try writableLayer(holding: id, requested: input.layer)
        try Self.check(try SkillWriter(registry: registry).remove(name: id, layer: layer))
        return RemoveSkillPayload(id: input.id, layer: SkillsGraphLayer(layer), skill: skill(id: id))
    }

    // MARK: - Support

    /// The skill of `id` in the current catalog generation.
    ///
    /// - Parameter id: The id of the skill.
    /// - Returns: The skill, or `nil` when no skill loads for the id.
    private func skill(id: String) -> SkillsGraphSkill? {
        registry.skillContents()[id].map(SkillsGraphSkill.init)
    }

    /// The source of each layer that holds the folder of `id`, lowest
    /// precedence first.
    ///
    /// - Parameter id: The id of the skill: one folder name.
    /// - Returns: The sources.
    private func holders(of id: String) -> [DotfolderStack.Source] {
        DotfolderStack(layers: registry.layers).layerDirectories(id).map(\.source)
    }

    /// The writable layer that a change of `id` writes.
    ///
    /// - Parameters:
    ///   - id: The id of the skill.
    ///   - requested: The layer of the input, or `nil`.
    /// - Returns: `requested` when it holds the skill, or else the writable
    ///   layer of the highest precedence that holds it.
    /// - Throws: `NOT_FOUND` when no layer, or not `requested`, holds the
    ///   id. ``SkillsGraphError/skillReadOnly(id:)`` when only read-only
    ///   layers hold it.
    private func writableLayer(holding id: String, requested: SkillsGraphLayer?) throws -> SkillWriteLayer {
        let holders = SkillWriter.isSinglePathComponent(id) ? holders(of: id) : []
        if let requested {
            guard holders.contains(requested.writeLayer.source) else {
                throw GraphQLToolkitError.notFound(
                    kind: "\(Self.notFoundKind) in the \(requested.rawValue) layer", id: id)
            }
            return requested.writeLayer
        }
        guard !holders.isEmpty else {
            throw GraphQLToolkitError.notFound(kind: Self.notFoundKind, id: id)
        }
        guard let layer = holders.compactMap(SkillWriteLayer.init(source:)).last else {
            throw SkillsGraphError.skillReadOnly(id: id)
        }
        return layer
    }

    /// Throws the corrective of a refused write.
    ///
    /// - Parameter outcome: The outcome of a write of `SkillWriter`.
    /// - Throws: ``SkillsGraphError/invalidSkill(message:)`` with the
    ///   corrective message.
    private static func check(_ outcome: SkillWriteOutcome) throws {
        if case .corrective(let message) = outcome {
            throw SkillsGraphError.invalidSkill(message: message)
        }
    }
}
