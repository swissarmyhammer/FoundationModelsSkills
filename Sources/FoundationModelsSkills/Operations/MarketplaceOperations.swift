import FoundationModels
import Marketplace
import Operations

// The marketplace operations of the `skills` tool (D190, D100): `add`,
// `edit`, `remove`, `list` and `show marketplace`. Each one goes to the
// `MarketplaceRegistry` of the context, the same registry as the marketplace
// mutations of the `skills` endpoint. The tool has these operations only when
// the context has a registry. Each answer is one plain text, and each refusal
// of the registry is a corrective message.

/// The answer of a marketplace operation: one plain text, or a corrective
/// message.
public typealias MarketplaceAnswer = CorrectiveOutcome<String>

/// The noun of each marketplace operation.
let marketplaceOperationNoun = "marketplace"

/// Makes a new marketplace at the end of the list.
public struct AddMarketplace: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: one sentence, or a corrective message.
    public typealias Output = MarketplaceAnswer

    /// The fields of the new source.
    public var fields: MarketplaceSourceFields

    /// Creates the operation by directly assigning its fields.
    ///
    /// - Parameter fields: The fields of the new source.
    public init(fields: MarketplaceSourceFields) {
        self.fields = fields
    }

    /// The action this operation performs: `"add"`.
    public static let verb = "add"

    /// The resource this operation acts on: `"marketplace"`.
    public static let noun = marketplaceOperationNoun

    /// A human- and model-facing summary of what this operation does.
    public static let operationDescription =
        "Add a skill marketplace: a git repository of skills. Give its `url`."

    /// This operation's parameters: `url` (required) and the optional
    /// fields of a source.
    public static let parameterMetadata: [ParamMeta] =
        [MarketplaceParameters.url(required: true)] + MarketplaceParameters.sourceFields

    /// Decodes the operation from a resolved payload.
    ///
    /// - Parameter content: The payload to decode.
    /// - Throws: An error of `content.value(_:forProperty:)`.
    public init(_ content: GeneratedContent) throws {
        fields = try MarketplaceParameters.fields(of: content)
    }

    /// This operation's parameters re-encoded as `GeneratedContent`.
    public var generatedContent: GeneratedContent {
        MarketplaceParameters.content(id: nil, fields: fields)
    }

    /// Adds the marketplace, or returns a corrective message.
    ///
    /// - Parameter context: The shared context that gives the registry.
    /// - Returns: The sentence of the add, or a corrective message.
    /// - Throws: An error of the storage of the registry.
    public func execute(in context: SkillsToolContext) async throws -> MarketplaceAnswer {
        try await MarketplaceParameters.answer(in: context) { marketplaces in
            let entry = try await marketplaces.add(fields.newSource())
            return "Added the marketplace `\(entry.id)`: \(entry.source.url)."
        }
    }
}

