---
assignees:
- claude-code
depends_on:
- 01M2XCY70WHM6NWN6XR8MXHN6A
position_column: todo
position_ordinal: 8f80
title: Consume the Extras Marketplace product and delete the marketplace code from this package
---
## What

Work in this package. This card starts only after `main` of `../FoundationModelsExtras` holds the `Marketplace` and `MarketplaceFixtures` products. Those come from five cards on the `FoundationModelsExtras` board: the target and transport card (`^jhj8kd2`), the source model card (`^vms0qv0`), the catalog card (`^7z1w5f8`), the cache card (`^nqdcd57`) and the store card (`^qtwjzx9`). This board cannot depend on a card of another board, so check that board before you pick this card up.

This package stops holding a copy of the marketplace implementation. It keeps only what is skill knowledge: the registry hookup, the provenance in the skill diagnostics, the provenance index by discovery layer, and the `skills marketplace` CLI command group.

1. Run `swift package update FoundationModelsExtras` first. The resolved pin must name a commit of `main` that holds the `Marketplace` product. If it does not, stop: the Extras cards are not pushed yet.
2. `Package.swift`: remove the `swift-libgit2` package dependency and the `libgit2` product from `commonDependencies`. Add `.product(name: "Marketplace", package: "FoundationModelsExtras")` to `commonDependencies`, and `.product(name: "MarketplaceFixtures", package: "FoundationModelsExtras")` to the test target only. The test bundle links libgit2 through that product; the library does not. Update the comment block. The sibling stays a remote `main` dependency.
3. `Sources/FoundationModelsSkills/SeamReexports.swift`: add `@_exported import Marketplace`, so a host that writes `import FoundationModelsSkills` still sees `MarketplaceStore`, `MarketplaceSource`, `MarketplacePolicy` and `MarketplaceConfig`, as `docs/marketplaces.md` shows.
4. Delete `Sources/FoundationModelsSkills/Marketplace/` completely, except `MarketplaceProvenanceIndex`: move that type into `Sources/FoundationModelsSkills/Registry/MarketplaceProvenanceIndex.swift`. It holds the provenance by discovery layer index; it has no grants.
5. Adapt the consumers to the Extras API: `Registry/SkillsRegistry.swift` (`init(marketplaces:stack:policy:watch:)`, the `LayerPlan`, `CatalogEntry.marketplace`, the `layerUpdates` rebuild task), `Validation/SkillValidator.swift` and `Validation/SkillDiagnostic.swift` (`MarketplaceProvenance`), `CLI/MarketplaceCLI.swift`, `CLI/MarketplaceCLISession.swift` (`makeStore` passes `MarketplaceLayout(documentName: SkillDiscovery.skillFileName, excludedDirectoryNames: SkillDiscovery.excludedDirectoryNames, partialsDirectoryName: "_partials")`), `CLI/MarketplaceCLIContext.swift`, `CLI/MarketplaceRow.swift`, `CLI/SkillsCLI.swift`, and `Examples/skills-demo/SkillsDemoMain.swift`. Define the layout value one time, as a static on `SkillsRegistry` or a small `SkillMarketplaceLayout` enum, and use it in the registry and the CLI.
6. Tests: delete the suites that moved to Extras: `CredentialGateTests`, `GitTransportTests`, `GitTreeFileSourceTests`, `MarketplaceCacheTests`, `MarketplaceCatalogTests`, `MarketplaceConfigTests`, `MarketplacePinTests`, `MarketplacePolicyTests`, `MarketplaceSourceTests`, `MarketplaceStoreTests`, `MarketplaceUpdateTests`, `MarketplaceUpdateTestSupport`, `SnapshotWriterTests`, `SourcePatternTests`, and `GitFixtureRepository.swift`. Keep and adapt the suites that assert through `SkillsRegistry`, the CLI or the demo: `MarketplaceRegistryTests`, `MarketplaceProvenanceDisplayTests`, `MarketplacePartialScopeTests`, `MarketplaceLocalSourceTests` (the registry half), `MarketplaceEndToEndTests`, `MarketplaceCLITests`, `MarketplaceDocsTests`, `SkillsDemoTests`. `MarketplaceTestSupport.swift` keeps `FakeMarketplaceProvider` and `makeMarketplaceLayer`, and gets a small wrapper that takes the `MarketplaceStoreFixture` of `MarketplaceFixtures` and adds `makeRegistry(watch:)`. It imports `GitFixtureRepository`, `RecordingGitTransport`, `MarketplaceStoreFixture`, `ManualClock`, `MarketplaceEventLog` and `TestSignal` from `MarketplaceFixtures`; it defines none of them. The fixture folder `Examples/marketplace-fixtures/` and the `FixtureLibrary.marketplaceCatalog` helper are removed by the next card, not by this one.
7. `NoGitProcessTests` keeps its scope `Sources/`; note in its doc that the transport now lives in Extras and has its own guard there.
8. `DependencyGraphTests`: add a test that `Package.swift` does not name `swift-libgit2` and does name the `Marketplace` product.

## Acceptance Criteria

- [ ] `Package.resolved` pins `FoundationModelsExtras` to a commit of `main` that holds `Sources/Marketplace`.
- [ ] `Sources/FoundationModelsSkills/` has no `Marketplace/` folder, no `import libgit2`, and no type named `GitTransport`, `MarketplaceStore`, `MarketplaceCache`, `SnapshotWriter`, `CatalogResolver` or `MarketplaceConfig`.
- [ ] `Package.swift` has no `swift-libgit2` dependency, and the `Marketplace` product resolves from `FoundationModelsExtras` `main`.
- [ ] A host that writes `import FoundationModelsSkills` compiles the example of `docs/marketplaces.md` with no other import.
- [ ] `SkillsRegistry(marketplaces:stack:watch:)`, the provenance in `SkillDiagnostic`, the shadow advisory, and every `skills marketplace` command behave as before: the kept test suites pass with the calls changed only.
- [ ] `skills-demo --marketplace list` gives the same output as before.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift`: the manifest names the `Marketplace` product and not `swift-libgit2`; no file under `Sources/` names a type of the deleted list.
- [ ] `Tests/FoundationModelsSkillsTests/PackageSmokeTests.swift`: `import FoundationModelsSkills` alone gives `MarketplaceStore` and `MarketplaceSource`.
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceEndToEndTests.swift`: the full cycle over two `file://` marketplaces from `MarketplaceFixtures` still passes.
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceCLITests.swift`: all seven commands pass over the Extras store.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#marketplace #skills #blocked-upstream