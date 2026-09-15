import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Tests for the marketplace.md §6.5 (decision 9) partial scope: the Stencil
/// partials stack of one render holds the marketplace layer that won plus the
/// local layers, and no other marketplace layer.
///
/// Every case builds a `SkillsRegistry` over real temporary folders with
/// `SkillsRegistry.init(layers:)`, so the render runs through the same
/// `RenderPipeline` a host gets.
struct MarketplacePartialScopeTests {
    /// The name each layer gives its partial, and that each fixture skill
    /// includes.
    private static let partialName = "header"

    /// The body of each fixture skill: one include of the `header` partial.
    private static let includeHeaderBody = "{% include \"\(partialName)\" %}"

    /// The path of the `header` partial inside one layer root.
    private static let partialPath = "_partials/\(partialName).md"

    /// The newline that `ReloadTestSupport.writeSkillFile` puts after the
    /// body, and that each render therefore keeps after the included text.
    private static let bodyTrailingNewline = "\n"

    /// The text of the `header` partial of marketplace A.
    private static let headerFromMarketplaceA = "header from marketplace A"

    /// The text of the `header` partial of marketplace B.
    private static let headerFromMarketplaceB = "header from marketplace B"

    /// The text of the `header` partial of the local project layer.
    private static let headerFromProject = "header from the project"

    /// The id of the fixture skill of marketplace A.
    private static let marketplaceSkillID = "marketplace-a-skill"

    /// The id of the fixture skill of the local project layer.
    private static let localSkillID = "local-project-skill"

    /// The folder of the marketplace A layer inside the temporary root.
    private static let marketplaceAFolder = "marketplace-a"

    /// The folder of the marketplace B layer inside the temporary root.
    private static let marketplaceBFolder = "marketplace-b"

    /// The folder of the local project layer inside the temporary root.
    private static let projectFolder = "project"

    /// A registry over two marketplace layers and one local project layer,
    /// with one skill in marketplace A and one skill in the project layer.
    ///
    /// Marketplace A ships `_partials/header.md`, and marketplace B ships a
    /// different `_partials/header.md`. B sits after A in the layer order, so
    /// an unscoped partials stack gives B's text to a skill of A.
    ///
    /// - Parameter projectHeader: The text of the `_partials/header.md` file
    ///   of the project layer, or `nil` to write no such file.
    /// - Returns: The registry, and its temporary root for clean-up.
    /// - Throws: The error of a folder or file write.
    private static func makeRegistry(projectHeader: String? = nil) throws -> (registry: SkillsRegistry, root: URL) {
        let projectFiles = projectHeader.map { ["\(projectFolder)/\(partialPath)": $0] } ?? [:]
        let files = [
            "\(marketplaceAFolder)/\(partialPath)": headerFromMarketplaceA,
            "\(marketplaceBFolder)/\(partialPath)": headerFromMarketplaceB,
        ].merging(projectFiles) { _, projectFile in projectFile }
        let root = try MarketplaceTestSupport.makeTempDirectory(withFiles: files)

        let marketplaceARoot = root.appendingPathComponent(marketplaceAFolder, isDirectory: true)
        let projectRoot = root.appendingPathComponent(projectFolder, isDirectory: true)
        try ReloadTestSupport.writeSkillFile(id: marketplaceSkillID, in: marketplaceARoot, body: includeHeaderBody)
        try ReloadTestSupport.writeSkillFile(id: localSkillID, in: projectRoot, body: includeHeaderBody)

        let registry = SkillsRegistry(
            layers: [
                DotfolderStack.Layer(source: .marketplace, root: marketplaceARoot),
                DotfolderStack.Layer(
                    source: .marketplace, root: root.appendingPathComponent(marketplaceBFolder, isDirectory: true)),
                DotfolderStack.Layer(source: .project, root: projectRoot),
            ])
        return (registry: registry, root: root)
    }

    @Test func aMarketplaceSkillResolvesItsOwnPartialAndNotTheOneOfAnotherMarketplace() throws {
        let fixture = try Self.makeRegistry()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let rendered = try fixture.registry.call(id: Self.marketplaceSkillID)

        #expect(rendered == Self.headerFromMarketplaceA + Self.bodyTrailingNewline)
    }

    @Test func aLocalPartialOverridesTheMarketplacePartialOfTheSameName() throws {
        let fixture = try Self.makeRegistry(projectHeader: Self.headerFromProject)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let rendered = try fixture.registry.call(id: Self.marketplaceSkillID)

        #expect(rendered == Self.headerFromProject + Self.bodyTrailingNewline)
    }

    @Test func aLocalSkillCannotIncludeAPartialThatOnlyAMarketplaceShips() throws {
        let fixture = try Self.makeRegistry()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let error = try #require(throws: TemplateEngineError.self) {
            try fixture.registry.call(id: Self.localSkillID)
        }

        #expect(
            error.description.contains(Self.partialName),
            "the render error must name the partial the local layers do not hold")
        #expect(
            !error.description.contains(Self.headerFromMarketplaceA),
            "a local skill must get a render error, not the text of a marketplace partial")
        #expect(!error.description.contains(Self.headerFromMarketplaceB))
    }
}
