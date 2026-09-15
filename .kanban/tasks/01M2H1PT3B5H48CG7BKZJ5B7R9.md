---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2kh94j9w5hmhsgjnrfn8yan
  text: |-
    Research before the code.

    What the code already gives:
    - `MarketplaceStore.installHead(remote:ofIndex:force:)` reads the remote head, fetches, materializes, and calls `MarketplaceCache.installUnderWriterLock(snapshotAt:sha:ref:)`, which moves the staged folder under `snapshots/<sha>` and swaps `current` in one rename.
    - `remoteHead(of:pinnedSha:)` already short-circuits on `source.sha`. `checkHead` passes that pin, thus a check of a pinned source reports the pin as `latest` today. §8.3 asks for the true head, thus the check must ask the remote.
    - `MarketplaceStateRecord` already holds `pinnedSha`, but nothing reads it back.

    Plan:
    1. A runtime pin override for each source, three states: pinned to a commit, unpinned, or no override (the `sha` field of the source then applies). `pin(_:sha:)` and `unpin(_:)` set it and write `state.json`. `unpin` must beat the `sha` field of the source, thus `state.json` needs an `unpinned` flag beside `pinnedSha`.
    2. `check()` always reads the true remote head. `installHead` targets the pin, thus a pinned source never moves to the head. A pinned source that already holds its commit makes no remote call at all.
    3. `MarketplacePolicy.applyUpdates` with `.immediately` and `.nextLaunch`. With `.nextLaunch` the sync stages the snapshot under `snapshots/<sha>`, writes a `pending` record in `state.json`, and publishes `.updateAvailable`. `start()` adopts every pending snapshot before it runs the passes, thus the swap is a state flag and no timer.
    4. New cache entry points: stage a snapshot with no swap, and adopt a snapshot that the folder already holds.
  timestamp: 2026-09-15T21:58:58.377029+00:00
- actor: claude-code
  id: 01m2kjwa70z3pwzwyakpf4fzax
  text: |-
    Work landed.

    What changed:
    - `MarketplacePinError` is new: `unknownMarketplace(id:)` and `notAGitMarketplace(id:)`. A folder on this computer has no commit, thus it cannot take a pin.
    - `MarketplaceStateRecord` holds `pinnedSha`, the new flag `unpinned`, and the new record `pending`. `MarketplacePendingSnapshot` holds the commit, the catalog version, and the display id of a snapshot that waits.
    - `MarketplaceStore` holds a pin override for each source with three states: pinned to a commit, cleared, or no override, and then the `sha` field of the source applies. The store reads the table out of `state.json` when it is made, thus a pin of an earlier run holds. `unpin` must beat the `sha` field of the source, and that is why `state.json` needs the flag beside the commit: an empty `pinnedSha` alone cannot tell "never pinned" from "unpinned".
    - `installHead` now targets the pin. A pinned marketplace that already holds its commit makes no remote call at all, thus a pinned host also works with no network. `check()` always reads the true remote head, thus §8.3 gets its "check still reports a newer SHA".
    - `MarketplaceCache` gained `stageUnderWriterLock(snapshotAt:sha:keeping:)`, which puts a snapshot under `snapshots/` and leaves `current` alone, and `adopt(snapshotSha:ref:)`, which makes `current` name a snapshot the folder already holds. Both share the new private `activate(checked:)` with the install, thus the swap has one body.
    - The install now writes `state.json` through one `updateRecord` entry point that keeps every field it does not know. The old `stateRecord` + `save` pair replaced the whole record, which would have dropped a pin at each update.

    One decision that the card did not state: a cold start does not defer. `.nextLaunch` holds back only an update of a marketplace that the store already serves. A first install has no session to keep stable, and a deferred first install would leave the registry with no layer at all until a second `start()`.

    Tests: `Tests/FoundationModelsSkillsTests/MarketplacePinTests.swift`, 15 tests. No test waits for real time; the pending snapshot is a flag on the disk.
  timestamp: 2026-09-15T22:26:55.328869+00:00
- actor: claude-code
  id: 01m2kjwgv961qmhwcgbdp5xp2b
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsSkills/Marketplace/MarketplacePinError.swift (new), MarketplaceState.swift, MarketplacePolicy.swift, MarketplaceCache.swift, MarketplaceStore.swift, Tests/FoundationModelsSkillsTests/MarketplacePinTests.swift (new). `swift build --build-tests`: no error and no warning. `swift test --filter MarketplacePinTests`: 15 tests passed. `swift test`: 673 tests in 51 suites passed.
    - next: /review
  timestamp: 2026-09-15T22:27:02.121541+00:00
- actor: claude-code
  id: 01m2kjx8a43n3jbwrvw0qfdjyc
  text: |-
    ### decision — a cold start does not defer
    The implementer asked whether `.nextLaunch` must also hold back the FIRST install of a marketplace. It must not. A cold start has no session to keep stable, and a deferred first install would leave the registry with no layer until a second `start()`. `.nextLaunch` holds back only a snapshot that replaces one the store already serves. The card is correct as built.
  timestamp: 2026-09-15T22:27:26.148894+00:00
depends_on:
- 01M2H125CCEZMT2PZAW6DRYE1R
position_column: doing
position_ordinal: '80'
title: 'MarketplaceStore: pins and .nextLaunch'
---
## What

marketplace.md §8.3 (pins) and §8.4 (`.nextLaunch`).

In `Sources/FoundationModelsSkills/Marketplace/MarketplaceStore.swift`, `MarketplacePolicy.swift`, and `MarketplaceState.swift`:
- `pin(_ id: String, sha: String) async throws` and `unpin(_ id: String) async throws` store `pinnedSha` in `state.json`. A `sha:` field on the source also pins it. A pinned source never updates automatically; `check()` still reports a newer head with `.updateAvailable`. `update(id, force: true)` on a pinned source fetches the pinned SHA only.
- `MarketplacePolicy.applyUpdates: ApplyUpdates` (`.immediately` default, `.nextLaunch`). With `.nextLaunch`, an update materializes the new snapshot, records it as pending in `state.json`, and swaps `current` only at the next `start()`.

- [x] `pin` and `unpin` with `state.json`
- [x] The `sha:` source pin, and pinned behavior in `start()` and `check()`
- [x] `.nextLaunch` with the pending snapshot
- [x] Tests

## Acceptance Criteria
- [x] A pinned source never fetches a newer head automatically, and `check()` reports the newer head
- [x] `unpin` lets the next automatic update fetch the head
- [x] With `.nextLaunch`, `current` changes only after the next `start()`, and a pending snapshot survives a store restart

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplacePinTests.swift` with `GitFixtureRepository` and a temporary cache: pin through the source and through `pin(_:sha:)`; `check()` with a pin; `unpin`; `.nextLaunch` across two store instances on one cache
- [x] Run `swift test --filter MarketplacePinTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace