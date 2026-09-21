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
- actor: claude-code
  id: 01m30cax7aa3h4z25xqx213vmt
  text: |
    ## Research: the Extras Marketplace product at `cf4be5c`

    `Package.resolved` pins `FoundationModelsExtras` at `cf4be5cba0862c0326183196db80754116cf753c` on `main`. Step 1 of this card is satisfied.

    ### The public read API that unblocks the CLI

    - `MarketplaceListing` is public. Fields: `id`, `key: String?`, `url: String?`, `currentSha`, `catalogVersion`, `lastChecked`, `isLocalFolder`, `holdsOneCommit`, `lastError`.
    - `MarketplaceStore.listings(of:cacheDirectory:)` is public, `static`, and reads the state file only.
    - `MarketplaceStore.cacheDirectory(environment:)`, `MarketplaceStore.cacheDirectoryVariable` and `MarketplaceStore.seedDirectoryVariable` are public.
    - `MarketplaceStore.init` now takes `layout: MarketplaceLayout`. `MarketplaceLayout(documentName:excludedDirectoryNames:partialsDirectoryName:)` is public, and the last two have defaults that are equal to the values of this package (`[".git", "node_modules"]` and `"_partials"`).
    - `MarketplaceLayerProviding.swift` of Extras and of this package are the same text, except for the `MarketplaceProvenanceIndex` at the end. Thus the index moves to `Registry/`, and the rest goes.
    - `MarketplaceFixtures` gives `MarketplaceStoreFixture` with `static let skillsLayout = MarketplaceLayout(documentName: "SKILL.md")`, plus `GitFixtureRepository`, `RecordingGitTransport`, `GatedGitTransport`, `ManualClock`, `MarketplaceEventLog` and `TestSignal`.

    ### What each CLI file becomes

    - `MarketplaceRow` keeps its column headings, its status words and `names(_:)`, and it reads each field from one `MarketplaceListing`. `MarketplaceCache`, `MarketplaceState`, `MarketplaceStateRecord`, `MarketplaceIdentity` and `MarketplaceLocation` leave this package.
    - `MarketplaceCLIContext.cacheDirectory` calls `MarketplaceStore.cacheDirectory(environment:)`.
    - `MarketplaceCLI.Add` takes the pre-fetch key from `MarketplaceListing.key`.
    - `MarketplaceCLISession.makeStore` passes the layout.

    ### The layout value

    One `SkillMarketplaceLayout` enum holds `MarketplaceLayout(documentName: SkillDiscovery.skillFileName, ...)`. It is public, because `docs/marketplaces.md` shows a host that builds a store, and the store now needs a layout.
  timestamp: 2026-09-20T21:42:41.130142+00:00
- actor: claude-code
  id: 01m31z5qaw8yq81f45jpff4rcw
  text: |
    ## Continued the work of the stopped run, and made the build and the tests green

    The working tree already held most of this card: the folder `Sources/FoundationModelsSkills/Marketplace/` is gone (42 files), `Package.swift`, `SeamReexports.swift`, the five `CLI/Marketplace*` files, `DependencyGraphTests` and the kept test suites are on the Extras API. The last run stopped at "restore the smoke test and build the tests". I did not start again, and I reverted nothing.

    ### What was still broken, and what I did

    - `MarketplaceLocalSourceTests`, `MarketplaceEndToEndTests` and `MarketplaceCLITests` used `GitFixtureRepository` and `MarketplaceStoreFixture` with no import. Each file now writes `import MarketplaceFixtures`.
    - `MarketplaceCLITests.cacheHoldsASnapshot` read `MarketplaceState.load(from: MarketplaceCache.stateFile(...))`. Both types are internal in Extras. It reads `MarketplaceStore.listings(of:cacheDirectory:)` now and asks whether a marketplace carries a commit.
    - `MarketplaceDocsTests.urlFormAdvice` named `MarketplaceSourceError.unsupportedForm.description`. `MarketplaceSourceError` is internal in Extras too. The suite now takes the same sentence through the public path that `marketplace add` uses: the `lastError` of the listing of a source whose URL the reader refuses, wrapped in `MarketplaceCLIError.unusableSource(reason:)`. Thus the test still reads the text that a user sees, and holds no copy of it.
    - The smoke test of `PackageSmokeTests` asserted `store.marketplaceLayers().isEmpty`. That is false: Extras serves one layer for each git source from construction, and the layer carries no commit before the first fetch. The test now asserts one layer with no commit.
    - `docs/marketplaces.md`: the host example built a store with `MarketplaceStore(sources:)`. The Extras initializer needs `layout:`, thus the example would not compile. It passes `SkillMarketplaceLayout.skills` now, which is the acceptance criterion of the one import.
    - `NoGitProcessTests`: the doc says now that `GitTransport` lives in the `Marketplace` module of Extras, and that the tests of that module hold a guard of the same shape. The scope stays `Sources/`.
    - `SkillDiscovery`: two doc comments named `CatalogResolver`, which left this package. They name ``SkillMarketplaceLayout/skills`` now.
    - `CLI/MarketplaceCLI.swift`: the `pin` doc named `MarketplaceCacheError`, which is internal in Extras and which no reader of this package can resolve. It says "the error of the cache" now.

    ### Evidence

    - `swift build --build-tests`: complete, 0 warnings.
    - `swift test`: 584 tests in 54 suites, 0 failures.
    - `.build/debug/skills-demo --marketplace list` gives the six columns, `demo-skills … not installed`.
  timestamp: 2026-09-21T12:31:08.636522+00:00
