import FoundationModelsExtras
import Graphiti
import GraphQL

// The GraphQL schema of the `skills` endpoint (SK-5): the `ID` scalar, the
// `SkillSource` enum, the `Skill` object type, the arguments, the resolver
// and the Graphiti API over one `SkillsRegistry`.

// MARK: - Scalars and enums

/// The text of a GraphQL `ID`: the id of a skill, which is its name.
///
/// Graphiti maps no Swift type to the built-in `ID` scalar, so this type is a
/// scalar with that name. The schema does not refer to the built-in scalar,
/// so the two do not collide. The Codable form is the text, so the default
/// Graphiti scalar closures serialize and parse the value.
struct SkillID: Codable, Sendable, Hashable {
    /// The GraphQL name of the scalar: the built-in `ID` name.
    static let name = "ID"

    /// The text of the id.
    let text: String
}

extension SkillID {
    /// Decodes the id from its text.
    ///
    /// - Parameter decoder: The decoder that holds the text.
    /// - Throws: A `DecodingError` when the value is not text.
    init(from decoder: any Decoder) throws {
        try self.init(text: decoder.singleValueContainer().decode(String.self))
    }

    /// Encodes the id as its text.
    ///
    /// - Parameter encoder: The encoder that gets the text.
    /// - Throws: An error from the encoder.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

/// The layer of the dotfolder stack that gives a skill, as the `skills`
/// endpoint names it.
enum SkillsGraphSource: String, Codable, CaseIterable, Sendable {
    /// A cached remote skill marketplace.
    case marketplace = "MARKETPLACE"

    /// The defaults folder of the host.
    case defaults = "DEFAULTS"

    /// The user level.
    case user = "USER"

    /// The project dotfolder of the working folder.
    case project = "PROJECT"

    /// Gives the GraphQL name of a layer of the stack.
    ///
    /// - Parameter source: The layer of the stack.
    init(_ source: DotfolderStack.Source) {
        switch source {
        case .marketplace:
            self = .marketplace
        case .defaults:
            self = .defaults
        case .user:
            self = .user
        case .project:
            self = .project
        }
    }
}

// MARK: - Object types

/// The `Skill` object: one skill on disk.
struct SkillsGraphSkill: Codable, Sendable {
    /// The id of the skill: its directory name.
    let id: SkillID

    /// The name of the skill, the same text as the id.
    let name: String

    /// The rendered description.
    let description: String

    /// The placeholder of each parameter.
    let parameters: [String]

    /// The layer that gives the skill.
    let source: SkillsGraphSource

    /// The marketplace of the skill, or `nil` for a local skill.
    let marketplace: String?

    /// Whether the skill is on.
    let enabled: Bool

    /// Makes the object of one record of the registry.
    ///
    /// - Parameter record: The record.
    init(_ record: SkillRecord) {
        id = SkillID(text: record.id)
        name = record.id
        description = record.description
        parameters = record.parameters
        source = SkillsGraphSource(record.layer)
        marketplace = record.marketplace
        enabled = record.isEnabled
    }
}

// MARK: - Arguments

/// The arguments of `Query.skill`.
struct SkillsGraphSkillArguments: Codable, Sendable {
    /// The id of the skill.
    let id: SkillID
}

// MARK: - Resolver and context

/// The context of one call of the `skills` endpoint.
struct SkillsGraphContext: GraphQLRunContext {
    /// The warnings of the call.
    let warnings = ResponseWarnings()
}

/// The root resolver of the `skills` endpoint over one registry.
struct SkillsGraphResolver: Sendable {
    /// The registry whose skills the endpoint gives.
    let registry: SkillsRegistry

    /// Resolves `Query.skills`.
    ///
    /// - Returns: Each skill of the registry, the skills that are off
    ///   included, sorted by id.
    func skills(context _: SkillsGraphContext, arguments _: NoArguments) -> [SkillsGraphSkill] {
        registry.records().map(SkillsGraphSkill.init)
    }

    /// Resolves `Query.skill`.
    ///
    /// - Parameter arguments: The id of the skill.
    /// - Returns: The skill, or `nil` when no skill has the id.
    func skill(context _: SkillsGraphContext, arguments: SkillsGraphSkillArguments) -> SkillsGraphSkill? {
        registry.records().first { record in record.id == arguments.id.text }.map(SkillsGraphSkill.init)
    }
}

// MARK: - The API

/// The Graphiti engine of the `skills` endpoint.
struct SkillsGraphAPI: API {
    /// The root resolver.
    let resolver: SkillsGraphResolver

    /// The schema.
    let schema: Schema<SkillsGraphResolver, SkillsGraphContext>

    /// Builds the schema over a resolver.
    ///
    /// - Parameter resolver: The root resolver.
    /// - Throws: An error of the schema builder.
    init(resolver: SkillsGraphResolver) throws {
        self.resolver = resolver
        schema = try SchemaBuilder(SkillsGraphResolver.self, SkillsGraphContext.self)
            .addToolkitScalars()
            .add {
                Scalar(SkillID.self, as: SkillID.name)
                Enum(SkillsGraphSource.self, as: "SkillSource") {
                    Value(.marketplace).description("A cached remote skill marketplace.")
                    Value(.defaults).description("The defaults folder of the host.")
                    Value(.user).description("The user level.")
                    Value(.project).description("The project dotfolder of the working folder.")
                }
                .description("The layer of the dotfolder stack that gives a skill.")
                Type(SkillsGraphSkill.self, as: "Skill") {
                    Field("id", at: \.id).description("The id of the skill: its directory name.")
                    Field("name", at: \.name).description("The name of the skill, the same text as the id.")
                    Field("description", at: \.description)
                        .description("The rendered description, or an empty text when the skill has none.")
                    Field("parameters", at: \.parameters)
                        .description("The placeholder of each parameter, in order, for example <message> or [env].")
                    Field("source", at: \.source).description("The layer that gives the SKILL.md of the skill.")
                    Field("marketplace", at: \.marketplace)
                        .description("The marketplace of the skill, for example name@1a2b3c4, or null for a local skill.")
                    Field("enabled", at: \.enabled)
                        .description("False when the enabled key of the skill turns it off. The model does not see it then.")
                }
                .description("One skill on disk, also one that is off.")
            }
            .addQuery {
                Field("skills", at: SkillsGraphResolver.skills)
                    .description("Each skill of the folder, also the skills that are off, sorted by id.")
                Field("skill", at: SkillsGraphResolver.skill) {
                    Argument("id", at: \.id).description("The id of the skill, which is its name.")
                }
                .description("One skill, or null when no skill has the id.")
            }
            .build()
    }
}
