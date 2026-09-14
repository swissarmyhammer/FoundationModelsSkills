---
assignees:
- claude-code
depends_on:
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: todo
position_ordinal: '8780'
title: 'Add MarketplaceCache: ~/.cache location, snapshots layout, atomic current swap, count cleanup, lock, state.json'
---
## What

marketplace.md §7.1, §7.2, §7.3 steps 5–7, §7.6. The on-disk cache for all marketplaces. It holds no network code.

Create `Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift`:
- `static func cacheDirectory(environment: [String: String]) -> URL`: `SKILLS_MARKETPLACE_CACHE` when it is set and not empty, else `~/.cache/skills/marketplaces`. This is the same pattern as `FoundationModelsACPAgent`'s `ModelResolver.hubCacheDirectory(environment:)`.
- For one marketplace, the folder `<cache>/<cacheFolderName>/` holds `repo.git/`, `refs/<ref>`, `snapshots/<sha>/`, the `current` symlink, and `lock`.
- `install(snapshotAt temporary: URL, sha: String, ref: String?) throws`: rename `temporary` to `snapshots/<sha>/`, write `refs/<ref>`, make `current.new` → `snapshots/<sha>`, then `rename(2)` it over `current`.
- Cleanup by count only (no age): after each install, keep `current` and one previous snapshot, and delete the others.
- Locks: `flock` on `lock`, exclusive for a writer. A reader can take a shared lock on the snapshot it uses. Cleanup does not delete a snapshot that has a shared lock.
- `MarketplaceState` (Codable, `version: 1`, one record for each marketplace: url, ref, pinnedSha, currentSha, catalogVersion, lastChecked, lastUpdated, lastError), written atomically to `<cache>/state.json`.

Create `Sources/FoundationModelsSkills/Marketplace/MarketplaceState.swift` for the Codable types.

- [ ] `cacheDirectory(environment:)`
- [ ] Folder layout and `install` with the atomic `current` swap
- [ ] Count-based cleanup that respects shared locks
- [ ] `MarketplaceState` with an atomic write and read

## Acceptance Criteria
- [ ] `current` always points at a complete snapshot: during and after an install, a reader never sees a missing or partial folder
- [ ] After three installs, exactly two snapshots remain, and one of them is `current`
- [ ] A snapshot with a shared lock survives cleanup

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceCacheTests.swift`: `cacheDirectory` with the variable set, empty, and absent; install and swap; three installs leave two snapshots; a shared-locked snapshot is kept; `state.json` round trip; a reader loop that resolves `current` during repeated installs never fails
- [ ] Run `swift test --filter MarketplaceCacheTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace