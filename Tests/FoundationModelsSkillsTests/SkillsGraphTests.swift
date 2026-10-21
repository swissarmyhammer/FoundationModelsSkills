import Foundation
import FoundationModelsExtras
import GraphQL
import Testing

@testable import FoundationModelsSkills

/// The `skills` GraphQL endpoint (SK-5) under the conventions of EXTRAS-9:
/// the flat root fields `skills` and `skill(id:)`, the `name` alias of `id`,
/// the skills that are off listed with `enabled: false`, and the checks of
/// rule 11 of the test kit.
///
/// Each test uses ``Fixture``: a temporary layer with one skill that is on
/// and one that is off, and an unwatched registry over it.
struct SkillsGraphTests {
    // MARK: - Constants

    /// The skill that is on.
    private static let onSkillID = "alpha"

    /// The skill that its `enabled` key turns off.
    private static let offSkillID = "bravo"

    /// An id that no skill has.
    private static let missingSkillID = "nosuchskill"

    /// The skill that the probe of the `changes` subscription adds.
    private static let addedSkillID = "charlie"

    /// The canonical name of the subscription of the changes.
    private static let changesField = "changes"

    /// The alias of ``changesField`` that the endpoint rewrites.
    private static let changesAlias = "skillChanges"

    /// The description of each fixture skill.
    private static let skillDescription = "Greets a person."

    /// The one parameter of each fixture skill.
    private static let parameterName = "person"

    /// The placeholder summary of ``parameterName``.
    private static let parameterSummary = "[person]"

    /// The GraphQL name of the project layer.
    private static let projectSource = "PROJECT"

    /// The golden file of the schema, from the package root.
    private static let goldenFilePath = "Tests/Fixtures/skills.graphql"

    /// The selection of each field of a `Skill`.
    private static let skillFields = "id name description parameters source marketplace enabled"

    // MARK: - Rule 11

    /// The endpoint has the facts of a host, the response conventions of
    /// the toolkit, rewrites `skill(name:)` to `skill(id:)` and the
    /// subscription `skillChanges` to `changes`, and obeys each rule of
    /// EXTRAS-9 with no exception: rule 9 too, the `changes` subscription
    /// and the root `cursor`. The endpoint has no code of its own, thus it
    /// gives no code for rule 8.
    @Test func theEndpointConforms() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let queryProbe = GraphQLAliasProbe(
            query: "{ skill(name: \"\(Self.onSkillID)\") { id } }", from: "name", to: "id")
        let subscriptionProbe = try await fixture.changesProbe()

        let problems = await GraphQLEndpointConformance.problems(
            of: fixture.graph, scope: .sessionFolder, probes: [queryProbe, subscriptionProbe], codes: [],
            exceptions: [])

