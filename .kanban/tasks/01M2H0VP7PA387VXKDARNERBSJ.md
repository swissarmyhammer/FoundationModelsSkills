---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2jwqxgftnzsneg0yyccwat3
  text: |-
    Picked up the card. Research notes:

    - marketplace.md §7.1-§7.6 read. The layout is `<cache>/<cacheFolderName>/` with `repo.git/`, `refs/<ref>`, `snapshots/<sha>/`, the `current` symlink, and `lock`.
    - The environment pattern comes from `ModelResolver.hubCacheDirectory(environment:)` in FoundationModelsACPAgent: read the variable, accept it only when it is not empty, expand a leading tilde with `NSString.expandingTildeInPath`, else fall back to a path under `FileManager.default.homeDirectoryForCurrentUser`.
    - `MarketplaceIdentity.cacheFolderName(key:normalizedURL:)` already gives the folder name, so the cache takes the name and does not compute it.
    - Error style: `MarketplaceConfigError` is a struct with `CustomStringConvertible`; `MarketplaceSourceError` is an enum with `CustomStringConvertible`.
    - Test helpers: `MarketplaceTestSupport.makeTempDirectory(withFiles:)` and `writeFile(text:to:)`, over `WatcherTestSupport.makeTempDirectory()`.

    Design:
    - Take the writer lock with `flock(LOCK_EX)` on the `lock` file for the full install.
    - A reader takes `flock(LOCK_SH)` on the snapshot folder itself, so no extra file goes into the layer root.
    - The swap makes a relative symlink `current.new` -> `snapshots/<sha>`, then `rename(2)` over `current`.
    - Cleanup keeps the new sha and the sha that `current` had before the swap, and it skips a folder on which `flock(LOCK_EX | LOCK_NB)` fails. Counts only; no age and no time value.
  timestamp: 2026-09-15T16:00:02.575226+00:00
- actor: claude-code
  id: 01m2jx72m3v48mv2k9ez9smhmp
  text: |-
    Implementation landed with /tdd. The tests came first and failed with "cannot find type 'MarketplaceCache' in scope"; then the two source files made them pass.

    Notes for the next agent:

    - `MarketplaceCache` and `MarketplaceState` are `internal`, in the same way as `MarketplaceIdentity`, `MarketplaceLocation`, and `MarketplaceCatalog`. Only host-facing configuration is public in this folder.
    - The `current` swap makes a **relative** symlink `current.new -> snapshots/<sha>`, then calls `rename(2)`. `Foundation` gives `rename` through `Darwin`, so the file needs no new import.
    - A reader takes its shared lock on the **snapshot folder itself**, not on a marker file in it. A marker file would go into the layer root, and skill discovery would see it. `flock` works on a directory file descriptor on macOS, and two file descriptors of the same process do conflict, so one test can hold the shared lock and prove that cleanup keeps the folder.
    - Cleanup keeps the new sha and the sha that `current` had before the swap. It reads no age and no time value.
    - `install` is idempotent for the same sha: a destination folder that is already there keeps its place, and the staged copy goes away. A commit never changes its content, so this keeps a folder that a reader may hold open.
    - Rules that changed the first draft:
      - swiftformat `redundantMemberwiseInit` — the explicit `init(root:folderName:)` was identical to the synthesized one, so it is gone.
      - swiftlint `no_magic_numbers` — Swift Testing suites get no test carve-out (only `XCTestCase` and `QuickSpec`), so every number in the test file now has a name: `hexRadix`, `keptShaCount`, `cleanupInstallCount`.
      - swiftformat `noGuardInTests` — the fixture helper now uses `Optional.map` in place of a `guard`.

    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift, Sources/FoundationModelsSkills/Marketplace/MarketplaceState.swift, Tests/FoundationModelsSkillsTests/MarketplaceCacheTests.swift. `swift test --filter MarketplaceCacheTests` = 15 tests, 1 suite, 0 failures. `swift test` = 568 tests, 41 suites, 0 failures. `swift build --build-tests` = 0 warnings.
    - next: /review
  timestamp: 2026-09-15T16:08:19.331857+00:00
depends_on:
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: doing
position_ordinal: '80'
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

- [x] `cacheDirectory(environment:)`
- [x] Folder layout and `install` with the atomic `current` swap
- [x] Count-based cleanup that respects shared locks
- [x] `MarketplaceState` with an atomic write and read

## Acceptance Criteria
- [x] `current` always points at a complete snapshot: during and after an install, a reader never sees a missing or partial folder
- [x] After three installs, exactly two snapshots remain, and one of them is `current`
- [x] A snapshot with a shared lock survives cleanup

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceCacheTests.swift`: `cacheDirectory` with the variable set, empty, and absent; install and swap; three installs leave two snapshots; a shared-locked snapshot is kept; `state.json` round trip; a reader loop that resolves `current` during repeated installs never fails
- [x] Run `swift test --filter MarketplaceCacheTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace