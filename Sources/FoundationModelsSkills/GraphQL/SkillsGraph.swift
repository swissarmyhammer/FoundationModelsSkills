import FoundationModelsExtras
import GraphQL

/// The `skills` GraphQL endpoint (SK-5): the skills of one registry for the
/// clients of a host, under the endpoint conventions of EXTRAS-9.
///
/// The endpoint has the session folder scope: a registry comes from the
/// dotfolder stack of the working folder of a session, thus one endpoint
/// over one registry serves one folder. A host keeps one endpoint for each
/// folder, and checks the folder of each call itself.
///
/// - `Query.skills` gives each skill that loads, the skills that their
///   `enabled` key turns off included, each with `enabled`. The model
///   surface of the `skills` tool keeps its own filter: it shows only the
///   skills that are on.
/// - `Query.skill(id:)` gives one skill, or `null` when no skill has the id.
///   The id is the name of the skill, thus `skill(name:)` is an alias.
/// - `Query.cursor` and `Subscription.changes(after:)` give the changes of
///   the skills (rule 9): one `SkillChange` for each reload of the registry
///   that adds, changes or removes a skill, the skills that are off included.
///   A cursor that the change log cannot resume after gives
///   `RESYNC_REQUIRED`. `skillChanges` is an alias of `changes`.
///
/// The endpoint reads and changes nothing on disk: it has no `Mutation`
/// type (D84). It has no package error code: each error is a code of the
/// toolkit.
///
/// The endpoint is a class because its identity is part of its contract:
/// one endpoint serves one registry, with one change log. `SkillsTool.make(context:)`
/// makes it one time, and each copy and each fork of the `skills` tool gives
/// that same instance, and thus that same change log, through
/// `GraphQLEndpointTool`.
public final class SkillsGraph: GraphQLEndpoint {
    /// The name of the endpoint: the noun of the `skills` tool.
    public static let endpointName = "skills"

    /// The other names that a call can write for the names of the schema:
    /// `listSkills` and `getSkill` for the root fields, `skillChanges` for
    /// the subscription, and `name` for the `id` argument of `skill`, because
    /// the id of a skill is its name.
    static let rules = GraphQLNameRules(
        aliases: GraphQLAliasTable(
            byType: [
                "Query": [
                    "skills": ["listSkills"],
                    "skill": ["getSkill"],
                ],
                "Subscription": [
                    "changes": ["skillChanges"]
                ],
            ],
            byField: [
                "Query.skill": ["id": ["name"]]
            ])
    )

    /// The name of the endpoint.
    public let name = endpointName

    /// The version of the schema.
    public let version = "1"

    /// The scope of the endpoint: the folder of a session.
    public let scope = GraphQLEndpointScope.sessionFolder

    /// The Graphiti engine of the endpoint.
    private let api: SkillsGraphAPI

    /// The feed that appends one event to the change log for each reload of
    /// the registry that changes a skill. The endpoint owns it, and its
    /// deinit stops the feed.
    ///
    /// Held for its lifetime only: the deinit of the endpoint releases it,
    /// and its own deinit cancels the feed task; periphery sees no read.
    // periphery:ignore
    private let feed: SkillChangeFeed

    /// Makes the endpoint over a registry, with a new change log of the
    /// default size.
    ///
    /// - Parameter registry: The registry whose skills the endpoint gives.
    ///   Each call reads its current catalog generation, and each reload
    ///   feeds the change log.
    /// - Throws: An error of the schema builder.
    public convenience init(registry: SkillsRegistry) throws {
        try self.init(registry: registry, changeLog: ChangeLog())
    }

    /// Makes the endpoint over a registry and a change log.
    ///
    /// A test gives a small change log, so that a cursor can fall out of its
    /// buffer.
    ///
    /// - Parameters:
    ///   - registry: The registry whose skills the endpoint gives.
    ///   - changeLog: The change log of the endpoint. The endpoint is its one
    ///     writer.
    /// - Throws: An error of the schema builder.
    init(registry: SkillsRegistry, changeLog: ChangeLog<ChangedIDs>) throws {
        api = try SkillsGraphAPI(resolver: SkillsGraphResolver(registry: registry, changeLog: changeLog))
        feed = SkillChangeFeed(registry: registry, changeLog: changeLog)
    }

    /// The schema of the endpoint in SDL.
    public var schema: String {
        api.sdl
    }

    /// Runs one GraphQL document.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil`.
    ///   - viewer: The client that makes the call, or `nil` for the agent.
    ///     Each client sees the same skills: the host checks the folder of
    ///     the call before it reaches the endpoint of that folder.
    /// - Returns: The GraphQL response as JSON text.
    /// - Throws: A fault that is not a GraphQL error.
    public func execute(
        query: String, variables: [String: Map], operationName: String?, viewer _: GraphQLViewer?
    ) async throws -> String {
        try await api.respond(
            to: query, variables: variables, operationName: operationName, rules: Self.rules,
            formattedWith: .sortedKeys, context: SkillsGraphContext())
    }

    /// Starts one GraphQL subscription.
    ///
    /// `changes(after:)` gives one response for each change after the
    /// cursor. A cursor that the change log cannot resume after gives one
    /// final response with `RESYNC_REQUIRED`, and the stream then ends.
    ///
    /// - Parameters:
    ///   - query: The subscription document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil`.
    ///   - viewer: The client that makes the call, or `nil` for the agent.
    /// - Returns: The GraphQL response of each event as JSON text.
    /// - Throws: A fault that is not a GraphQL error.
    public func subscribe(
        query: String, variables: [String: Map], operationName: String?, viewer _: GraphQLViewer?
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await api.subscribe(
            to: query, variables: variables, operationName: operationName, rules: Self.rules,
            formattedWith: .sortedKeys, context: SkillsGraphContext())
    }
}