- actor: claude-code
  id: 01m31zmcmqx4k74zheq27yy03r
  text: |-
    ## The rule check of the changed files

    I gave the changed files to the validator rules before I reported. Three points came back, and I did each one:

    1. `no-test-cheating`, "Over-mocking": the smoke test asserted `source.url == "github:acme/team-skills"` against the literal that the line above gave the initializer. That expectation cannot fail, thus it proves nothing. It is gone. The two expectations that stay are real: the store serves one layer, and that layer holds no commit before a fetch.
    2. `Registry/MarketplaceProvenanceIndex.swift` wrote `import Foundation` and used no Foundation name. The old home of the type needed `URL`; this one does not. The import is gone.
    3. `DependencyGraphTests` said three times that "the library of this package links no git library at all". That is not true: the `Marketplace` product links libgit2, thus the library reaches libgit2 through that product. What is true is that no entry of this manifest names a git package. The three sentences, and the same claim in `Package.swift` ("no libgit2 of its own"), say that now. The assertions themselves were right and did not change.

    `swift build --build-tests` is complete with 0 warnings after the three corrections, and `swift test` gives 584 tests in 54 suites with 0 failures.

    The `marketplace.md` §6.2 sketch still builds a store with no layout. That belongs to the card `^eb2vsqg`, which owns the documents; I recorded it there.
  timestamp: 2026-09-21T12:39:09.207585+00:00
- actor: claude-code
  id: 01m31zmjh6ty2ezqppxqk05m6g
  text: |-
    ### implement — changed
    - evidence: 66 files changed (42 marketplace sources deleted, 15 test files deleted, 2 new files, the rest adapted). `swift build --build-tests`: complete, 0 warnings. `swift test`: 584 tests in 54 suites, 0 failures. `.build/debug/skills-demo --marketplace list`: the six columns, one row. Files of this pass: Tests/FoundationModelsSkillsTests/MarketplaceLocalSourceTests.swift, MarketplaceEndToEndTests.swift, MarketplaceCLITests.swift, MarketplaceDocsTests.swift, PackageSmokeTests.swift, DependencyGraphTests.swift, NoGitProcessTests.swift, Sources/FoundationModelsSkills/Registry/MarketplaceProvenanceIndex.swift, Sources/FoundationModelsSkills/Discovery/SkillDiscovery.swift, Sources/FoundationModelsSkills/CLI/MarketplaceCLI.swift, Package.swift, docs/marketplaces.md.
    - next: `/review`. The card stays in `doing`, and nothing is committed.
  timestamp: 2026-09-21T12:39:15.238668+00:00
