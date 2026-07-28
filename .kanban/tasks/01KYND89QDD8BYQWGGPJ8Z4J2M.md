---
depends_on:
- 01KYNCSXAEKDVR36H387H5TYXR
- 01KYNCSDX30R4T2NRXP7XRQMM2
position_column: todo
position_ordinal: '9580'
title: 'SkillsRegistry reload: watcher wiring, atomic swap, onReload'
---
## What
The reloadable half of the registry (plan §7 "Reload & metadata injection"; decision #13) — split out of the static core per double-check.

- Extend `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`:
  - Add `watch: Bool` to the init; when true, wire `SkillWatcher` over every stack layer root → rebuild on its coalesced signal.
  - Rebuild swaps the catalog atomically (actor or lock) — readers never observe a half-built catalog.
  - `onReload` observation (AsyncStream or callback) publishing the refreshed `[SkillMetadata]` after each rebuild — the seam the search agent's `update(items:)` and preload refresh hang off (§7.1).
  - `preloadedBodies()`, `commandListing()`, `metadata()`, and `diagnostics` all reflect the post-reload catalog.
  - Watcher lifecycle owned by the registry: stopped on deinit; no callbacks after stop.

## Acceptance Criteria
- [ ] Editing a temp-layer `SKILL.md` triggers exactly one rebuild and one `onReload` publication with refreshed metadata
- [ ] Add and remove of a skill directory each propagate to `metadata()` and `commandListing()`
- [ ] A reader querying during a rebuild burst never sees a partial catalog (stress loop over concurrent reads + reloads)
- [ ] `watch: false` performs no watching (temp-dir edit changes nothing)

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillsRegistryReloadTests.swift` — temp-dir add/edit/remove with expectation waits; concurrency stress case; watch-off case
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.