---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2zgp2045qj7njmsc9m584f1
  text: |-
    ## Research: the Extras Marketplace product at 1c150fb

    I ran `swift package update FoundationModelsExtras`. The pin stays at `1c150fb67b8cbc254a90fe133804797f84fa6894` on `main`. Step 1 of this card is satisfied. Extras gives the products `Marketplace` and `MarketplaceFixtures`, as the card states.

    ### What maps cleanly

    These types are `public` in the Extras `Marketplace` target. The registry side, the validation side and the demo side map onto them with no gap:

    - `MarketplaceLayerProviding`, `MarketplaceLayer`, `MarketplaceProvenance` — same shape as the local copies.
    - `MarketplaceStore` — `init(sources:layout:cacheDirectory:policy:)`, `init(sources:layout:cacheDirectory:policy:transport:clock:environment:)`, `static cacheDirectory(environment:)`, `marketplaceLayers()`, `layerUpdates`, `events`, `diagnostics`, `pin(_:sha:)`, `unpin(_:)`, `start()`, `stop()`, `check()`, `update(_:force:)`.
    - `MarketplaceLayout` — `init(documentName:excludedDirectoryNames:partialsDirectoryName:)`.
    - `MarketplaceSource`, `SkillSelection`, `SourcePattern`, `MarketplacePolicy`, `SnapshotLimits`, `MarketplaceConfig`, `MarketplaceConfigError`, `MarketplaceCredential`, `MarketplaceDiagnostic`, `MarketplaceEvent`, `MarketplaceStatus`, `MarketplacePinError`, `GitTransport`, `GitTransportError`, `LibGit2Transport`.
    - `MarketplaceFixtures` gives `GitFixtureRepository`, `RecordingGitTransport`, `GatedGitTransport`, `ManualClock`, `MarketplaceEventLog`, `TestSignal` and `MarketplaceStoreFixture`. `MarketplaceStoreFixture` carries `static let skillsLayout = MarketplaceLayout(documentName: "SKILL.md")` and a `layout:` parameter. It does not carry `makeRegistry(watch:)`, thus the wrapper of step 6 is necessary.

    ### What does not map: the CLI command group

    `Sources/FoundationModelsSkills/CLI/` cannot move onto the Extras API. Every type that `MarketplaceRow` and `MarketplaceCLIContext` use to read the cache is `internal` in the Extras `Marketplace` target:

    - `MarketplaceCache` — `cacheVariable`, `seedVariable`, `stateFile(inCacheDirectory:)`, `cacheDirectory(environment:)`
    - `MarketplaceState`, `MarketplaceStateRecord` — `displayID`, `currentSha`, `catalogVersion`, `lastChecked`, `lastError`, `pinnedSha`, `unpinned`
    - `MarketplaceIdentity` — `preFetchKey(for:)`, `cacheFolderName(key:normalizedURL:)`
    - `MarketplaceLocation` — `normalizedURL`, and the test that tells a git remote from a folder on this computer

    A consumer of the product cannot reach one of them. Thus:

    - `marketplace list` cannot make its six columns: ID, URL, CURRENT, CATALOG, CHECKED, STATUS.
    - `check`, `update`, `pin`, `unpin` and `remove` cannot find the marketplace that an id names, because `MarketplaceRow.names(_:)` matches the display id **or** the pre-fetch key.
    - `add` cannot make the pre-fetch key of a new source, thus it cannot refuse a duplicate.
    - The kept test `MarketplaceCLITests.pinHoldsTheCommitAndListSaysSo` asserts that `list` shows `pinned` after `store.pin(...)`. The pin lives in `state.json` only, thus no public call answers it.
    - `MarketplaceDocsTests` and `SkillsDemoTests` name `MarketplaceCache.cacheVariable` and `MarketplaceCache.seedVariable`. Those two constants are internal too.

    ### Why no part of the card fits alone

    The delete and the adaptation are one step, as the card states. `SeamReexports.swift` must add `@_exported import Marketplace`. That import makes `MarketplaceProvenance`, `MarketplaceLayer`, `MarketplaceSource`, `MarketplaceStore` and the rest visible with the same names as the local copies. Two types of one name in one file is an ambiguity error. Thus the local `Marketplace/` folder must go whole, or it must stay whole. A slice that deletes only some files does not build.

    ### Dead ends that I did not take

    - Make the row from `store.marketplaceLayers()` alone. The provenance carries the id, the URL, the commit and the catalog version, but it carries no last-check time, no pin and no error message. The output of `marketplace list` would change, and one kept test would fail.
    - Write the pin into the user `marketplaces.yaml` instead of the cache. That changes what `marketplace pin` does, and the card says the CLI must behave as before.
    - Keep a local copy of `MarketplaceIdentity` and `MarketplaceLocation`. That keeps about 500 lines of the code that this card deletes, and it duplicates the URL rules that Extras owns now.

    ### The way out

    `^z8qke1j` records the public read API that Extras must add: one `MarketplaceListing` value, one `listings(of:cacheDirectory:)` call that reads only the disk, and public names for the two environment variables. That work is in `../FoundationModelsExtras`. This card now depends on it.
  timestamp: 2026-09-20T13:39:26.340185+00:00
