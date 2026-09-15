---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2kp49bj4j4s24ecs3fggwq9
  text: |-
    Research of the whole file `Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift`, for the rule "every place that reads the file system to decide, then writes, must make the decision under the same lock":

    - `adopt(snapshotSha:ref:)` — the one defect. It read `fileExists` and called `makeFolders()` before `withWriterLock`.
    - `install(snapshotAt:sha:ref:)` — only value checks and `makeFolders()` are outside the lock; every file decision and write is inside `installValidated`, under the lock. Correct.
    - `installUnderWriterLock`, `stageUnderWriterLock` — the caller holds the lock over the whole call. Correct.
    - `publish(snapshotAt:validatedSha:)` — `fileExists` then move or delete, always inside the lock. Correct.
    - `activate(checked:)`, `swapCurrent`, `write(sha:toValidatedRef:)` — inside the lock. Correct.
    - `removeUnusedSnapshots` and `removeSnapshot` — inside the writer lock, and each folder also gets its own `flock`. Correct.
    - `currentSha()`, `currentSnapshot()`, `installedShas()`, `sha(forRef:)`, `leaseCurrentSnapshot()`, `withSnapshotInUse` — these read and never write, thus the rule does not apply to them.

    So `adopt` was the only place to correct.
  timestamp: 2026-09-15T23:23:42.322563+00:00
- actor: claude-code
  id: 01m2kp4xbqxwbmn0snm6ejc616
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift, Sources/FoundationModelsSkills/Marketplace/MarketplaceStore.swift, Tests/FoundationModelsSkillsTests/MarketplacePinTests.swift. `swift build --build-tests`: Build complete, zero warnings. `swift test`: 676 tests in 51 suites passed.
    - what changed: `MarketplaceCache.adopt(snapshotSha:ref:)` now tests the snapshot folder inside `withWriterLock`, in the same critical section as the swap. `makeFolders()` stays before the lock, because the lock file lives in the folder that call makes. The call no longer gives a `Bool`; it throws the new typed error `MarketplaceCacheError.snapshotMissing(sha:)` and leaves `current` where it was. `MarketplaceStore.adopt(pending:ofRemote:atIndex:)` catches that one error, clears the stale pending record, and keeps the snapshot it serves — the behaviour the `false` result gave before.
    - TDD: the first test failed to build, because `MarketplaceCacheError` had no `snapshotMissing` member. After the change every test passes.
    - new tests, all in MarketplacePinTests: `adoptRefusesAStagedSnapshotThatAnotherProcessDeleted`, `adoptKeepsTheServedSnapshotWhenTheStagedOneIsGone`, `aStartAfterAStagedSnapshotIsDeletedKeepsTheServedSnapshot`. They share the fixture `makePrunedStagedFixture()`, which stages a snapshot with `.nextLaunch` and then deletes the folder as a pruner in a second process would.
    - no time value: the fix and the tests hold no interval, no timeout, and no age.
    - note for the next agent: a test of the true interleaving (the delete lands between the test and the swap) is not deterministic without a hook in the source, because no caller can observe that another thread is waiting in `flock(2)`. The tests prove the two results that the lock gives: the typed refusal, and the served snapshot that stays.
    - next: ready for /review.
  timestamp: 2026-09-15T23:24:02.807808+00:00
position_column: doing
position_ordinal: '80'
title: MarketplaceCache.adopt checks the snapshot before it takes the writer lock
---
## What

The review of ^zj5b7r9 found this. `adopt(snapshotSha:ref:)` in `Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift` does its `FileManager.default.fileExists` check and its `makeFolders()` call BEFORE it takes the writer lock. A pruner in another process can delete the staged snapshot between the check and the swap. `current` then names a folder that is not there.

Move the existence check inside `withWriterLock`, so the check and the swap are one operation under the lock. Keep `makeFolders()` before the lock, because the lock file lives in the folder that call makes.

## Acceptance Criteria
- [x] The existence check of the staged snapshot happens under the writer lock, in the same critical section as the swap
- [x] `adopt` reports a clear error when the snapshot is gone, and it leaves `current` as it was
- [x] No hard-coded time value is part of the fix

## Tests
- [x] A test in `Tests/FoundationModelsSkillsTests/MarketplacePinTests.swift`: a second store deletes the staged snapshot, then `adopt` refuses and keeps the served snapshot
- [x] Run `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace