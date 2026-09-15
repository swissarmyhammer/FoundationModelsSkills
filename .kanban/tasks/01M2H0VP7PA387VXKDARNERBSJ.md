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
- actor: claude-code
  id: 01m2jxmq2c6yayk185fvdbad63
  text: |-
    ### review — findings
    - evidence: 4 findings, all confirmed. Scope `review sha HEAD~1..HEAD`. MarketplaceCache.swift:152, :196, :273, :295 — path traversal through the `sha` and `ref` values that go into the file paths.
    - next: Make `sha` and `ref` valid before you use them in a path. Correct all of the file, not only the lines in the list. The task stays in the review column.
  timestamp: 2026-09-15T16:15:46.252210+00:00
- actor: claude-code
  id: 01m2jxn3scqqrtw5y2hgyqpjss
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 3 files (Marketplace/MarketplaceCache.swift, Marketplace/MarketplaceState.swift, Tests/FoundationModelsSkillsTests/MarketplaceCacheTests.swift)
    - test: green — swift build --build-tests 0 warnings; swift test x2, 568 passed each run, 0 failed, 0 skipped
    - commit: 8f242a3 feat(marketplace): add the marketplace cache and its state
    - review: findings — 4 open, all path traversal in MarketplaceCache.swift (lines 152, 196, 273, 295): `sha` and `ref` go into a path or a symlink target with no check
  timestamp: 2026-09-15T16:15:59.276687+00:00
- actor: claude-code
  id: 01m2jy5nm9m75e6xg8s7pjvrjv
  text: |
    Pulled the card back to `doing` and worked the four path-traversal findings with /tdd.

    RED first: the new tests in `MarketplaceCacheTests.swift` failed with 40 issues, because `snapshotDirectory(forSha:)`, `sha(forRef:)`, `install`, and `withSnapshotInUse` took any value.

    GREEN: one boundary check in `MarketplaceCache`, and a typed error.

    - `MarketplacePathValue` names what a value is: `.sha` or `.ref`. The error tells it.
    - `MarketplaceCacheError.unsafePathValue(kind:value:)` and `.notACommit(value:)` are the two new cases.
    - `validated(pathValue:kind:)` refuses an empty value, a value that starts with a dot, a value that holds `..`, a value that holds `/` or `\`, and a value that holds a control character.
    - `validated(sha:)` adds the commit rule: only hex digits, and the length of a SHA-1 or a SHA-256 object name.
    - `validated(ref:)` is the path rule alone.

    The cause is gone from the whole file, not only the four lines:

    - `snapshotDirectory(forSha:)` throws now. A private `snapshotDirectory(forValidatedSha:)` builds the path, and only a checked value reaches it.
    - `install` checks `sha` and `ref` first, before `makeFolders()`. Thus a bad value writes nothing at all. A test proves that the marketplace folder does not appear.
    - `publish`, `write`, `swapCurrent`, and `removeSnapshot` take `validatedSha` or `toValidatedRef` labels, so the name of each call says that the value is checked. The symlink target holds a checked commit.
    - `sha(forRef:)` checks the ref.
    - `withSnapshotInUse(sha:)` goes through the throwing `snapshotDirectory(forSha:)`.
    - `currentSha()` checks the symlink target too, because another program can write that file. A target that is no commit gives `nil`.
    - `installedShas()` keeps only the names that are commits, so cleanup never touches a folder that is not a snapshot.

    Two notes for the next agent:

    - `write(sha:toValidatedRef:)` no longer makes the folders of the file, because a ref is one name now. A branch name with a `/` in it, such as `feature/login`, is refused. The card ordered one validator that refuses a path separator, so this is the ordered behavior; the follow-up work is task ^7ga9yde, which splits a ref on `/` and checks each part.
    - The tests expect the exact error case, not only the error type, so a weakened assertion cannot pass.
  timestamp: 2026-09-15T16:25:01.833500+00:00
- actor: claude-code
  id: 01m2jy5st3z06f0dmykfy2brc5
  text: |
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift, Tests/FoundationModelsSkillsTests/MarketplaceCacheTests.swift. `swift build --build-tests` = 0 warnings, 0 errors. `swift test --filter MarketplaceCacheTests` = 24 tests, 1 suite, 0 failures. `swift test` = 577 tests, 41 suites, 0 failures. All 4 review findings are checked.
    - next: /review
  timestamp: 2026-09-15T16:25:06.115580+00:00
- actor: claude-code
  id: 01m2jyfzcvz1t076x6hd0myr5w
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 1f44d5b). 0 findings, 0 confirmed, 1 refuted, 7 attempted. 2 files reviewed. All 4 findings of the previous pass are marked complete.
    - next: none. The task moves to done.
  timestamp: 2026-09-15T16:30:39.515456+00:00
- actor: claude-code
  id: 01m2jygafr81rt29qdep0kg50k
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 2 files; one boundary validator for the `sha` and the `ref` values, with typed errors; every path build now uses a checked value
    - test: green — swift build --build-tests 0 warnings; swift test x2, 577 passed each run, 0 failed, 0 skipped
    - commit: 1f44d5b fix(marketplace): check sha and ref values before path use
    - review: clean — 0 new findings; all 4 prior findings checked; task moved to done
    - carry-over: a ref name with a `/` (example `feature/login`) is now refused. Task ^7ga9yde holds the follow-up.
  timestamp: 2026-09-15T16:30:50.872195+00:00
depends_on:
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: done
position_ordinal: cf80
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

## Review Findings (2026-09-15 11:10)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift:152` `code-security/injection` — Path traversal in snapshotDirectory function. The `sha` parameter is passed directly to `appendingPathComponent` without validation. An attacker could provide a value like `../../../etc/passwd` to escape the snapshots directory. Validate that `sha` is a valid 40-character hexadecimal string before using it: `guard sha.count == 40 && sha.allSatisfy({ $0.isHexDigit }) else { throw MarketplaceCacheError(...) }`.
- [x] `Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift:196` `code-security/injection` — Path traversal in ref file path. The `ref` parameter is used directly with `appendingPathComponent` without validation in the `sha(forRef:)` function, allowing path traversal characters like `../` to escape the intended refs directory and read arbitrary files. Validate that `ref` does not contain path traversal sequences: `guard !ref.contains("..") && !ref.hasPrefix("/") else { throw MarketplaceCacheError(...) }`.
- [x] `Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift:273` `code-security/injection` — Path traversal in ref file path. The `ref` parameter is passed to `appendingPathComponent` without validation. An attacker could provide a value containing `../` to escape the intended refs directory and write files outside the cache. Validate that `ref` does not contain path traversal characters: `guard !ref.contains("..") && !ref.hasPrefix("/") else { throw MarketplaceCacheError(...) }`.
- [x] `Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift:295` `code-security/injection` — Path traversal in symlink target. The `sha` parameter is directly interpolated into the symlink destination path without validation. An attacker could provide a value like `../../../etc/passwd` to create a symlink pointing outside the cache directory. Validate that `sha` is a valid 40-character hexadecimal commit hash: `guard sha.count == 40 && sha.allSatisfy({ $0.isHexDigit }) else { throw MarketplaceCacheError(...) }`.
