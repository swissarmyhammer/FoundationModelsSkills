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
        let root = try #require(
            try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let data = try #require(root["data"] as? [String: Any])
        let skill = try #require(data["skill"] as? [String: Any])

        #expect(skill["id"] as? String == Self.fixtureSkillID)
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
