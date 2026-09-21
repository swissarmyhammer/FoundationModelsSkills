import Foundation
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Operations
import Testing
import Yams

/// Placeholder scaffold test proving the library target and all four
/// dependencies build, link, and are importable from the test target.
///
/// Proves `FoundationModelsSkills` and its four dependencies --
/// `FoundationModelsExtras`, `Operations` (package `FoundationModelsOperations`),
/// `FoundationModelsMetadataRegistry`, and `Yams` -- all resolve, build, and
/// link from a Swift Testing test target (plan.md §3/§17). The imports above
/// are the real assertion, exactly like the sibling packages' own scaffold
/// smoke tests: this only compiles if every dependency is wired correctly in
/// `Package.swift`. Replaced by real tests as each layer lands in subsequent
/// tasks.
@Test func moduleAndDependenciesImportCleanly() {
    #expect(Bool(true))
}

/// Proves that one `import FoundationModelsSkills` gives a host the
/// marketplace types.
///
/// The marketplace lives in the `Marketplace` module of
/// `FoundationModelsExtras` now. This file imports that module nowhere, thus
/// the names below resolve only through the re-export in
/// `Sources/FoundationModelsSkills/SeamReexports.swift`. A change that drops
/// the re-export stops this file from compiling, and a host that follows
/// `docs/marketplaces.md` would then need a second import.
@Test func oneImportGivesTheMarketplaceTypes() throws {
    let cacheDirectory = try WatcherTestSupport.makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: cacheDirectory) }
    let source = MarketplaceSource("github:acme/team-skills")

    let store = MarketplaceStore(
        sources: [source], layout: SkillMarketplaceLayout.skills,
        cacheDirectory: cacheDirectory)

    let layer = try #require(store.marketplaceLayers().first)
    #expect(store.marketplaceLayers().count == 1, "the store serves one layer for the one source")
    #expect(layer.provenance.sha == nil, "no fetch ran, thus the layer serves no commit yet")
}