        #expect(problems.isEmpty)
    }

    /// The endpoint is `skills`, version `1`, of the session folder scope.
    @Test func theEndpointHasItsNameVersionAndScope() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        #expect(fixture.graph.name == "skills")
        #expect(fixture.graph.version == "1")
        #expect(fixture.graph.scope == .sessionFolder)
    }

    /// Each type, field, argument and enum value of the schema has a
    /// description, because a client learns the schema with introspection.
    @Test func eachPartOfTheSchemaHasADescription() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let undescribed = try GraphQLSchemaDescriptions.undescribed(in: buildSchema(source: fixture.graph.schema))

        #expect(undescribed.isEmpty)
    }

    /// The SDL schema is the schema in the golden file.
    @Test func theSchemaMatchesTheGoldenFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let goldenFile = FixtureLibrary.packageRoot().appendingPathComponent(Self.goldenFilePath)

        #expect(GraphQLSchemaGolden.problems(of: fixture.graph.schema, against: goldenFile).isEmpty)
    }

    /// The endpoint changes nothing, thus it has no `Mutation` type (D84).
    @Test func theSchemaHasNoMutationType() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        #expect(try buildSchema(source: fixture.graph.schema).mutationType == nil)
    }

    // MARK: - skills

    /// `skills` gives each field of a skill that is on.
    @Test func skillsGivesEachFieldOfASkill() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let skills = try await fixture.list("{ skills { \(Self.skillFields) } }", at: "skills")
        let skill = try #require(skills.first)

        #expect(skill["id"] as? String == Self.onSkillID)
        #expect(skill["name"] as? String == Self.onSkillID)
        #expect(skill["description"] as? String == Self.skillDescription)
        #expect(skill["parameters"] as? [String] == [Self.parameterSummary])
        #expect(skill["source"] as? String == Self.projectSource)
        #expect(skill["marketplace"] is NSNull)
        #expect(skill["enabled"] as? Bool == true)
    }

    /// `skills` lists a skill that is off too, with `enabled: false`.
    @Test func skillsListsADisabledSkillAsNotEnabled() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let skills = try await fixture.list("{ skills { id enabled } }", at: "skills")

        #expect(skills.map { skill in skill["id"] as? String } == [Self.onSkillID, Self.offSkillID])
        #expect(skills.map { skill in skill["enabled"] as? Bool } == [true, false])
    }

    /// `listSkills` is an alias of `skills`.
    @Test func listSkillsIsAnAliasOfSkills() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let skills = try await fixture.list("{ listSkills { id } }", at: "listSkills")

        #expect(skills.map { skill in skill["id"] as? String } == [Self.onSkillID, Self.offSkillID])
    }

    // MARK: - skill(id:)

    /// `skill(id:)` gives one skill, also one that is off.
    @Test func skillGivesOneSkillByItsID() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("{ skill(id: \"\(Self.offSkillID)\") { id enabled } }")
        let skill = try #require(reply.data?["skill"] as? [String: Any])

        #expect(skill["id"] as? String == Self.offSkillID)
        #expect(skill["enabled"] as? Bool == false)
    }

    /// `skill(id:)` of an id that no skill has is `null`, and no error.
    @Test func skillOfAMissingIDIsNull() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("{ skill(id: \"\(Self.missingSkillID)\") { id } }")

        #expect(reply.errors.isEmpty)
        #expect(reply.data?["skill"] is NSNull)
    }

    /// `skill(name:)` is `skill(id:)`, and the response reports the rewrite.
    @Test func skillTakesNameAsAnAliasOfID() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("{ skill(name: \"\(Self.onSkillID)\") { id } }")
        let skill = try #require(reply.data?["skill"] as? [String: Any])

        #expect(skill["id"] as? String == Self.onSkillID)
        #expect(reply.rewrites.contains { rewrite in rewrite["from"] as? String == "name" && rewrite["to"] as? String == "id" })
    }

    /// `getSkill` is an alias of `skill`.
    @Test func getSkillIsAnAliasOfSkill() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("{ getSkill(id: \"\(Self.onSkillID)\") { id } }")
        let skill = try #require(reply.data?["getSkill"] as? [String: Any])

        #expect(skill["id"] as? String == Self.onSkillID)
    }

    // MARK: - Fixtures

    /// One parsed GraphQL response.
    private struct Reply {
        /// The `data` object, or `nil` when the response has none.
        let data: [String: Any]?

        /// The `errors` list.
        let errors: [[String: Any]]

        /// The `extensions.rewrites` list.
        let rewrites: [[String: Any]]

        /// Reads a response.
        ///
        /// - Parameter json: The JSON text of the response.
        /// - Throws: An error when the text is not JSON, or a failure of
        ///   `#require` when it is not an object.
        init(json: String) throws {
            let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            data = object["data"] as? [String: Any]
            errors = object["errors"] as? [[String: Any]] ?? []
            rewrites = (object["extensions"] as? [String: Any])?["rewrites"] as? [[String: Any]] ?? []
        }
    }

    /// A temporary layer with ``onSkillID`` and ``offSkillID``, an unwatched
    /// registry over it, and the endpoint over that registry.
    ///
    /// A fake marketplace provider with no layer backs the registry, and each
    /// update of the provider reloads the registry one time, thus
    /// ``changesProbe()`` gives exactly one change.
    private struct Fixture {
        /// The temporary layer root.
        let root: URL

        /// The provider whose updates reload the registry.
        let provider = FakeMarketplaceProvider(layers: [])

        /// The endpoint under test.
        let graph: SkillsGraph

        /// Writes the two skills into a new root, and builds the endpoint.
        ///
        /// - Throws: Whatever the directory, a file write, or the schema
        ///   builder throws.
        init() throws {
            root = try HotReloadTestSupport.makeTempDirectory()
            try Self.writeSkill(id: SkillsGraphTests.onSkillID, extraFrontmatter: "", in: root)
            try Self.writeSkill(id: SkillsGraphTests.offSkillID, extraFrontmatter: "enabled: false\n", in: root)
            graph = try SkillsGraph(registry: provider.makeRegistry(projectRoot: root))
        }

        /// Makes the probe of the alias ``SkillsGraphTests/changesAlias`` of
        /// the `changes` subscription for the conformance check.
        ///
        /// The probe resumes after the cursor of now. One reload that adds
        /// ``SkillsGraphTests/addedSkillID`` then follows that cursor, and the
        /// wait for the root `cursor` to move puts its change in the buffer
        /// of the change log, thus the first response of the subscription
        /// comes at once.
        ///
        /// - Returns: The probe, which expects the rewrite from the alias to
        ///   `changes`.
        /// - Throws: An error of the endpoint, of the file write, or a
        ///   failure of `#require` when no change comes.
        func changesProbe() async throws -> GraphQLAliasProbe {
            let start = try await cursor()
            try Self.writeSkill(id: SkillsGraphTests.addedSkillID, extraFrontmatter: "", in: root)
            provider.publish(layers: [])
            try await ReloadTestSupport.newestCursor(after: start, reading: cursor)
            return GraphQLAliasProbe(
                query: "subscription($after: String) { \(SkillsGraphTests.changesAlias)(after: $after) { cursor } }",
                variables: ["after": .string(start)],
                from: SkillsGraphTests.changesAlias,
                to: SkillsGraphTests.changesField,
                kind: .subscription)
        }

        /// Queries the root `cursor`.
        ///
        /// - Returns: The cursor of the newest change.
        /// - Throws: An error of the endpoint, or a failure of `#require`.
        func cursor() async throws -> String {
            try #require(try await run("{ cursor }").data?["cursor"] as? String)
        }

        /// Runs one document with no viewer.
        ///
        /// - Parameter query: The document.
        /// - Returns: The parsed response.
        /// - Throws: An error of the endpoint, or of the parse.
        func run(_ query: String) async throws -> Reply {
            try Reply(json: await graph.execute(query: query, variables: [:], operationName: nil, viewer: nil))
        }

        /// Runs one document that must give a list, with no error.
        ///
        /// - Parameters:
        ///   - query: The document.
        ///   - key: The key of the list in `data`.
        /// - Returns: The objects of the list.
        /// - Throws: An error of the endpoint, or a failure of `#require`.
        func list(_ query: String, at key: String) async throws -> [[String: Any]] {
            let reply = try await run(query)
            #expect(reply.errors.isEmpty)
            return try #require(reply.data?[key] as? [[String: Any]])
        }

        /// Deletes the temporary root.
        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        /// Writes one fixture skill with the shared description and
        /// parameter.
        ///
        /// - Parameters:
        ///   - id: The skill id.
        ///   - extraFrontmatter: More frontmatter lines, each ending in a
        ///     newline.
        ///   - directory: The layer root.
        /// - Throws: Whatever the directory or the file write throws.
        private static func writeSkill(id: String, extraFrontmatter: String, in directory: URL) throws {
            let text =
                "---\nname: \(id)\ndescription: \(SkillsGraphTests.skillDescription)\n"
                + "arguments: \(SkillsGraphTests.parameterName)\n\(extraFrontmatter)---\nHello $\(SkillsGraphTests.parameterName).\n"
            _ = try LayerFixtureSupport.writeTextFile(text, at: "\(id)/\(SkillDiscovery.skillFileName)", in: directory)
        }
    }
}