- actor: claude-code
  id: 01m31zt8rx7tg3xcsgmhxdrw5n
  text: |-
    ### test — green
    - evidence: `swift package clean && swift build --build-tests` — build complete, 0 warnings, 0 errors. `swift test` — 584 tests in 54 suites, all pass, 0 fail, 0 skip.
    - note: the test count fall from 812 to 584 is only from the 15 deleted marketplace test files (the code they test moved to the Extras `Marketplace` product): CredentialGateTests.swift, GitFixtureRepository.swift, GitTransportTests.swift, GitTreeFileSourceTests.swift, MarketplaceCacheTests.swift, MarketplaceCatalogTests.swift, MarketplaceConfigTests.swift, MarketplacePinTests.swift, MarketplacePolicyTests.swift, MarketplaceSourceTests.swift, MarketplaceStoreTests.swift, MarketplaceUpdateTestSupport.swift, MarketplaceUpdateTests.swift, SnapshotWriterTests.swift, SourcePatternTests.swift.
    - check: no test in the suite has a skip mark or a disable mark. No test was removed to hide a failure.
    - next: send to review.
  timestamp: 2026-09-21T12:42:21.853239+00:00
- actor: claude-code
  id: 01m320489ezkasawyvmz5rrabn
  text: |
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 07a77c8) — findings 0, confirmed 0, refuted 0; 14 validators attempted, 0 failed. 61 files reviewed; 6 `.kanban/` files excluded by `.reviewignore`; `docs/marketplaces.md` matched no validator. The `code-hygiene` rules declined the deleted `Sources/FoundationModelsSkills/Marketplace/` and `Tests/` files, because those files are gone after the delete; no finding came from them.
    - next: none. The card moves to `done`.
  timestamp: 2026-09-21T12:47:49.038662+00:00
- actor: wballard
  id: 01m3204rb56bay9d8s13rptt6m
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 66 files (42 marketplace sources and 15 test files deleted)
    - test: green — swift test, 584 passed, 0 warnings
    - commit: 07a77c8
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-21T12:48:05.477510+00:00
depends_on:
- 01M2XCY70WHM6NWN6XR8MXHN6A
position_column: done
position_ordinal: ff8780
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

Work in this package. This card starts only after `main` of `../FoundationModelsExtras` holds the `Marketplace` and `MarketplaceFixtures` products. Those come from five cards on the `FoundationModelsExtras` board: the target and transport card (`^jhj8kd2`), the source model card (`^vms0qv0`), the catalog card (`^7z1w5f8`), the cache card (`^nqdcd57`) and the store card (`^qtwjzx9`). This board cannot depend on a card of another board, thus check that board before you pick this card up.

This package stops holding a copy of the marketplace implementation. It keeps only what is skill knowledge: the registry hookup, the provenance in the skill diagnostics, the provenance index by discovery layer, and the `skills marketplace` CLI command group.

**Sizing note.** This card is far over the normal size: it deletes 27 source files and about 15 test suites, and it adapts about 12 files. It cannot be split, because the package does not compile between the delete and the adaptation. Plan it as one long card.

**The shim.** The build of this package is green with the shim in place and the public `DotfolderStack.init(layers:)` of Extras resolved at the same time: the compiler prefers the initializer of this module, and reports no ambiguity. Thus the shim card is a plain cleanup, and this card does not touch the shim.

