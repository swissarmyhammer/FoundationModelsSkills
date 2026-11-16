import Foundation
import FoundationModelsExtras
import GraphQL
import Testing

@testable import FoundationModelsSkills

/// The skill mutations of the `skills` GraphQL endpoint (D190): `addSkill`,
/// `updateSkill` and `removeSkill`, their errors, the `body` and
/// `rawDescription` fields that an editor reads, and the change event of each
/// mutation.
///
/// Each test uses ``Fixture``: a registry with a defaults layer, a user layer
/// and a project layer. The defaults layer holds ``readOnlySkillID`` and the
/// user layer holds ``userSkillID``.
struct SkillsGraphMutationTests {
    // MARK: - Constants

    /// The skill of the user layer.
    private static let userSkillID = "mine"

    /// The skill that only the read-only defaults layer holds.
    private static let readOnlySkillID = "base"

    /// The id of a skill that a test adds.
    private static let newSkillID = "fresh"

    /// An id that no layer holds.
    private static let missingSkillID = "nosuchskill"

    /// An id that is not one folder name.
    private static let badSkillID = "a/b"

    /// The description of each fixture skill.
    private static let fixtureDescription = "Greets a person."

    /// The body of each fixture skill.
    private static let fixtureBody = "Say hello."

    /// A description that a mutation writes.
    private static let newDescription = "Says goodbye: politely."

    /// A body that a mutation writes.
    private static let newBody = "Say goodbye."

    /// A frontmatter line of the user skill that an update must keep.
    private static let keptFrontmatterLine = "license: MIT"

    /// The selection of a `Skill` in each mutation.
    private static let skillSelection = "{ id rawDescription body source }"

    // MARK: - addSkill

    /// `addSkill` with no layer writes the skill in the user layer.
    @Test func addSkillWritesTheSkillInTheUserLayer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.run(Self.addDocument(id: Self.newSkillID))

