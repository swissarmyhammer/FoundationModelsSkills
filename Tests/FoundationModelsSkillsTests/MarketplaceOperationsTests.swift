import Foundation
import FoundationModels
import FoundationModelsExtras
import Marketplace
import Testing

@testable import FoundationModelsSkills

/// The marketplace operations of the `skills` tool (D190, D100): `add`,
/// `edit`, `remove`, `list` and `show marketplace`. Each answer is plain
/// text, and each refusal is a corrective message.
///
/// Each test uses ``Fixture``: a `MarketplaceRegistry` over an in-memory
/// storage with ``acmeID``, and the tool over an empty skill registry.
struct MarketplaceOperationsTests {
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

    /// The name of a skill that a test writes in the project layer.
    private static let skillID = "keep-me"

    /// A ref that a test writes.
    private static let newRef = "v2"

    // MARK: - list marketplace

    /// `list marketplace` names each marketplace.
    @Test func listMarketplaceNamesEachMarketplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let answer = try await fixture.call(["op": "list marketplace"])

        #expect(answer.contains("`\(Self.acmeID)`: \(Self.acmeURL)"))
    }

    /// `list marketplace` of an empty list says that the list is empty.
    @Test func listMarketplaceOfAnEmptyListSaysSo() async throws {
        let fixture = try Fixture(sources: [])
        defer { fixture.remove() }

        let answer = try await fixture.call(["op": "list marketplace"])

        #expect(answer == "No marketplace is in the list. Use `add marketplace` to add one.")
    }

    // MARK: - show marketplace

    /// `show marketplace` gives the URL of the marketplace.
    @Test func showMarketplaceGivesTheURL() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let answer = try await fixture.call(["op": "show marketplace", "id": Self.acmeID])

        #expect(answer.contains("url: \(Self.acmeURL)"))
    }

    /// `show marketplace` of an id that no marketplace has gives a
    /// corrective.
    @Test func showMarketplaceOfAMissingIDGivesACorrective() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let answer = try await fixture.call(["op": "show marketplace", "id": Self.missingID])

        #expect(answer.hasPrefix("No marketplace has the id \"\(Self.missingID)\"."))
    }

    // MARK: - add marketplace

    /// `add marketplace` adds the marketplace to the registry.
    @Test func addMarketplaceAddsTheMarketplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.call(["op": "add marketplace", "url": Self.toolsURL])

        #expect(try await fixture.ids() == [Self.acmeID, Self.toolsID])
    }

    /// `add marketplace` answers one sentence that names the id and the URL.
    @Test func addMarketplaceAnswersOneSentence() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let answer = try await fixture.call(["op": "add marketplace", "url": Self.toolsURL])

        #expect(answer == "Added the marketplace `\(Self.toolsID)`: \(Self.toolsURL).")
    }

    /// `add marketplace` with an empty URL gives the corrective of the
    /// registry.
    @Test func addMarketplaceWithAnEmptyURLGivesACorrective() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let answer = try await fixture.call(["op": "add marketplace", "url": ""])

        #expect(answer.contains("The URL is empty."))
    }

    // MARK: - edit marketplace

    /// `edit marketplace` writes the field that the call gives.
    @Test func editMarketplaceChangesTheRef() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.call(["op": "edit marketplace", "id": Self.acmeID, "ref": Self.newRef])

        #expect(try await fixture.source(of: Self.acmeID)?.ref == Self.newRef)
    }

    /// `update marketplace` is `edit marketplace`.
    @Test func updateMarketplaceIsEditMarketplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.call(["op": "update marketplace", "id": Self.acmeID, "ref": Self.newRef])

        #expect(try await fixture.source(of: Self.acmeID)?.ref == Self.newRef)
    }

    // MARK: - remove marketplace

    /// `remove marketplace` removes the marketplace from the registry.
    @Test func removeMarketplaceRemovesTheMarketplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.call(["op": "remove marketplace", "id": Self.acmeID])

        #expect(try await fixture.ids().isEmpty)
    }

    // MARK: - reset marketplace

    /// `reset marketplace` makes the list the default list of the storage.
    @Test func resetMarketplaceRestoresTheDefaultList() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.call(["op": "reset marketplace"])

        #expect(try await fixture.ids() == [Self.toolsID])
    }

    /// `reset marketplaces` (the plural noun) is `reset marketplace`.
    @Test func resetMarketplacesIsResetMarketplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.call(["op": "reset marketplaces"])

        #expect(try await fixture.ids() == [Self.toolsID])
    }

    /// `reset marketplace` answers one sentence that names the new list.
    @Test func resetMarketplaceAnswersOneSentence() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let answer = try await fixture.call(["op": "reset marketplace"])

        #expect(answer == "The marketplace list is the default list again: `\(Self.toolsID)`.")
    }

    // MARK: - A call with no op runs no write

    /// A call with no `op` whose keys fit only `add marketplace` adds no
    /// marketplace: inference never runs an operation that writes.
    @Test func aURLWithNoOpAddsNoMarketplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try await fixture.call(["url": Self.toolsURL])

        #expect(try await fixture.ids() == [Self.acmeID])
    }

    /// A call with no `op` whose keys fit only `remove skill` removes no
    /// skill.
    @Test func anIDAndALayerWithNoOpRemoveNoSkill() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let skillFile = fixture.root.appending(path: "\(Self.skillID)/SKILL.md")
        try FileManager.default.createDirectory(
            at: skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("---\nname: \(Self.skillID)\ndescription: A skill.\n---\nThe body.\n".utf8).write(to: skillFile)

        _ = try await fixture.call(["id": Self.skillID, "layer": "project"])

        #expect(FileManager.default.fileExists(atPath: skillFile.path))
    }

    // MARK: - A host with no marketplace list

    /// A tool whose context has no marketplace registry has no marketplace
    /// operation.
    @Test func aToolWithNoMarketplaceRegistryHasNoMarketplaceOperation() async throws {
        let fixture = try Fixture(withMarketplaces: false)
        defer { fixture.remove() }

        let answer = try await fixture.call(["op": "list marketplace"])

        #expect(answer.hasPrefix("Unknown operation."))
    }

    // MARK: - The registry factories

    /// A tool from `SkillsTool.make(registry:marketplaces:)` (no model) has
    /// the marketplace operations of the registry that it gets.
    @Test func theRetrievalFactoryGivesTheMarketplacesToTheTool() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = try await SkillsTool.make(
            registry: Self.emptyRegistry(at: root), marketplaces: Self.acmeMarketplaces())

        let answer = try await tool.call(arguments: GeneratedContent(properties: ["op": "list marketplace"]))

        #expect(answer.contains("`\(Self.acmeID)`: \(Self.acmeURL)"))
    }

    /// A tool from `SkillsTool.make(registry:model:marketplaces:)` has the
    /// marketplace operations of the registry that it gets.
    @Test func theModelFactoryGivesTheMarketplacesToTheTool() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = try await SkillsTool.make(
            registry: Self.emptyRegistry(at: root), model: ScriptedLanguageModel(""),
            marketplaces: Self.acmeMarketplaces())

        let answer = try await tool.call(arguments: GeneratedContent(properties: ["op": "list marketplace"]))

        #expect(answer.contains("`\(Self.acmeID)`: \(Self.acmeURL)"))
    }

    /// The full name of the retrieval factory with no `marketplaces:` still
    /// names a function. FoundationModelsAgents keeps a reference to it, and
    /// the tool that it makes has no marketplace operation.
    @Test func theRetrievalFactoryWithNoMarketplacesKeepsItsName() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let factory = SkillsTool.make(
            registry:embedder:followReloads:catalogCharacterLimit:visibilityPredicate:sandboxProbe:)
        let tool = try await factory(
            Self.emptyRegistry(at: root), nil, true, SkillsTool.defaultCatalogCharacterLimit, { _ in true }, .live)

        let answer = try await tool.call(arguments: GeneratedContent(properties: ["op": "list marketplace"]))

        #expect(answer.hasPrefix("Unknown operation."))
    }

    /// The full name of the model factory with no `marketplaces:` still names
    /// a function, and the tool that it makes has no marketplace operation.
    @Test func theModelFactoryWithNoMarketplacesKeepsItsName() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let factory = SkillsTool.make(
            registry:model:embedder:followReloads:catalogCharacterLimit:visibilityPredicate:sandboxProbe:)
        let tool = try await factory(
            Self.emptyRegistry(at: root), ScriptedLanguageModel(""), nil, true,
            SkillsTool.defaultCatalogCharacterLimit, { _ in true }, .live)

        let answer = try await tool.call(arguments: GeneratedContent(properties: ["op": "list marketplace"]))

        #expect(answer.hasPrefix("Unknown operation."))
    }

    // MARK: - Fixtures

    /// A skill registry over the empty folder `root`.
    ///
    /// - Parameter root: The folder of the one project layer.
    /// - Returns: The registry.
    private static func emptyRegistry(at root: URL) -> SkillsRegistry {
        SkillsRegistry(layers: [DotfolderStack.Layer(source: .project, root: root)], mode: .open)
    }

    /// A marketplace registry that has only the marketplace ``acmeID``.
    ///
    /// - Returns: The registry.
    private static func acmeMarketplaces() -> MarketplaceRegistry {
        MarketplaceRegistry(
            storage: InMemoryMarketplaceSourceStorage(sources: [MarketplaceSource(acmeURL, alias: acmeID)]))
    }

    /// An empty skill layer, a marketplace registry, and the tool over the
    /// two. The default list of the storage, which a reset restores, has
    /// only ``toolsURL``.
    private struct Fixture {
        /// The temporary root of the skill layer.
        let root: URL

        /// The marketplace registry, or `nil` for a tool with none.
        let marketplaces: MarketplaceRegistry?

        /// The tool under test.
        let tool: SkillsCatalogTool

        /// Builds the tool.
        ///
        /// - Parameters:
        ///   - withMarketplaces: Whether the context has a marketplace
        ///     registry.
        ///   - sources: The sources of the registry.
        /// - Throws: Whatever the folder or the tool assembly throws.
        init(
            withMarketplaces: Bool = true,
            sources: [MarketplaceSource] = [
                MarketplaceSource(MarketplaceOperationsTests.acmeURL, alias: MarketplaceOperationsTests.acmeID)
            ]
        ) throws {
            root = try HotReloadTestSupport.makeTempDirectory()
            marketplaces =
                withMarketplaces
                ? MarketplaceRegistry(
                    storage: InMemoryMarketplaceSourceStorage(
                        sources: sources, defaultSources: [MarketplaceSource(MarketplaceOperationsTests.toolsURL)]))
                : nil
            let registry = SkillsRegistry(layers: [DotfolderStack.Layer(source: .project, root: root)], mode: .open)
            let searcher = MetadataSearcher(items: registry.metadata())
            let context = try SkillsToolContext(
                registry: registry, searchAgent: SkillSearchAgent(searcher: searcher), mode: .open,
                marketplaces: marketplaces)
            tool = try SkillsTool.make(context: context)
        }

        /// Calls the tool with `properties`.
        ///
        /// - Parameter properties: The arguments of the call.
        /// - Returns: The answer of the tool.
        /// - Throws: An error of the tool.
        func call(_ properties: KeyValuePairs<String, any ConvertibleToGeneratedContent>) async throws -> String {
            try await tool.call(arguments: GeneratedContent(properties: properties))
        }

        /// The id of each marketplace of the registry, in order.
        ///
        /// - Returns: The ids.
        /// - Throws: An error of the registry, or a failure of `#require`.
        func ids() async throws -> [String] {
            try await #require(marketplaces).marketplaces().map(\.id)
        }

        /// The source of the marketplace `id`.
        ///
        /// - Parameter id: The id.
        /// - Returns: The source, or `nil` when no marketplace has the id.
        /// - Throws: An error of the registry, or a failure of `#require`.
        func source(of id: String) async throws -> MarketplaceSource? {
            try await #require(marketplaces).marketplace(id: id)?.source
        }

        /// Deletes the temporary root.
        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