/// Changes the source of one marketplace, in its place in the list.
public struct EditMarketplace: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: one sentence, or a corrective message.
    public typealias Output = MarketplaceAnswer

    /// The id of the marketplace.
    public var id: String

    /// The changes. A field that is `nil` does not change.
    public var fields: MarketplaceSourceFields

    /// Creates the operation by directly assigning its parameters.
    ///
    /// - Parameters:
    ///   - id: The id of the marketplace.
    ///   - fields: The changes.
    public init(id: String, fields: MarketplaceSourceFields) {
        self.id = id
        self.fields = fields
    }

    /// The action this operation performs: `"edit"`.
    public static let verb = "edit"

    /// The resource this operation acts on: `"marketplace"`.
    public static let noun = marketplaceOperationNoun

    /// A human- and model-facing summary of what this operation does.
    public static let operationDescription =
        "Change a skill marketplace. Give its `id` and only the fields to change. An empty text clears a field."

    /// This operation's parameters: `id` (required) and each optional field.
    public static let parameterMetadata: [ParamMeta] =
        [MarketplaceParameters.id, MarketplaceParameters.url(required: false)] + MarketplaceParameters.sourceFields

    /// Decodes the operation from a resolved payload.
    ///
    /// - Parameter content: The payload to decode.
    /// - Throws: An error of `content.value(_:forProperty:)`.
    public init(_ content: GeneratedContent) throws {
        id = try content.value(String.self, forProperty: MarketplaceParameters.idKey)
        fields = try MarketplaceParameters.fields(of: content)
    }

    /// This operation's parameters re-encoded as `GeneratedContent`.
    public var generatedContent: GeneratedContent {
        MarketplaceParameters.content(id: id, fields: fields)
    }

    /// Changes the marketplace, or returns a corrective message.
    ///
    /// - Parameter context: The shared context that gives the registry.
    /// - Returns: The sentence of the change, or a corrective message.
    /// - Throws: An error of the storage of the registry.
    public func execute(in context: SkillsToolContext) async throws -> MarketplaceAnswer {
        try await MarketplaceParameters.answer(in: context) { marketplaces in
            let entry = try await MarketplaceEdits.update(id: id, with: fields, in: marketplaces)
            let rename = entry.id == id ? "" : " Its id is now `\(entry.id)`."
            return "Edited the marketplace `\(id)`: \(entry.source.url).\(rename)"
        }
    }
}

/// Removes one marketplace from the list.
public struct RemoveMarketplace: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: one sentence, or a corrective message.
    public typealias Output = MarketplaceAnswer

    /// The id of the marketplace.
    public var id: String

    /// Creates the operation by directly assigning its parameter.
    ///
    /// - Parameter id: The id of the marketplace.
    public init(id: String) {
        self.id = id
    }

    /// The action this operation performs: `"remove"`.
    public static let verb = "remove"

    /// The resource this operation acts on: `"marketplace"`.
    public static let noun = marketplaceOperationNoun

    /// A human- and model-facing summary of what this operation does.
    public static let operationDescription = "Remove a skill marketplace from the list. Give its `id`."

    /// This operation's parameter: `id` (required).
    public static let parameterMetadata: [ParamMeta] = [MarketplaceParameters.id]

    /// Decodes the operation from a resolved payload.
    ///
    /// - Parameter content: The payload to decode.
    /// - Throws: An error of `content.value(_:forProperty:)`.
    public init(_ content: GeneratedContent) throws {
        id = try content.value(String.self, forProperty: MarketplaceParameters.idKey)
    }

    /// This operation's parameter re-encoded as `GeneratedContent`.
    public var generatedContent: GeneratedContent {
        GeneratedContent(properties: [MarketplaceParameters.idKey: id])
    }

    /// Removes the marketplace, or returns a corrective message.
    ///
    /// - Parameter context: The shared context that gives the registry.
    /// - Returns: The sentence of the remove, or a corrective message.
    /// - Throws: An error of the storage of the registry.
    public func execute(in context: SkillsToolContext) async throws -> MarketplaceAnswer {
        try await MarketplaceParameters.answer(in: context) { marketplaces in
            let entry = try await marketplaces.remove(id: id)
            return "Removed the marketplace `\(entry.id)`: \(entry.source.url)."
        }
    }
}

/// Lists each marketplace, one line each.
public struct ListMarketplace: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: the lines, or a corrective message.
    public typealias Output = MarketplaceAnswer

    /// Creates the operation. It has no parameter.
    public init() {}

    /// The action this operation performs: `"list"`.
    public static let verb = "list"

    /// The resource this operation acts on: `"marketplace"`.
    public static let noun = marketplaceOperationNoun

    /// A human- and model-facing summary of what this operation does.
    public static let operationDescription = "List each skill marketplace with its id and its url."

    /// This operation has no parameter.
    public static let parameterMetadata: [ParamMeta] = []

    /// Decodes the operation from a resolved payload.
    ///
    /// - Parameter content: The payload, which has no field to read.
    public init(_: GeneratedContent) throws {}

    /// This operation's parameters re-encoded as `GeneratedContent`: none.
    public var generatedContent: GeneratedContent {
        GeneratedContentBuilder.make(required: [], optional: [])
    }

    /// Lists the marketplaces, or returns a corrective message.
    ///
    /// - Parameter context: The shared context that gives the registry.
    /// - Returns: One line for each marketplace, or a text that says the
    ///   list is empty.
    /// - Throws: An error of the storage of the registry.
    public func execute(in context: SkillsToolContext) async throws -> MarketplaceAnswer {
        try await MarketplaceParameters.answer(in: context) { marketplaces in
            let entries = try await marketplaces.marketplaces()
            guard !entries.isEmpty else {
                return "No marketplace is in the list. Use `add marketplace` to add one."
            }
            return entries.map { "- `\($0.id)`: \($0.source.url)" }.joined(separator: "\n")
        }
    }
}