        #expect(fixture.skillFileExists(Self.newSkillID, in: .user))
    }

    /// `addSkill` gives the new skill.
    @Test func addSkillGivesTheNewSkill() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(Self.addDocument(id: Self.newSkillID))
        let skill = try #require(reply.data?["addSkill"] as? [String: Any])

        #expect(skill["rawDescription"] as? String == Self.newDescription)
    }

    /// `addSkill` writes the body that the input gives.
    @Test func addSkillWritesTheBody() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(Self.addDocument(id: Self.newSkillID))
        let skill = try #require(reply.data?["addSkill"] as? [String: Any])

        #expect((skill["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == Self.newBody)
    }

    /// `addSkill` with the layer `PROJECT` writes the project layer.
    @Test func addSkillWithTheProjectLayerWritesTheProjectLayer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.run(Self.addDocument(id: Self.newSkillID, layer: "PROJECT"))

        #expect(fixture.skillFileExists(Self.newSkillID, in: .project))
    }

    /// `addSkill` of an id that the layer holds gives `SKILL_EXISTS`.
    @Test func addSkillOfAnExistingSkillGivesSkillExists() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(Self.addDocument(id: Self.userSkillID))

        #expect(reply.codes == ["SKILL_EXISTS"])
    }

    /// `addSkill` of an id that is not one folder name gives `INVALID_SKILL`.
    @Test func addSkillOfABadIDGivesInvalidSkill() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(Self.addDocument(id: Self.badSkillID))

        #expect(reply.codes == ["INVALID_SKILL"])
    }

    /// `addSkill` with an empty description gives `INVALID_SKILL`, because
    /// the validator refuses a skill with no description.
    @Test func addSkillWithAnEmptyDescriptionGivesInvalidSkill() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { addSkill(input: { id: \"\(Self.newSkillID)\", description: \"\" }) { id } }")

        #expect(reply.codes == ["INVALID_SKILL"])
    }

    // MARK: - updateSkill

    /// `updateSkill` changes the description of the skill.
    @Test func updateSkillChangesTheDescription() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { updateSkill(input: { id: \"\(Self.userSkillID)\", description: \"\(Self.newDescription)\" }) "
                + "\(Self.skillSelection) }")
        let skill = try #require(reply.data?["updateSkill"] as? [String: Any])

        #expect(skill["rawDescription"] as? String == Self.newDescription)
    }

    /// `updateSkill` with only a description keeps the other frontmatter
    /// keys of the file.
    @Test func updateSkillKeepsTheOtherFrontmatterKeys() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.run(
            "mutation { updateSkill(input: { id: \"\(Self.userSkillID)\", description: \"\(Self.newDescription)\" }) "
                + "{ id } }")

        let text = try fixture.skillFileText(Self.userSkillID, in: .user)

        #expect(text.contains(Self.keptFrontmatterLine) && text.contains(Self.newDescription))
    }

    /// `updateSkill` with only a body changes the body of the skill.
    @Test func updateSkillChangesTheBody() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { updateSkill(input: { id: \"\(Self.userSkillID)\", body: \"\(Self.newBody)\" }) "
                + "\(Self.skillSelection) }")
        let skill = try #require(reply.data?["updateSkill"] as? [String: Any])

        #expect((skill["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == Self.newBody)
    }

    /// `updateSkill` with only a body keeps the description.
    @Test func updateSkillOfTheBodyKeepsTheDescription() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { updateSkill(input: { id: \"\(Self.userSkillID)\", body: \"\(Self.newBody)\" }) "
                + "\(Self.skillSelection) }")
        let skill = try #require(reply.data?["updateSkill"] as? [String: Any])

        #expect(skill["rawDescription"] as? String == Self.fixtureDescription)
    }

    /// `updateSkill` of an id that no layer holds gives `NOT_FOUND`.
    @Test func updateSkillOfAMissingSkillGivesNotFound() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { updateSkill(input: { id: \"\(Self.missingSkillID)\", body: \"x\" }) { id } }")

        #expect(reply.codes == ["NOT_FOUND"])
    }

    /// `updateSkill` of a skill that only a read-only layer holds gives
    /// `SKILL_READ_ONLY`.
    @Test func updateSkillOfAReadOnlySkillGivesSkillReadOnly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { updateSkill(input: { id: \"\(Self.readOnlySkillID)\", body: \"x\" }) { id } }")

        #expect(reply.codes == ["SKILL_READ_ONLY"])
    }

    /// `updateSkill` with a layer that does not hold the skill gives
    /// `NOT_FOUND`.
    @Test func updateSkillWithALayerThatDoesNotHoldTheSkillGivesNotFound() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { updateSkill(input: { id: \"\(Self.userSkillID)\", body: \"x\", layer: PROJECT }) { id } }")

        #expect(reply.codes == ["NOT_FOUND"])
    }

    // MARK: - removeSkill

    /// `removeSkill` deletes the folder of the skill.
    @Test func removeSkillDeletesTheSkill() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.run("mutation { removeSkill(input: { id: \"\(Self.userSkillID)\" }) { id } }")

        #expect(!fixture.skillFileExists(Self.userSkillID, in: .user))
    }

    /// `removeSkill` gives the layer that it changed.
    @Test func removeSkillGivesTheLayer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { removeSkill(input: { id: \"\(Self.userSkillID)\" }) { id layer skill { id } } }")
        let payload = try #require(reply.data?["removeSkill"] as? [String: Any])

        #expect(payload["layer"] as? String == "USER")
    }

    /// `removeSkill` of a skill that only a read-only layer holds gives
    /// `SKILL_READ_ONLY`.
    @Test func removeSkillOfAReadOnlySkillGivesSkillReadOnly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("mutation { removeSkill(input: { id: \"\(Self.readOnlySkillID)\" }) { id } }")

        #expect(reply.codes == ["SKILL_READ_ONLY"])
    }

    /// `removeSkill` of an id that no layer holds gives `NOT_FOUND`.
    @Test func removeSkillOfAMissingSkillGivesNotFound() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("mutation { removeSkill(input: { id: \"\(Self.missingSkillID)\" }) { id } }")

        #expect(reply.codes == ["NOT_FOUND"])
    }

    // MARK: - Query fields and change events

    /// `skill(id:)` gives the body of the `SKILL.md`, not rendered.
    @Test func skillGivesTheBody() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("{ skill(id: \"\(Self.userSkillID)\") { body } }")
        let skill = try #require(reply.data?["skill"] as? [String: Any])

        #expect((skill["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == Self.fixtureBody)
    }

    /// A mutation gives one change event with the id of the skill.
    @Test func addSkillGivesAChangeEvent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let start = try await GraphQLTestSupport.cursor(of: fixture.graph)

        _ = try await fixture.run(Self.addDocument(id: Self.newSkillID))
        let stream = try await fixture.graph.subscribe(
            query: "subscription { changes(after: \"\(start)\") { added } }", variables: [:], operationName: nil,
            viewer: nil)
        var iterator = stream.makeAsyncIterator()
        let event = try GraphQLTestSupport.changeEvent(in: try #require(try await iterator.next()))

        #expect(event["added"] as? [String] == [Self.newSkillID])
    }

    // MARK: - Fixtures

    /// The `addSkill` document for `id`, with the shared description and
    /// body.
    ///
    /// - Parameters:
    ///   - id: The id of the new skill.
    ///   - layer: The GraphQL name of the layer, or `nil` for no layer.
    /// - Returns: The document.
    private static func addDocument(id: String, layer: String? = nil) -> String {
        let layerField = layer.map { ", layer: \($0)" } ?? ""
        return "mutation { addSkill(input: { id: \"\(id)\", description: \"\(newDescription)\", "
            + "body: \"\(newBody)\"\(layerField) }) \(skillSelection) }"
    }

    /// One parsed GraphQL response.
    private struct Reply {
        /// The `data` object, or `nil` when the response has none.
        let data: [String: Any]?

        /// The `extensions.code` of each error.
        let codes: [String]

        /// Reads a response.
        ///
        /// - Parameter json: The JSON text of the response.
        /// - Throws: An error when the text is not a JSON object.
        init(json: String) throws {
            data = try GraphQLTestSupport.object(json)["data"] as? [String: Any]
            codes = try GraphQLTestSupport.codes(of: json)
        }
    }

    /// A registry with a defaults, a user and a project layer, and the
    /// endpoint over it.
    private struct Fixture {
        /// The source of each layer, lowest precedence first.
        let sources: [DotfolderStack.Source] = [.defaults, .user, .project]

        /// The root of each layer, in the order of ``sources``.
        let directories: [URL]

        /// The endpoint under test.
        let graph: SkillsGraph

        /// Writes the fixture skills and builds the endpoint.
        ///
        /// - Throws: Whatever a folder, a file write or the schema builder
        ///   throws.
        init() throws {
            directories = try LayerFixtureSupport.makeLayerDirectories(count: sources.count)
            try Self.writeSkill(id: SkillsGraphMutationTests.readOnlySkillID, extraFrontmatter: "", in: directories[0])
            try Self.writeSkill(
                id: SkillsGraphMutationTests.userSkillID,
                extraFrontmatter: "\(SkillsGraphMutationTests.keptFrontmatterLine)\n", in: directories[1])
            let registry = SkillsRegistry(
                layers: zip(sources, directories).map { DotfolderStack.Layer(source: $0, root: $1) }, mode: .open)
            graph = try SkillsGraph(registry: registry)
        }

        /// Runs one document with no viewer.
        ///
        /// - Parameter query: The document.
        /// - Returns: The parsed response.
        /// - Throws: An error of the endpoint, or of the parse.
        func run(_ query: String) async throws -> Reply {
            try Reply(json: await graph.execute(query: query, variables: [:], operationName: nil, viewer: nil))
        }

        /// Whether the layer of `source` holds the skill file of `id`.
        ///
        /// - Parameters:
        ///   - id: The id of the skill.
        ///   - source: The source of the layer.
        /// - Returns: `true` when the file exists.
        func skillFileExists(_ id: String, in source: DotfolderStack.Source) -> Bool {
            FileManager.default.fileExists(atPath: skillFile(id, in: source).path)
        }

        /// The text of the skill file of `id` in the layer of `source`.
        ///
        /// - Parameters:
        ///   - id: The id of the skill.
        ///   - source: The source of the layer.
        /// - Returns: The text.
        /// - Throws: Whatever the read throws.
        func skillFileText(_ id: String, in source: DotfolderStack.Source) throws -> String {
            try String(contentsOf: skillFile(id, in: source), encoding: .utf8)
        }

        /// Deletes the layer roots.
        func remove() {
            LayerFixtureSupport.removeDirectories(directories)
        }

        /// The skill file of `id` in the layer of `source`.
        ///
        /// - Parameters:
        ///   - id: The id of the skill.
        ///   - source: The source of the layer.
        /// - Returns: The URL of the file.
        private func skillFile(_ id: String, in source: DotfolderStack.Source) -> URL {
            let index = sources.firstIndex(of: source) ?? sources.startIndex
            return directories[index].appendingPathComponent(id).appendingPathComponent(SkillDiscovery.skillFileName)
        }

        /// Writes one fixture skill with the shared description and body.
        ///
        /// - Parameters:
        ///   - id: The skill id.
        ///   - extraFrontmatter: More frontmatter lines, each ending in a
        ///     newline.
        ///   - directory: The layer root.
        /// - Throws: Whatever the folder or the file write throws.
        private static func writeSkill(id: String, extraFrontmatter: String, in directory: URL) throws {
            let text =
                "---\nname: \(id)\ndescription: \(SkillsGraphMutationTests.fixtureDescription)\n\(extraFrontmatter)---\n"
                + "\(SkillsGraphMutationTests.fixtureBody)\n"
            _ = try LayerFixtureSupport.writeTextFile(text, at: "\(id)/\(SkillDiscovery.skillFileName)", in: directory)
        }
    }
}
