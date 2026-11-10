import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the `skills` GraphQL endpoint that the `skills` tool gives a
/// host through `GraphQLEndpointTool` (SK-5, EXTRAS-9 rule 11).
///
/// A host holds each tool as `any Tool`, and finds the endpoints with
/// `tool as? any GraphQLEndpointTool`. These cases read the endpoint that
/// way, thus they show what a host sees.
struct SkillsCatalogToolEndpointTests {
    // MARK: - Constants

    /// The version of the schema of the `skills` endpoint.
    private static let endpointVersion = "1"

    /// A fixture skill that the endpoint gives by its id.
    private static let fixtureSkillID = "lint"

    /// The skill that each write case writes through the tool. `WriteCase`
    /// reads it too, thus it is `fileprivate`.
    fileprivate static let writtenSkillID = "written"

    // MARK: - The endpoint of the tool

    @Test func theToolGivesTheSkillsEndpointWithItsNameVersionAndScope() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())

        let endpoint = try Self.onlyEndpoint(of: tool)

        #expect(endpoint.name == SkillsGraph.endpointName)
        #expect(endpoint.version == Self.endpointVersion)
        #expect(endpoint.scope == .sessionFolder)
    }

    @Test func aCopyOfTheToolGivesTheSameEndpointInstance() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())
        let copy = tool

        let endpoint = try Self.onlyEndpoint(of: tool)
        let copiedEndpoint = try Self.onlyEndpoint(of: copy)

        #expect(endpoint === copiedEndpoint)
    }

    @Test func aForkedToolGivesTheSameEndpointInstance() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())

        let endpoint = try Self.onlyEndpoint(of: tool)
        let forkedEndpoint = try Self.onlyEndpoint(of: tool.forked())

        #expect(endpoint === forkedEndpoint)
    }

    @Test func theEndpointReadsTheRegistryOfTheTool() async throws {
        let tool = try await SkillsTool.make(registry: Self.makeFixtureRegistry())
        let endpoint = try Self.onlyEndpoint(of: tool)

        let response = try await endpoint.execute(
            query: "{ skill(id: \"\(Self.fixtureSkillID)\") { id } }", variables: [:], operationName: nil,
            viewer: nil)
        let skill = try #require(try GraphQLTestSupport.data(of: response)["skill"] as? [String: Any])

        #expect(skill["id"] as? String == Self.fixtureSkillID)
    }

    // MARK: - A write through the tool

    /// Each write through the tool gives one change event on the `skills`
    /// endpoint of the same tool, with the id of the skill in the field of
    /// its kind of change.
    ///
    /// The case of `edit skill` and `remove skill` first adds the skill. The
    /// feed of the endpoint appends the event of that add on its own task,
    /// thus a cursor read after the add can come before that event. The case
    /// subscribes before the add, and reads the event of the add from the
    /// stream. The next event is then the event of the write under test.
    @Test(.timeLimit(.minutes(1)), arguments: WriteCase.allCases)
    func eachWriteThroughTheToolGivesOneChangeEventOnTheEndpoint(write: WriteCase) async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = try await SkillsTool.make(
            registry: SkillsRegistry(layers: [DotfolderStack.Layer(source: .user, root: root)]))
        let endpoint = try Self.onlyEndpoint(of: tool)
        let start = try await GraphQLTestSupport.cursor(of: endpoint)
        let stream = try await endpoint.subscribe(
            query: "subscription { changes(after: \"\(start)\") { cursor \(write.changeField) } }", variables: [:],
            operationName: nil, viewer: nil)
        var events = stream.makeAsyncIterator()
        if write != .add {
            _ = try await tool.call(arguments: WriteCase.add.arguments)
            _ = try #require(try await events.next())
        }

        _ = try await tool.call(arguments: write.arguments)
        let event = try GraphQLTestSupport.changeEvent(in: try #require(try await events.next()))

        #expect(event[write.changeField] as? [String] == [Self.writtenSkillID])
        #expect(try await GraphQLTestSupport.cursor(of: endpoint) == event["cursor"] as? String)
    }

    /// One write operation of the tool, with its payload for
    /// ``writtenSkillID`` and the field of the change event that names the
    /// skill.
    enum WriteCase: CaseIterable, Sendable {
        /// `add skill`, which adds the skill.
        case add

        /// `edit skill`, which changes the description of the skill.
        case edit

        /// `remove skill`, which deletes the skill.
        case remove

        /// The payload of the write.
        var arguments: GeneratedContent {
            let id = SkillsCatalogToolEndpointTests.writtenSkillID
            switch self {
            case .add:
                return GeneratedContent(properties: [
                    "op": "add skill", "id": id, "content": ReloadTestSupport.skillFileContents(id: id),
                ])
            case .edit:
                return GeneratedContent(properties: [
                    "op": "edit skill", "id": id,
                    "content": ReloadTestSupport.skillFileContents(id: id, descriptionSuffix: "edited"),
                ])
            case .remove:
                return GeneratedContent(properties: ["op": "remove skill", "id": id])
            }
        }

        /// The field of the change event that names the skill.
        var changeField: String {
            switch self {
            case .add: "added"
            case .edit: "changed"
            case .remove: "removed"
            }
        }
    }

    // MARK: - Fixtures

    /// Builds a registry over the `Examples/skill-library` fixture stack.
    ///
    /// - Returns: The registry the cases hand to the factory.
    private static func makeFixtureRegistry() -> SkillsRegistry {
        SkillsRegistry(stack: FixtureLibrary.stack())
    }

    /// Finds the endpoints of `tool` the way a host does, and requires
    /// exactly one: the `skills` endpoint.
    ///
    /// - Parameter tool: The tool, as the `any Tool` a host holds.
    /// - Returns: The one endpoint of the tool.
    /// - Throws: A `#require` failure when the tool gives no endpoint, more
    ///   than one, or one that is not a `SkillsGraph`.
    private static func onlyEndpoint(of tool: any Tool) throws -> SkillsGraph {
        let endpointTool = try #require(tool as? any GraphQLEndpointTool)
        let endpoints = endpointTool.graphQLEndpoints
        try #require(endpoints.count == 1)
        return try #require(endpoints.first as? SkillsGraph)
    }
}