/// Shows each field of one marketplace.
public struct ShowMarketplace: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: the fields, or a corrective message.
    public typealias Output = MarketplaceAnswer

    /// The id of the marketplace.
    public var id: String

    /// Creates the operation by directly assigning its parameter.
    ///
    /// - Parameter id: The id of the marketplace.
    public init(id: String) {
        self.id = id
    }

    /// The action this operation performs: `"show"`.
    public static let verb = "show"

    /// The resource this operation acts on: `"marketplace"`.
    public static let noun = marketplaceOperationNoun

    /// A human- and model-facing summary of what this operation does.
    public static let operationDescription = "Show each field of one skill marketplace. Give its `id`."

    /// This operation's parameter: `id` (required).
    public static let parameterMetadata: [ParamMeta] = [MarketplaceParameters.id]

    /// Decodes the operation from a resolved payload.
    ///
    /// - Parameter content: The payload to decode.
    /// - Throws: An error of `content.value(_:forProperty:)`.
    public init(_ content: GeneratedContent) throws {
        id = try content.value(String.self, forProperty: MarketplaceParameters.idKey)
    }

    /// This operation's parameter re-encoded as `GeneratedContent`.
    public var generatedContent: GeneratedContent {
        GeneratedContent(properties: [MarketplaceParameters.idKey: id])
    }

    /// Shows the marketplace, or returns a corrective message.
    ///
    /// - Parameter context: The shared context that gives the registry.
    /// - Returns: One line for each field, or a corrective message.
    /// - Throws: An error of the storage of the registry.
    public func execute(in context: SkillsToolContext) async throws -> MarketplaceAnswer {
        try await MarketplaceParameters.answer(in: context) { marketplaces in
            guard let entry = try await marketplaces.marketplace(id: id) else {
                throw MarketplaceRegistryError.unknownMarketplace(id: id)
            }
            return MarketplaceParameters.lines(of: entry)
        }
    }
}

/// The parameters and the answers that the marketplace operations share.
enum MarketplaceParameters {
    /// The `GeneratedContent` property name for `id`.
    static let idKey = "id"

    /// The property names of the fields of a source.
    private enum Key {
        static let url = "url"
        static let ref = "ref"
        static let sha = "sha"
        static let path = "path"
        static let alias = "alias"
        static let skills = "skills"
        static let allSkills = "allSkills"
        static let autoUpdate = "autoUpdate"
    }

    /// The required `id` parameter.
    static let id = ParamMeta(
        name: idKey, type: .string, required: true,
        description: "The id of the marketplace: its alias, or else its repository name.")

    /// The `url` parameter.
    ///
    /// - Parameter required: Whether the operation needs it.
    /// - Returns: The parameter.
    static func url(required: Bool) -> ParamMeta {
        ParamMeta(
            name: Key.url, type: .string, required: required,
            description: "The location: https://host/owner/repo.git, github:owner/repo, or file:///path.")
    }