- actor: claude-code
  id: 01m2zgparjr030nc7v0v3dk64y
  text: |-
    ### implement — stuck
    - evidence: `swift package update FoundationModelsExtras` keeps the pin at `1c150fb` on `main`. No source file changed. The blocker is the Extras API: `MarketplaceCache`, `MarketplaceState`, `MarketplaceStateRecord`, `MarketplaceIdentity` and `MarketplaceLocation` are `internal` in the `Marketplace` target, thus `CLI/MarketplaceRow.swift`, `CLI/MarketplaceCLIContext.swift` and `CLI/MarketplaceCLI.swift` have no public call to move onto. The card cannot be cut smaller, because `@_exported import Marketplace` makes every local duplicate ambiguous at the same time.
    - next: do `^z8qke1j` in `../FoundationModelsExtras`, push it to `main`, then start this card again from step 1.
  timestamp: 2026-09-20T13:39:35.314214+00:00
- actor: wballard
  id: 01m2zgr28bmy9315zzhb54a9p6
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — five types of the Extras Marketplace product are internal, thus the CLI of this package has no public call
    - test: not run
    - commit: none
    - review: not run
    - next: the Extras card ^rx3ke7b on the FoundationModelsExtras board gives the public read API. After it lands and is pushed, bump the dependency and do this card.
  timestamp: 2026-09-20T13:40:32.139819+00:00
depends_on:
- 01M2XCY70WHM6NWN6XR8MXHN6A
position_column: todo
position_ordinal: 9a80
title: Consume the Extras Marketplace product and delete the marketplace code from this package
---
## What

**Status on 2026-09-20, second check: not blocked.** The first try of this card stopped, because `MarketplaceCache`, `MarketplaceState`, `MarketplaceStateRecord`, `MarketplaceIdentity` and `MarketplaceLocation` are internal in the Extras `Marketplace` target, and the CLI of this package used them. The Extras card `^rx3ke7b` is done and pushed (commit `37e6116`). It did not make the cache types public. It gave one public read API, and the CLI moves onto it:
- `CLI/MarketplaceRow.swift`: take each row from `MarketplaceStore.listings(of:cacheDirectory:)`, which gives `[MarketplaceListing]` (`id`, `key`, `url`, `currentSha`, `catalogVersion`, `lastChecked`, `isLocalFolder`, `holdsOneCommit`, `lastError`). It reads the state file and opens no connection. Delete the code that read `MarketplaceCache.stateFile`, `MarketplaceState.load`, `MarketplaceLocation` and `MarketplaceIdentity` itself.
- `CLI/MarketplaceCLI.swift` (`add`, `remove`, `pin`, `unpin`): the pre-fetch key of a source is `MarketplaceListing.key`; do not call `MarketplaceIdentity.preFetchKey(for:)`.
- `CLI/MarketplaceCLIContext.swift`: the cache directory is `MarketplaceStore.cacheDirectory(environment:)`.
- `Tests/FoundationModelsSkillsTests/SkillsDemoTests.swift` and the CLI tests: the environment variable names are `MarketplaceStore.cacheDirectoryVariable` and `MarketplaceStore.seedDirectoryVariable`.
If one more internal Extras type is still necessary, make one card on the Extras board for a public read call, as `^rx3ke7b` did. Do not ask Extras to make a cache type public. `Package.resolved` of this package pins the Extras revision `cf4be5c`, which is `origin/main` of `FoundationModelsExtras` (checked on 2026-09-20; `swift build` of this package is green against it).

**Status on 2026-09-20: not blocked.** The five Extras cards are done and pushed, and `Package.resolved` of this package pins `1c150fb`, which holds `Sources/Marketplace` and `Tests/MarketplaceFixtures`. Step 1 below is satisfied now; run it again only to confirm the pin. Checked facts of that revision: the products `Marketplace` and `MarketplaceFixtures` exist; `MarketplaceStore.init(sources:layout:cacheDirectory:policy:transport:clock:environment:)` is public; `GitTransport` and `GitTransportError` are public; `MarketplaceFixtures` holds `GitFixtureRepository`, `RecordingGitTransport`, `GatedGitTransport`, `ManualClock`, `MarketplaceEventLog`, `MarketplaceStoreFixture` and `TestSignal`; `EventBroadcaster` of that target is internal, thus `Registry/EventBroadcaster.swift` of this package stays.

Work in this package. This card starts only after `main` of `../FoundationModelsExtras` holds the `Marketplace` and `MarketplaceFixtures` products. Those come from five cards on the `FoundationModelsExtras` board: the target and transport card (`^jhj8kd2`), the source model card (`^vms0qv0`), the catalog card (`^7z1w5f8`), the cache card (`^nqdcd57`) and the store card (`^qtwjzx9`). This board cannot depend on a card of another board, so check that board before you pick this card up.

This package stops holding a copy of the marketplace implementation. It keeps only what is skill knowledge: the registry hookup, the provenance in the skill diagnostics, the provenance index by discovery layer, and the `skills marketplace` CLI command group.

**Sizing note.** This card is far over the normal size: it deletes 27 source files and about 15 test suites, and it adapts about 12 files. It cannot be split, because the package does not compile between the delete and the adaptation. Plan it as one long card.

**The shim.** The build of this package is green with the shim in place and the public `DotfolderStack.init(layers:)` of Extras resolved at the same time: the compiler prefers the initializer of this module, and reports no ambiguity. Thus the shim card is a plain cleanup, and this card does not touch the shim.

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

#marketplace #skills #loading-boundary