1. Run `swift package update FoundationModelsExtras` first. The resolved pin must name a commit of `main` that holds the `Marketplace` product. If it does not, stop: the Extras cards are not pushed yet.
2. `Package.swift`: remove the `swift-libgit2` package dependency and the `libgit2` product from `commonDependencies`. Add `.product(name: "Marketplace", package: "FoundationModelsExtras")` to `commonDependencies`, and `.product(name: "MarketplaceFixtures", package: "FoundationModelsExtras")` to the test target only. The test bundle links libgit2 through that product; the library does not. Update the comment block. The sibling stays a remote `main` dependency.
3. `Sources/FoundationModelsSkills/SeamReexports.swift`: add `@_exported import Marketplace`, thus a host that writes `import FoundationModelsSkills` still sees `MarketplaceStore`, `MarketplaceSource`, `MarketplacePolicy` and `MarketplaceConfig`, as `docs/marketplaces.md` shows.
4. Delete `Sources/FoundationModelsSkills/Marketplace/` completely, except `MarketplaceProvenanceIndex`: move that type into `Sources/FoundationModelsSkills/Registry/MarketplaceProvenanceIndex.swift`. It holds the provenance by discovery layer index; it has no grants.
5. Adapt the consumers to the Extras API: `Registry/SkillsRegistry.swift` (`init(marketplaces:stack:policy:watch:)`, the `LayerPlan`, `CatalogEntry.marketplace`, the `layerUpdates` rebuild task), `Validation/SkillValidator.swift` and `Validation/SkillDiagnostic.swift` (`MarketplaceProvenance`), `CLI/MarketplaceCLI.swift`, `CLI/MarketplaceCLISession.swift` (`makeStore` passes `MarketplaceLayout(documentName: SkillDiscovery.skillFileName, excludedDirectoryNames: SkillDiscovery.excludedDirectoryNames, partialsDirectoryName: "_partials")`), `CLI/MarketplaceCLIContext.swift`, `CLI/MarketplaceRow.swift`, `CLI/SkillsCLI.swift`, and `Examples/skills-demo/SkillsDemoMain.swift`. Define the layout value one time, as a static on `SkillsRegistry` or a small `SkillMarketplaceLayout` enum, and use it in the registry and the CLI.
6. Tests: delete the suites that moved to Extras: `CredentialGateTests`, `GitTransportTests`, `GitTreeFileSourceTests`, `MarketplaceCacheTests`, `MarketplaceCatalogTests`, `MarketplaceConfigTests`, `MarketplacePinTests`, `MarketplacePolicyTests`, `MarketplaceSourceTests`, `MarketplaceStoreTests`, `MarketplaceUpdateTests`, `MarketplaceUpdateTestSupport`, `SnapshotWriterTests`, `SourcePatternTests`, and `GitFixtureRepository.swift`. Keep and adapt the suites that assert through `SkillsRegistry`, the CLI or the demo: `MarketplaceRegistryTests`, `MarketplaceProvenanceDisplayTests`, `MarketplacePartialScopeTests`, `MarketplaceLocalSourceTests` (the registry half), `MarketplaceEndToEndTests`, `MarketplaceCLITests`, `MarketplaceDocsTests`, `SkillsDemoTests`. `MarketplaceTestSupport.swift` keeps `FakeMarketplaceProvider` and `makeMarketplaceLayer`, and gets a small wrapper that takes the `MarketplaceStoreFixture` of `MarketplaceFixtures` and adds `makeRegistry(watch:)`. It imports `GitFixtureRepository`, `RecordingGitTransport`, `MarketplaceStoreFixture`, `ManualClock`, `MarketplaceEventLog` and `TestSignal` from `MarketplaceFixtures`; it defines none of them. The fixture folder `Examples/marketplace-fixtures/` and the `FixtureLibrary.marketplaceCatalog` helper are removed by the next card, not by this one.
7. `NoGitProcessTests` keeps its scope `Sources/`; note in its doc that the transport now lives in Extras and has its own guard there.
8. `DependencyGraphTests`: add a test that `Package.swift` does not name `swift-libgit2` and does name the `Marketplace` product.

## Acceptance Criteria

- [x] `Package.resolved` pins `FoundationModelsExtras` to a commit of `main` that holds `Sources/Marketplace`.
- [x] `Sources/FoundationModelsSkills/` has no `Marketplace/` folder, no `import libgit2`, and no type named `GitTransport`, `MarketplaceStore`, `MarketplaceCache`, `SnapshotWriter`, `CatalogResolver` or `MarketplaceConfig`.
- [x] `Package.swift` has no `swift-libgit2` dependency, and the `Marketplace` product resolves from `FoundationModelsExtras` `main`.
- [x] A host that writes `import FoundationModelsSkills` compiles the example of `docs/marketplaces.md` with no other import.
- [x] `SkillsRegistry(marketplaces:stack:watch:)`, the provenance in `SkillDiagnostic`, the shadow advisory, and every `skills marketplace` command behave as before: the kept test suites pass with the calls changed only.
- [x] `skills-demo --marketplace list` gives the same output as before.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift`: the manifest names the `Marketplace` product and not `swift-libgit2`; no file under `Sources/` names a type of the deleted list.
- [x] `Tests/FoundationModelsSkillsTests/PackageSmokeTests.swift`: `import FoundationModelsSkills` alone gives `MarketplaceStore` and `MarketplaceSource`.
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceEndToEndTests.swift`: the full cycle over two `file://` marketplaces from `MarketplaceFixtures` still passes.
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceCLITests.swift`: all seven commands pass over the Extras store.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#marketplace #skills #loading-boundary