    /// The optional fields of a source, after `url`.
    static let sourceFields: [ParamMeta] = [
        ParamMeta(name: Key.ref, type: .string, required: false, description: "A branch or a tag."),
        ParamMeta(name: Key.sha, type: .string, required: false, description: "A commit pin. It wins over `ref`."),
        ParamMeta(
            name: Key.path, type: .string, required: false,
            description: "For a marketplace: the subfolder of the repository."),
        ParamMeta(
            name: Key.alias, type: .string, required: false,
            description: "A local name for the marketplace. It is then the id."),
        ParamMeta(
            name: Key.skills, type: .array(of: .string), required: false,
            description: "The names of the skills to take. Leave it out for all the skills."),
        ParamMeta(
            name: Key.allSkills, type: .boolean, required: false,
            description: "True to take all the skills of the marketplace again."),
        ParamMeta(
            name: Key.autoUpdate, type: .boolean, required: false,
            description: "Whether a new commit installs when it is found. Leave it out for true."),
    ]

    /// Reads the fields of a source from a payload.
    ///
    /// - Parameter content: The payload.
    /// - Returns: The fields.
    /// - Throws: An error of `content.value(_:forProperty:)`.
    static func fields(of content: GeneratedContent) throws -> MarketplaceSourceFields {
        MarketplaceSourceFields(
            url: try content.value(String?.self, forProperty: Key.url),
            ref: try content.value(String?.self, forProperty: Key.ref),
            sha: try content.value(String?.self, forProperty: Key.sha),
            path: try content.value(String?.self, forProperty: Key.path),
            alias: try content.value(String?.self, forProperty: Key.alias),
            skills: try content.value([String]?.self, forProperty: Key.skills),
            allSkills: try content.value(Bool?.self, forProperty: Key.allSkills) ?? false,
            autoUpdate: try content.value(Bool?.self, forProperty: Key.autoUpdate))
    }

    /// The payload of an `id` and the fields of a source.
    ///
    /// - Parameters:
    ///   - id: The id, or `nil` for no id.
    ///   - fields: The fields.
    /// - Returns: The payload.
    static func content(id: String?, fields: MarketplaceSourceFields) -> GeneratedContent {
        GeneratedContentBuilder.make(
            required: [],
            optional: [
                (idKey, id), (Key.url, fields.url), (Key.ref, fields.ref), (Key.sha, fields.sha),
                (Key.path, fields.path), (Key.alias, fields.alias), (Key.skills, fields.skills),
                (Key.allSkills, fields.allSkills ? true : nil), (Key.autoUpdate, fields.autoUpdate),
            ])
    }

    /// One line for each field of `entry`.
    ///
    /// - Parameter entry: The marketplace.
    /// - Returns: The lines.
    static func lines(of entry: MarketplaceEntry) -> String {
        let source = entry.source
        let skills: String
        switch source.select {
        case .all: skills = "all"
        case .skills(let names): skills = names.joined(separator: ", ")
        }
        let optional = [(Key.ref, source.ref), (Key.sha, source.sha), (Key.path, source.path), (Key.alias, source.alias)]
            .compactMap { key, value in value.map { "\(key): \($0)" } }
        return (["\(idKey): \(entry.id)", "\(Key.url): \(source.url)"] + optional + [
            "\(Key.skills): \(skills)", "\(Key.autoUpdate): \(source.autoUpdate)",
        ]).joined(separator: "\n")
    }

    /// Runs `body` with the registry of `context`, and gives a refusal of
    /// the registry as a corrective message.
    ///
    /// - Parameters:
    ///   - context: The shared context.
    ///   - body: The work, with the registry.
    /// - Returns: `.success(_:)` with the text of `body`, or `.corrective(_:)`
    ///   when the context has no registry or the registry refuses.
    /// - Throws: Any other error of `body`: an error of the storage.
    static func answer(
        in context: SkillsToolContext, _ body: (MarketplaceRegistry) async throws -> String
    ) async throws -> MarketplaceAnswer {
        guard let marketplaces = context.marketplaces else {
            return .corrective("This host keeps no marketplace list, thus no marketplace can change here.")
        }
        do {
            return .success(try await body(marketplaces))
        } catch let error as MarketplaceRegistryError {
            return .corrective(error.errorDescription ?? "\(error)")
        }
    }
}
