import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the marketplace source text of a display row (marketplace.md
/// §9.1): a `list skill` row and a `commandListing()` row both name the
/// marketplace a skill came from, a local skill names none, and a
/// marketplace whose catalog carries no version falls back to the short
/// commit.
struct MarketplaceProvenanceDisplayTests {
    /// The display id of the marketplace every case here builds.
    private static let marketplaceID = "swissarmyhammer-skills"

    /// The catalog version of the marketplace, when the case gives it one.
    private static let catalogVersion = "1.2.0"

    /// The commit of the snapshot of the marketplace.
    private static let commit = "abc1234def5678"

    /// The first characters of ``commit``: the text a row shows when the
    /// catalog carries no version.
    private static let shortCommit = "abc1234"

    /// The id of the skill that only the marketplace root holds.
    private static let marketplaceSkillID = "review"

    /// The id of the skill that only the local root holds.
    private static let localSkillID = "commit"

    // MARK: - list skill

    @Test func theListSkillRowOfAMarketplaceSkillNamesTheMarketplaceAndTheCatalogVersion() async throws {
        let fixture = try Fixture()

        let rows = try await fixture.listSkillRows()

        let row = try #require(rows.first { $0.id == Self.marketplaceSkillID })
        #expect(row.source == "\(Self.marketplaceID)@\(Self.catalogVersion)")
    }

    @Test func theListSkillRowOfALocalSkillNamesNoSource() async throws {
        let fixture = try Fixture()

        let rows = try await fixture.listSkillRows()

        let row = try #require(rows.first { $0.id == Self.localSkillID })
        #expect(row.source == nil)
    }

    @Test func theListSkillRowFallsBackToTheShortCommitWhenTheCatalogHasNoVersion() async throws {
        let fixture = try Fixture(catalogVersion: nil)

        let rows = try await fixture.listSkillRows()

        let row = try #require(rows.first { $0.id == Self.marketplaceSkillID })
        #expect(row.source == "\(Self.marketplaceID)@\(Self.shortCommit)")
    }

    @Test func noListSkillRowShowsTheURLOfTheMarketplace() async throws {
        let fixture = try Fixture()

        let rows = try await fixture.listSkillRows()

        #expect(rows.allSatisfy { $0.source?.contains("://") != true })
    }

    // MARK: - commandListing()

    @Test func theCommandListingRowOfAMarketplaceSkillNamesTheMarketplaceAndTheCatalogVersion() throws {
        let fixture = try Fixture()

        let listing = fixture.makeRegistry().commandListing()

        let row = try #require(listing.first { $0.id == Self.marketplaceSkillID })
        #expect(row.source == "\(Self.marketplaceID)@\(Self.catalogVersion)")
    }

    @Test func theCommandListingRowOfALocalSkillNamesNoSource() throws {
        let fixture = try Fixture()

        let listing = fixture.makeRegistry().commandListing()

        let row = try #require(listing.first { $0.id == Self.localSkillID })
        #expect(row.source == nil)
    }

    @Test func theCommandListingRowFallsBackToTheShortCommitWhenTheCatalogHasNoVersion() throws {
        let fixture = try Fixture(catalogVersion: nil)

        let listing = fixture.makeRegistry().commandListing()

        let row = try #require(listing.first { $0.id == Self.marketplaceSkillID })
        #expect(row.source == "\(Self.marketplaceID)@\(Self.shortCommit)")
    }

    // MARK: - Fixture

    /// One marketplace root and one local project root, each holding a skill
    /// id the other does not, plus the provider the registry is built over.
    private struct Fixture {
        /// The root of the marketplace layer.
        let marketplaceRoot: URL

        /// The root of the local project layer.
        let localRoot: URL

        /// The provider the registry subscribes to.
        let provider: FakeMarketplaceProvider

        /// Writes the two roots and builds the provider.
        ///
        /// - Parameter catalogVersion: The `version` field of the catalog of
        ///   the marketplace, or `nil` for a catalog with no version. The
        ///   default is
        ///   ``MarketplaceProvenanceDisplayTests/catalogVersion``.
        /// - Throws: The error of a folder or file write.
        init(catalogVersion: String? = MarketplaceProvenanceDisplayTests.catalogVersion) throws {
            marketplaceRoot = try MarketplaceTestSupport.makeTempDirectory()
            localRoot = try MarketplaceTestSupport.makeTempDirectory()

            try ReloadTestSupport.writeSkillFile(
                id: MarketplaceProvenanceDisplayTests.marketplaceSkillID, in: marketplaceRoot)
            try ReloadTestSupport.writeSkillFile(
                id: MarketplaceProvenanceDisplayTests.localSkillID, in: localRoot)

            provider = FakeMarketplaceProvider(layers: [
                MarketplaceTestSupport.makeMarketplaceLayer(
                    root: marketplaceRoot, id: MarketplaceProvenanceDisplayTests.marketplaceID,
                    sha: MarketplaceProvenanceDisplayTests.commit, catalogVersion: catalogVersion)
            ])
        }

        /// Builds a registry over the provider and a stack whose only layer
        /// is the local project root.
        ///
        /// - Returns: The registry, with watching off.
        func makeRegistry() -> SkillsRegistry {
            var stack = DotfolderStack(name: "skills", workingDirectory: localRoot, environment: [:])
            stack.layers = [DotfolderStack.Layer(source: .project, root: localRoot)]
            return SkillsRegistry(marketplaces: provider, stack: stack)
        }

        /// Dispatches one `list skill` operation through the fused tool and
        /// decodes the rows it returned.
        ///
        /// Goes through the real tool, and not through `SkillRow` directly,
        /// so that the case reads the JSON a host actually sees.
        ///
        /// - Returns: The rows of the catalog.
        /// - Throws: Whatever the factory, the dispatch, or the JSON decode
        ///   throws.
        func listSkillRows() async throws -> [Row] {
            let tool = try await SkillsTool.make(registry: makeRegistry())
            let json = try await tool.call(
                arguments: GeneratedContent(properties: ["op": "list skill"]))
            return try JSONDecoder().decode(ListResponse.self, from: Data(json.utf8)).skills
        }
    }

    /// One `list skill` row, as this suite reads it back.
    ///
    /// A decode-side mirror of `SkillRow`, which is `Encodable` only. It
    /// names the two fields these cases assert on.
    private struct Row: Decodable {
        /// The skill's canonical id.
        let id: String

        /// The marketplace the skill came from, or `nil` for a local skill.
        let source: String?
    }

    /// One `list skill` result, as this suite reads it back.
    private struct ListResponse: Decodable {
        /// The rows of the catalog.
        let skills: [Row]
    }
}
