import FoundationModelsExtras
import Graphiti
import GraphQL

// The GraphQL schema of the `skills` endpoint (SK-5): the `SkillSource` enum,
// the `Skill` and `SkillChange` object types, the arguments, the resolver and
// the Graphiti API over one `SkillsRegistry` and its change log. The `ID`
// scalar is the toolkit `ToolkitID`.

// MARK: - Enums

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
    let id: ToolkitID

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
        id = ToolkitID(record.id)
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
    let id: ToolkitID
}

/// The arguments of `Subscription.changes`.
struct SkillsGraphChangesArguments: Codable, Sendable {
    /// The cursor to resume after, or `nil` for the new changes only.
    let after: String?
}

// MARK: - Resolver and context

/// The context of one call of the `skills` endpoint.
struct SkillsGraphContext: GraphQLRunContext {
    /// The warnings of the call.
    let warnings = ResponseWarnings()
}

/// The root resolver of the `skills` endpoint over one registry and the
/// change log of its reloads.
struct SkillsGraphResolver: Sendable {
    /// The registry whose skills the endpoint gives.
    let registry: SkillsRegistry

    /// The change log that `SkillChangeFeed` fills from the reloads of
    /// ``registry``.
    let changeLog: ChangeLog<ChangedIDs>

    /// Resolves `Query.cursor`.
    ///
    /// - Returns: The cursor of the newest change of the skills.
    func cursor(context _: SkillsGraphContext, arguments _: NoArguments) async -> String {
        await changeLog.cursor
    }

    /// Resolves the source stream of `Subscription.changes`.
    ///
    /// - Parameter arguments: The cursor to resume after.
    /// - Returns: The changes after the cursor, or only the new changes when
    ///   there is no cursor. The stream ends with `RESYNC_REQUIRED` when the
    ///   log cannot resume after the cursor.
    func changes(
        context _: SkillsGraphContext, arguments: SkillsGraphChangesArguments
    ) async -> ChangeLog<ChangedIDs>.Changes {
        await changeLog.changes(after: arguments.after)
    }

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
            .addToolkitIDScalar()
            .add {
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
                Type(IDChange.self, as: "SkillChange") {
                    Field("cursor", at: \.cursor).description("The cursor that resumes after this change.")
                    Field("at", at: \.at).description("The time of the reload that made the change.")
                    Field("added", at: \.added).description("The ids of the skills that the reload added.")
                    Field("changed", at: \.changed)
                        .description("The ids of the skills whose SKILL.md the reload changed, also to turn one off.")
                    Field("removed", at: \.removed).description("The ids of the skills that the reload removed.")
                }
                .description("One reload of the skills of the folder that added, changed or removed a skill.")
            }
            .addQuery {
                Field("cursor", at: SkillsGraphResolver.cursor)
                    .description("The cursor of the newest change of the skills, for changes(after:).")
                Field("skills", at: SkillsGraphResolver.skills)
                    .description("Each skill of the folder, also the skills that are off, sorted by id.")
                Field("skill", at: SkillsGraphResolver.skill) {
                    Argument("id", at: \.id).description("The id of the skill, which is its name.")
                }
                .description("One skill, or null when no skill has the id.")
            }
            .addSubscription {
                SubscriptionField(
                    "changes",
                    at: { (entry: ChangeLogEntry<ChangedIDs>) in
                        { (_: SkillsGraphContext, _: SkillsGraphChangesArguments) async throws -> IDChange in
                            IDChange(entry)
                        }
                    },
                    atSub: SkillsGraphResolver.changes
                ) {
                    Argument("after", at: \.after)
                        .description("The cursor to resume after, from cursor or a change. Omit it for the new changes only.")
                }
                .description(
                    "One change for each reload that adds, changes or removes a skill. "
                        + "A cursor that cannot resume gives RESYNC_REQUIRED.")
            }
            .build()
    }
}
