import FoundationModelsExtras
import Graphiti
import GraphQL
import Marketplace

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

    /// The description as the `SKILL.md` gives it, not rendered.
    let rawDescription: String

    /// The Markdown body of the `SKILL.md`, not rendered.
    let body: String

    /// Makes the object of the content of one skill of the registry.
    ///
    /// - Parameter content: The record, the frontmatter and the body of the
    ///   skill.
    init(_ content: SkillContent) {
        let record = content.record
        id = ToolkitID(record.id)
        name = record.id
        description = record.description
        parameters = record.parameters
        source = SkillsGraphSource(record.layer)
        marketplace = record.marketplace
        enabled = record.isEnabled
        rawDescription = content.frontmatter.description ?? ""
        body = content.body
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

    /// The marketplace list that the host keeps, or `nil` when the host
    /// keeps none.
    let marketplaces: MarketplaceRegistry?

    /// The change log that `MarketplaceChangeFeed` fills from the changes of
    /// ``marketplaces``.
    let marketplaceChangeLog: ChangeLog<ChangedIDs>

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
        registry.skillContents().values.sorted { $0.record.id < $1.record.id }.map(SkillsGraphSkill.init)
    }

    /// Resolves `Query.skill`.
    ///
    /// - Parameter arguments: The id of the skill.
    /// - Returns: The skill, or `nil` when no skill has the id.
    func skill(context _: SkillsGraphContext, arguments: SkillsGraphSkillArguments) -> SkillsGraphSkill? {
        registry.skillContents()[arguments.id.text].map(SkillsGraphSkill.init)
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
                    Field("rawDescription", at: \.rawDescription)
                        .description("The description as the SKILL.md gives it, not rendered. An editor shows this text.")
                    Field("body", at: \.body).description("The Markdown body of the SKILL.md, not rendered.")
                }
                .description("One skill on disk, also one that is off.")
                Enum(SkillsGraphLayer.self, as: "SkillLayer") {
                    Value(.user).description("The user layer, for all projects.")
                    Value(.project).description("The project layer, for this project only.")
                }
                .description("A layer that a mutation can write. The defaults and marketplace layers are read-only.")
                Type(RemoveSkillPayload.self) {
                    Field("id", at: \.id).description("The id of the deleted skill.")
                    Field("layer", at: \.layer).description("The layer that the mutation deleted the skill from.")
                    Field("skill", at: \.skill)
                        .description("The copy of the skill in another layer that stays, or null when no copy stays.")
                }
                .description("What removeSkill deleted.")
                Input(AddSkillInput.self) {
                    InputField("id", at: \.id).description("The id of the new skill: the name of its folder.")
                    InputField("description", at: \.description).description("The description of the new skill.")
                    InputField("body", at: \.body).description("The Markdown body of the new skill. Omit it for no body.")
                    InputField("layer", at: \.layer).description("The layer to write. Omit it for USER.")
                }
                .description("The fields of addSkill.")
                Input(UpdateSkillInput.self) {
                    InputField("id", at: \.id).description("The id of the skill to change.")
                    InputField("description", at: \.description)
                        .description("The new description. Omit it for no change.")
                    InputField("body", at: \.body).description("The new Markdown body. Omit it for no change.")
                    InputField("layer", at: \.layer)
                        .description(
                            "The layer to write, which must hold the skill. "
                                + "Omit it for the writable layer of the highest precedence that holds the skill.")
                }
                .description("The fields of updateSkill. A field that you omit does not change.")
                Input(RemoveSkillInput.self) {
                    InputField("id", at: \.id).description("The id of the skill to delete.")
                    InputField("layer", at: \.layer)
                        .description(
                            "The layer to delete from, which must hold the skill. "
                                + "Omit it for the writable layer of the highest precedence that holds the skill.")
                }
                .description("The fields of removeSkill.")
                Type(IDChange.self, as: "SkillChange") {
                    Field("cursor", at: \.cursor).description("The cursor that resumes after this change.")
                    Field("at", at: \.at).description("The time of the reload that made the change.")
                    Field("added", at: \.added).description("The ids of the skills that the reload added.")
                    Field("changed", at: \.changed)
                        .description("The ids of the skills whose SKILL.md the reload changed, also to turn one off.")
                    Field("removed", at: \.removed).description("The ids of the skills that the reload removed.")
                }
                .description("One reload of the skills of the folder that added, changed or removed a skill.")
                Type(SkillsGraphMarketplace.self, as: "Marketplace") {
                    Field("id", at: \.id).description("The id of the marketplace: its alias, or else its repository name.")
                    Field("url", at: \.url)
                        .description("The location: https://host/owner/repo.git, github:owner/repo, or file:///path.")
                    Field("ref", at: \.ref).description("The branch or the tag, or null for the default branch.")
                    Field("sha", at: \.sha).description("The commit pin, or null. It wins over ref.")
                    Field("path", at: \.path).description("The subfolder of the repository, or null for the root.")
                    Field("alias", at: \.alias).description("The local name, or null. When it is set, it is the id.")
                    Field("skills", at: \.skills).description("The skills to take, or null for all the skills.")
                    Field("autoUpdate", at: \.autoUpdate)
                        .description("Whether the store installs a new commit when it finds one.")
                }
                .description("One skill marketplace of the list.")
                Type(SkillsGraphMarketplaceChange.self, as: "MarketplaceChange") {
                    Field("cursor", at: \.cursor).description("The cursor that resumes after this change.")
                    Field("at", at: \.at).description("The time of the change.")
                    Field("added", at: \.added).description("The ids of the marketplaces that the change added.")
                    Field("changed", at: \.changed).description("The ids of the marketplaces that the change changed.")
                    Field("removed", at: \.removed)
                        .description("The ids of the marketplaces that the change removed. A new id is a remove and an add.")
                }
                .description("One change of the marketplace list.")
                Input(AddMarketplaceInput.self) {
                    InputField("url", at: \.url)
                        .description("The location: https://host/owner/repo.git, github:owner/repo, or file:///path.")
                    InputField("ref", at: \.ref).description("The branch or the tag. Omit it for the default branch.")
                    InputField("sha", at: \.sha).description("The commit pin. It wins over ref.")
                    InputField("path", at: \.path).description("The subfolder of the repository.")
                    InputField("alias", at: \.alias).description("The local name, which is then the id.")
                    InputField("skills", at: \.skills).description("The skills to take. Omit it for all the skills.")
                    InputField("autoUpdate", at: \.autoUpdate)
                        .description("Whether the store installs a new commit when it finds one. Omit it for true.")
                }
                .description("The fields of addMarketplace.")
                Input(UpdateMarketplaceInput.self) {
                    InputField("id", at: \.id).description("The id of the marketplace to change.")
                    InputField("url", at: \.url).description("The new location.")
                    InputField("ref", at: \.ref).description("The new branch or tag. An empty text clears it.")
                    InputField("sha", at: \.sha).description("The new commit pin. An empty text clears it.")
                    InputField("path", at: \.path).description("The new subfolder. An empty text clears it.")
                    InputField("alias", at: \.alias)
                        .description("The new local name. An empty text clears it. A new alias changes the id.")
                    InputField("skills", at: \.skills).description("The new skills to take.")
                    InputField("allSkills", at: \.allSkills).description("True to take all the skills again.")
                    InputField("autoUpdate", at: \.autoUpdate).description("The new auto-update flag.")
                }
                .description("The fields of updateMarketplace. A field that you omit does not change.")
                Input(RemoveMarketplaceInput.self) {
                    InputField("id", at: \.id).description("The id of the marketplace to remove.")
                }
                .description("The fields of removeMarketplace.")
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
                Field("marketplaceCursor", at: SkillsGraphResolver.marketplaceCursor)
                    .description("The cursor of the newest change of the marketplaces, for marketplaceChanges(after:).")
                Field("marketplaces", at: SkillsGraphResolver.marketplaces)
                    .description("Each skill marketplace of the list, in order. Empty when the host keeps no list.")
                Field("marketplace", at: SkillsGraphResolver.marketplace) {
                    Argument("id", at: \.id).description("The id of the marketplace.")
                }
                .description("One marketplace, or null when no marketplace has the id.")
            }
            .addMutation {
                Field("addSkill", at: SkillsGraphResolver.addSkill) {
                    Argument("input", at: \.input).description("The new skill.")
                }
                .description(
                    "Makes a new skill: its folder and its SKILL.md. Gives the skill that wins for the id, "
                        + "or SKILL_EXISTS or INVALID_SKILL.")
                Field("updateSkill", at: SkillsGraphResolver.updateSkill) {
                    Argument("input", at: \.input).description("The skill and its changes.")
                }
                .description(
                    "Writes a new description or body into the SKILL.md of a skill. Gives the skill that wins for "
                        + "the id, or NOT_FOUND, SKILL_READ_ONLY or INVALID_SKILL.")
                Field("removeSkill", at: SkillsGraphResolver.removeSkill) {
                    Argument("input", at: \.input).description("The skill to delete.")
                }
                .description(
                    "Deletes a skill and all its files from one layer. A copy in another layer stays. "
                        + "Gives NOT_FOUND or SKILL_READ_ONLY for a skill that cannot be deleted.")
                Field("addMarketplace", at: SkillsGraphResolver.addMarketplace) {
                    Argument("input", at: \.input).description("The new marketplace.")
                }
                .description(
                    "Adds a skill marketplace to the end of the list. Gives the new marketplace, or "
                        + "DUPLICATE_MARKETPLACE, INVALID_MARKETPLACE or MARKETPLACES_UNAVAILABLE.")
                Field("updateMarketplace", at: SkillsGraphResolver.updateMarketplace) {
                    Argument("input", at: \.input).description("The marketplace and its changes.")
                }
                .description(
                    "Changes the source of one marketplace, in its place in the list. Gives the changed marketplace, "
                        + "or NOT_FOUND, DUPLICATE_MARKETPLACE, INVALID_MARKETPLACE or MARKETPLACES_UNAVAILABLE.")
                Field("removeMarketplace", at: SkillsGraphResolver.removeMarketplace) {
                    Argument("input", at: \.input).description("The marketplace to remove.")
                }
                .description(
                    "Removes one marketplace from the list. Gives the removed marketplace, or NOT_FOUND or "
                        + "MARKETPLACES_UNAVAILABLE.")
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
                SubscriptionField(
                    "marketplaceChanges",
                    at: { (entry: ChangeLogEntry<ChangedIDs>) in
                        { (_: SkillsGraphContext, _: SkillsGraphChangesArguments) async throws -> SkillsGraphMarketplaceChange in
                            SkillsGraphMarketplaceChange(entry)
                        }
                    },
                    atSub: SkillsGraphResolver.marketplaceChanges
                ) {
                    Argument("after", at: \.after)
                        .description(
                            "The cursor to resume after, from marketplaceCursor or a change. Omit it for the new changes only.")
                }
                .description(
                    "One change for each add, update or remove of a marketplace. "
                        + "A cursor that cannot resume gives RESYNC_REQUIRED.")
            }
            .build()
    }
}
