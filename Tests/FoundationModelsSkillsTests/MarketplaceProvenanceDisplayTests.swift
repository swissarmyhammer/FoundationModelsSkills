import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the marketplace source text of a display row (marketplace.md
/// §9.1).
///
/// A `commandListing()` row names the marketplace that a skill came from. A
/// local skill names no marketplace. When the catalog of the marketplace has
/// no version, the row shows the short commit.
///
/// The model-facing `list skill` answer gives one line for each skill:
/// `- <id>: <description>`. That line does not show the source, and it never
/// shows the URL of a marketplace.
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

    /// The text that starts the path of a URL. No `list skill` answer may
    /// hold it.
    private static let urlSchemeSeparator = "://"

    // MARK: - list skill

    @Test func noListSkillRowShowsTheURLOfTheMarketplace() async throws {
        let fixture = try Fixture()

        let answer = try await fixture.listSkillAnswer()

        #expect(
            SkillLineReader.ids(in: answer).contains(Self.marketplaceSkillID),
            "the answer must list the marketplace skill, or the check below proves nothing")
        #expect(!answer.contains(Self.urlSchemeSeparator))
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
        /// gives the plain answer.
        ///
        /// The case goes through the real tool, thus it reads the text that
        /// the model sees.
        ///
        /// - Returns: The plain text of the `list skill` answer.
        /// - Throws: Whatever the factory or the dispatch throws.
        func listSkillAnswer() async throws -> String {
            let tool = try await SkillsTool.make(registry: makeRegistry())
            return try await tool.call(arguments: GeneratedContent(properties: ["op": "list skill"]))
        }
    }
}
