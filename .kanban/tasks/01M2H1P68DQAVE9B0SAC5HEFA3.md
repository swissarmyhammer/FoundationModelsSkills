---
assignees:
- claude-code
depends_on:
- 01M2H10AWYB2KQ6P0N4B43PG6M
position_column: todo
position_ordinal: '9680'
title: 'MarketplaceStore: file:// sources (watched) and the read-only seed folder'
---
## What

marketplace.md §5.1 (local folder), §7.4, §7.5. Two sources that need no network.

- `Sources/FoundationModelsSkills/Marketplace/MarketplaceStore.swift`:
  - A `file://` source gives a layer at `<folder>/<path ?? "skills">` directly, with no copy and no cache entry. A `select` other than `.all` gives a diagnostic and is ignored.
  - When the cache has no entry for a git source and `SKILLS_MARKETPLACE_SEED` names a folder with the same layout that has one, the layer uses the seed entry. The store never updates a seed entry: `update()` for it gives a diagnostic.
- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: in `init(marketplaces:stack:policy:watch:)` with `watch: true`, the file watcher also watches every `file://` marketplace root, as it watches a local layer (§7.4). Cache-backed marketplace layers still reload only on `layerUpdates`.

- [ ] The `file://` layer and the `select` diagnostic
- [ ] The seed lookup, and no update for a seed entry
- [ ] The watcher over `file://` marketplace roots
- [ ] Tests

## Acceptance Criteria
- [ ] A `file://` source gives its skills with no network and no cache folder
- [ ] With `watch: true`, an edit to a `SKILL.md` under a `file://` marketplace gives exactly one `onReload` value
- [ ] A seed entry gives a layer when the cache is empty, and `update()` never changes it

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceLocalSourceTests.swift`: the `file://` source (layer root, no cache folder, the `select` diagnostic); the `file://` watch case (one `onReload` value after an edit); the seed case with `SKILLS_MARKETPLACE_SEED` given through the store's environment parameter; `update()` on a seed entry is a no-op with a diagnostic
- [ ] Run `swift test --filter MarketplaceLocalSourceTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace