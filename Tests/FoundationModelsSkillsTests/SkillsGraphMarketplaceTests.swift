import Foundation
import FoundationModelsExtras
import Marketplace
import Testing

@testable import FoundationModelsSkills

/// The skill marketplaces of the `skills` GraphQL endpoint (D190): the
/// queries `marketplaces` and `marketplace(id:)`, the mutations
/// `addMarketplace`, `updateMarketplace` and `removeMarketplace`, their
/// errors, and the `marketplaceChanges` subscription.
///
/// Each test uses ``Fixture``: a `MarketplaceRegistry` over an in-memory
/// storage with ``acmeID``, and the endpoint over it and over an empty skill
/// registry.
struct SkillsGraphMarketplaceTests {
    // MARK: - Constants

    /// The id of the fixture marketplace: its alias.
    private static let acmeID = "acme"

    /// The URL of the fixture marketplace.
    private static let acmeURL = "github:acme/skills"

    /// The URL of a marketplace that a test adds.
    private static let toolsURL = "github:acme/tools"

    /// The id of the marketplace of ``toolsURL``: its repository name.
    private static let toolsID = "tools"

    /// An id that no marketplace has.
    private static let missingID = "nosuchmarketplace"

    /// A ref that a test writes.
    private static let newRef = "v2"

    /// A skill name that a selection takes.
    private static let selectedSkill = "review"

    /// The selection of each field of a `Marketplace`.
    private static let fields = "id url ref sha path alias skills autoUpdate"

    // MARK: - Queries

    /// `marketplaces` gives each marketplace of the registry.
    @Test func marketplacesGivesEachMarketplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("{ marketplaces { id } }")
        let list = try #require(reply.data?["marketplaces"] as? [[String: Any]])

        #expect(list.map { $0["id"] as? String } == [Self.acmeID])
    }

    /// `marketplace(id:)` gives the fields of one marketplace.
    @Test func marketplaceGivesTheURL() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("{ marketplace(id: \"\(Self.acmeID)\") { \(Self.fields) } }")
        let marketplace = try #require(reply.data?["marketplace"] as? [String: Any])

        #expect(marketplace["url"] as? String == Self.acmeURL)
    }

    /// A marketplace that takes all its skills has `skills: null`.
    @Test func aMarketplaceThatTakesAllSkillsHasNoSkillList() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("{ marketplace(id: \"\(Self.acmeID)\") { skills } }")
        let marketplace = try #require(reply.data?["marketplace"] as? [String: Any])

        #expect(marketplace["skills"] is NSNull)
    }

    /// `marketplace(id:)` of an id that no marketplace has is `null`.
    @Test func marketplaceOfAMissingIDIsNull() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("{ marketplace(id: \"\(Self.missingID)\") { id } }")

        #expect(reply.data?["marketplace"] is NSNull)
    }

    /// An endpoint with no marketplace registry gives no marketplace.
    @Test func anEndpointWithNoMarketplaceRegistryGivesNoMarketplace() async throws {
        let fixture = try Fixture(withMarketplaces: false)
        defer { fixture.remove() }

        let reply = try await fixture.run("{ marketplaces { id } }")

        #expect((reply.data?["marketplaces"] as? [Any])?.isEmpty == true)
    }

    // MARK: - addMarketplace

    /// `addMarketplace` adds the marketplace to the registry.
    @Test func addMarketplaceAddsTheMarketplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.run("mutation { addMarketplace(input: { url: \"\(Self.toolsURL)\" }) { id } }")

        #expect(try await fixture.ids() == [Self.acmeID, Self.toolsID])
    }

    /// `addMarketplace` keeps the skill selection of the input.
    @Test func addMarketplaceKeepsTheSkillSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { addMarketplace(input: { url: \"\(Self.toolsURL)\", skills: [\"\(Self.selectedSkill)\"] }) "
                + "{ skills } }")
        let marketplace = try #require(reply.data?["addMarketplace"] as? [String: Any])

        #expect(marketplace["skills"] as? [String] == [Self.selectedSkill])
    }

    /// `addMarketplace` of an id that the list has gives
    /// `DUPLICATE_MARKETPLACE`.
    @Test func addMarketplaceOfADuplicateIDGivesDuplicateMarketplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { addMarketplace(input: { url: \"\(Self.toolsURL)\", alias: \"\(Self.acmeID)\" }) { id } }")

        #expect(reply.codes == ["DUPLICATE_MARKETPLACE"])
    }

    /// `addMarketplace` of a URL that is not usable gives
    /// `INVALID_MARKETPLACE`.
    @Test func addMarketplaceOfABadURLGivesInvalidMarketplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("mutation { addMarketplace(input: { url: \"\" }) { id } }")

        #expect(reply.codes == ["INVALID_MARKETPLACE"])
    }

    /// A mutation of an endpoint with no marketplace registry gives
    /// `MARKETPLACES_UNAVAILABLE`.
    @Test func addMarketplaceWithNoRegistryGivesMarketplacesUnavailable() async throws {
        let fixture = try Fixture(withMarketplaces: false)
        defer { fixture.remove() }

        let reply = try await fixture.run("mutation { addMarketplace(input: { url: \"\(Self.toolsURL)\" }) { id } }")

        #expect(reply.codes == ["MARKETPLACES_UNAVAILABLE"])
    }

    // MARK: - updateMarketplace

    /// `updateMarketplace` changes the field that the input gives.
    @Test func updateMarketplaceChangesTheRef() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { updateMarketplace(input: { id: \"\(Self.acmeID)\", ref: \"\(Self.newRef)\" }) { ref } }")
        let marketplace = try #require(reply.data?["updateMarketplace"] as? [String: Any])

        #expect(marketplace["ref"] as? String == Self.newRef)
    }

    /// `updateMarketplace` keeps a field that the input does not give.
    @Test func updateMarketplaceKeepsTheURL() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { updateMarketplace(input: { id: \"\(Self.acmeID)\", ref: \"\(Self.newRef)\" }) { url } }")
        let marketplace = try #require(reply.data?["updateMarketplace"] as? [String: Any])

        #expect(marketplace["url"] as? String == Self.acmeURL)
    }

    /// `updateMarketplace` with an empty text clears that field.
    @Test func updateMarketplaceWithAnEmptyTextClearsTheField() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.run(
            "mutation { updateMarketplace(input: { id: \"\(Self.acmeID)\", ref: \"\(Self.newRef)\" }) { id } }")
        let reply = try await fixture.run(
            "mutation { updateMarketplace(input: { id: \"\(Self.acmeID)\", ref: \"\" }) { ref } }")
        let marketplace = try #require(reply.data?["updateMarketplace"] as? [String: Any])

        #expect(marketplace["ref"] is NSNull)
    }

    /// `updateMarketplace` with `allSkills: true` takes all the skills again.
    @Test func updateMarketplaceWithAllSkillsClearsTheSelection() async throws {
        let fixture = try Fixture(acmeSelection: .skills([Self.selectedSkill]))
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { updateMarketplace(input: { id: \"\(Self.acmeID)\", allSkills: true }) { skills } }")
        let marketplace = try #require(reply.data?["updateMarketplace"] as? [String: Any])

        #expect(marketplace["skills"] is NSNull)
    }

    /// `updateMarketplace` of an id that no marketplace has gives
    /// `NOT_FOUND`.
    @Test func updateMarketplaceOfAMissingIDGivesNotFound() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run(
            "mutation { updateMarketplace(input: { id: \"\(Self.missingID)\", ref: \"\(Self.newRef)\" }) { id } }")

        #expect(reply.codes == ["NOT_FOUND"])
    }

    // MARK: - removeMarketplace

    /// `removeMarketplace` removes the marketplace from the registry.
    @Test func removeMarketplaceRemovesTheMarketplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.run("mutation { removeMarketplace(input: { id: \"\(Self.acmeID)\" }) { id } }")

        #expect(try await fixture.ids().isEmpty)
    }

    /// `removeMarketplace` of an id that no marketplace has gives
    /// `NOT_FOUND`.
    @Test func removeMarketplaceOfAMissingIDGivesNotFound() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let reply = try await fixture.run("mutation { removeMarketplace(input: { id: \"\(Self.missingID)\" }) { id } }")

        #expect(reply.codes == ["NOT_FOUND"])
    }

    // MARK: - marketplaceChanges

    /// `addMarketplace` gives one change with the new id.
    @Test func addMarketplaceGivesAChange() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let start = try await fixture.marketplaceCursor()

        _ = try await fixture.run("mutation { addMarketplace(input: { url: \"\(Self.toolsURL)\" }) { id } }")
        let event = try await fixture.firstChange(after: start)

        #expect(event["added"] as? [String] == [Self.toolsID])
    }

    /// An update that changes the id gives the old id as removed and the new
    /// id as added.
    @Test func updateMarketplaceOfTheAliasGivesARemoveAndAnAdd() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let start = try await fixture.marketplaceCursor()

        _ = try await fixture.run(
            "mutation { updateMarketplace(input: { id: \"\(Self.acmeID)\", alias: \"\(Self.toolsID)\" }) { id } }")
        let event = try await fixture.firstChange(after: start)

        #expect(event["removed"] as? [String] == [Self.acmeID] && event["added"] as? [String] == [Self.toolsID])
    }

    /// `removeMarketplace` gives one change with the removed id.
    @Test func removeMarketplaceGivesAChange() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let start = try await fixture.marketplaceCursor()

        _ = try await fixture.run("mutation { removeMarketplace(input: { id: \"\(Self.acmeID)\" }) { id } }")
        let event = try await fixture.firstChange(after: start)

        #expect(event["removed"] as? [String] == [Self.acmeID])
    }

    // MARK: - Fixtures

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

    /// An empty skill layer, a marketplace registry with ``acmeID`` (or no
    /// marketplace registry), and the endpoint over the two.
    private struct Fixture {
        /// The temporary root of the skill layer.
        let root: URL

        /// The marketplace registry, or `nil` for an endpoint with none.
        let marketplaces: MarketplaceRegistry?

        /// The endpoint under test.
        let graph: SkillsGraph

        /// Builds the endpoint.
        ///
        /// - Parameters:
        ///   - withMarketplaces: Whether the endpoint has a marketplace
        ///     registry.
        ///   - acmeSelection: The skill selection of ``acmeID``.
        /// - Throws: Whatever the folder or the schema builder throws.
        init(withMarketplaces: Bool = true, acmeSelection: SkillSelection = .all) throws {
            root = try HotReloadTestSupport.makeTempDirectory()
            let source = MarketplaceSource(
                SkillsGraphMarketplaceTests.acmeURL, alias: SkillsGraphMarketplaceTests.acmeID, select: acmeSelection)
            marketplaces =
                withMarketplaces
                ? MarketplaceRegistry(storage: InMemoryMarketplaceSourceStorage(sources: [source])) : nil
            let registry = SkillsRegistry(layers: [DotfolderStack.Layer(source: .project, root: root)], mode: .open)
            graph = try SkillsGraph(registry: registry, marketplaces: marketplaces)
        }

        /// Runs one document with no viewer.
        ///
        /// - Parameter query: The document.
        /// - Returns: The parsed response.
        /// - Throws: An error of the endpoint, or of the parse.
        func run(_ query: String) async throws -> Reply {
            try Reply(json: await graph.execute(query: query, variables: [:], operationName: nil, viewer: nil))
        }

        /// The id of each marketplace of the registry, in order.
        ///
        /// - Returns: The ids.
        /// - Throws: An error of the registry, or a failure of `#require`
        ///   when the fixture has no registry.
        func ids() async throws -> [String] {
            try await #require(marketplaces).marketplaces().map(\.id)
        }

        /// Queries the root `marketplaceCursor`.
        ///
        /// - Returns: The cursor of the newest marketplace change.
        /// - Throws: An error of the endpoint, or a failure of `#require`.
        func marketplaceCursor() async throws -> String {
            try #require(try await run("{ marketplaceCursor }").data?["marketplaceCursor"] as? String)
        }

        /// The first event of `marketplaceChanges` after `cursor`.
        ///
        /// - Parameter cursor: The cursor to resume after.
        /// - Returns: The event object.
        /// - Throws: An error of the endpoint, or a failure of `#require`
        ///   when the stream ends with no event.
        func firstChange(after cursor: String) async throws -> [String: Any] {
            let stream = try await graph.subscribe(
                query: "subscription { marketplaceChanges(after: \"\(cursor)\") { added changed removed } }",
                variables: [:], operationName: nil, viewer: nil)
            var iterator = stream.makeAsyncIterator()
            let response = try #require(try await iterator.next())
            return try #require(try GraphQLTestSupport.data(of: response)["marketplaceChanges"] as? [String: Any])
        }

        /// Deletes the temporary root.
        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
