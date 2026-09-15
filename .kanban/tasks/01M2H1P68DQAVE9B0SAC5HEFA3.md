---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2kdy6ejw9vqgkw8ymprdq49
  text: |-
    Research before the code (implement step).

    What the code already gives:
    - `MarketplaceLocation` gives `.local(URL)` for a `file://` URL that does not end in `.git`. The parser refuses a ref on a local folder.
    - `Preparation.add(source:)` in `MarketplaceStore.swift` runs the URL parse, then `MarketplacePolicy.refusal(forNormalizedURL:)`, and only then the `guard case .git`. Thus a `file://` source already passes the allow-list and block-list gate. The new local branch goes after that gate, so the gate keeps its place.
    - `SkillsRegistry` private `init(source:policy:watch:)` sets `roots = plan.layers.map(\.root)` and gives `watchedRoots: watch ? roots : nil` to the `ReloadCoordinator`. `plan.layers` is the marketplace layers plus the local layers. So a `file://` marketplace root is watched as soon as the store serves a layer for it; no second watcher is necessary, and no registry change is necessary.
    - `MarketplaceCache.cacheDirectory(environment:)` is the pattern for the seed folder variable.

    Plan of the change in `MarketplaceStore.swift`:
    - `PreparedSource` gets a kind: `.git(remote)`, `.local(root)`, or `.seed(remote, seedCache)`. The list order stays the list order, because layer precedence follows it.
    - A `file://` source gives a layer at `<folder>/<path ?? "skills">` with no cache folder. A `select` other than `.all` gives one warning and is ignored.
    - The store takes an `environment` parameter. `SKILLS_MARKETPLACE_SEED` names a folder with the cache layout. A git source whose cache has no `current`, and whose seed folder has one, is served from the seed.
    - An update pass over a seed entry writes nothing and gives one diagnostic. Thus the seed folder is never written.
  timestamp: 2026-09-15T21:00:34.130925+00:00
- actor: claude-code
  id: 01m2kg485bh15zd12tc07pkxm3
  text: |-
    ### implement — changed
    - evidence: 5 files. `Sources/FoundationModelsSkills/Marketplace/MarketplaceStore.swift`, `Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift`, `Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift`, `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`, `Tests/FoundationModelsSkillsTests/MarketplaceLocalSourceTests.swift` (new), `Tests/FoundationModelsSkillsTests/MarketplaceTestSupport.swift`. `swift test --filter MarketplaceLocalSourceTests`: 8 tests, 0 failures. `swift test`: 658 tests, 2 failures, both of them in `RunScriptTests` and both of them older than this work.
    - next: /review

    What the code does now:
    - `MarketplaceStore.PreparedSource` holds a kind: `.git(GitRemote)`, `.local(root:)`, or `.seed(GitRemote, seed:)`. The list order of the sources stays the list order of the layers, because layer precedence follows it.
    - A `file://` folder source gives a layer at `<folder>/<path ?? "skills">`. The store makes no cache folder, opens no connection, and writes nothing. `CatalogPath.normalized(path:)` checks the `path` field, thus a path with `..` gets an error finding and no layer. A `select` other than `.all` gives one warning and the store reads the whole folder.
    - The store takes an `environment` parameter. `MarketplaceCache.seedDirectory(environment:)` reads `SKILLS_MARKETPLACE_SEED`. A git source whose cache holds no `current`, and whose folder in the seed holds one, is served from the seed: the layer root, the sha, the display id, and the catalog version all come from the seed folder and its `state.json`. The store takes no lease on a seed snapshot, because it never cleans the seed folder up.
    - An update pass over a seed entry writes nothing, publishes nothing, and records one advisory. A check pass over a seed entry still reads the remote head, because a check writes nothing.

    Watching (§7.4):
    - `MarketplaceLayer` gains `isWatchable`. It is `true` for a folder on this computer, and `false` for a cache-backed root.
    - `SkillsRegistry.LayerPlan` now gives `watchedRoots`: every local root, plus the root of each watchable marketplace layer. The registry watched **every** layer root before, the cache roots included. That was wrong for two reasons: a snapshot swap sends no reliable event, and the cleanup of an old snapshot sends a delete event that names no real change and would give a second reload after an update. A cache-backed layer now reloads on `layerUpdates` only, as the card says.

    What did not work, so that the next agent does not repeat it:
    - A full `swift test` on this computer fails in `RunScriptTests` (`result.durationMs < 2000`, lines 313 and 346). The same two tests pass with `swift test --filter RunScriptTests`, and the same failures appear with `swift test --skip MarketplaceLocalSourceTests`, thus they are not of this work. The limit of 2000 ms is a built-in time value that the load of the host breaks. New task ^g2fy0q1 records it.
    - A settle window stays in the new tests: `ReloadTestSupport.expectExactlyOneEvent` is the helper that `MarketplaceStoreTests` and `MarketplaceRegistryTests` already use for "exactly one reload". A file-system event has no other signal to follow, thus proving that no second event comes needs that window.
  timestamp: 2026-09-15T21:38:49.643697+00:00
depends_on:
- 01M2H10AWYB2KQ6P0N4B43PG6M
position_column: doing
position_ordinal: '80'
title: 'MarketplaceStore: file:// sources (watched) and the read-only seed folder'
---
## What

marketplace.md §5.1 (local folder), §7.4, §7.5. Two sources that need no network.

- `Sources/FoundationModelsSkills/Marketplace/MarketplaceStore.swift`:
  - A `file://` source gives a layer at `<folder>/<path ?? "skills">` directly, with no copy and no cache entry. A `select` other than `.all` gives a diagnostic and is ignored.
  - When the cache has no entry for a git source and `SKILLS_MARKETPLACE_SEED` names a folder with the same layout that has one, the layer uses the seed entry. The store never updates a seed entry: `update()` for it gives a diagnostic.
- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: in `init(marketplaces:stack:policy:watch:)` with `watch: true`, the file watcher also watches every `file://` marketplace root, as it watches a local layer (§7.4). Cache-backed marketplace layers still reload only on `layerUpdates`.

- [x] The `file://` layer and the `select` diagnostic
- [x] The seed lookup, and no update for a seed entry
- [x] The watcher over `file://` marketplace roots
- [x] Tests

## Acceptance Criteria
- [x] A `file://` source gives its skills with no network and no cache folder
- [x] With `watch: true`, an edit to a `SKILL.md` under a `file://` marketplace gives exactly one `onReload` value
- [x] A seed entry gives a layer when the cache is empty, and `update()` never changes it

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceLocalSourceTests.swift`: the `file://` source (layer root, no cache folder, the `select` diagnostic); the `file://` watch case (one `onReload` value after an edit); the seed case with `SKILLS_MARKETPLACE_SEED` given through the store's environment parameter; `update()` on a seed entry is a no-op with a diagnostic
- [x] Run `swift test --filter MarketplaceLocalSourceTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace