---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2kppc4vctk03ex3kqp14e9a
  text: |-
    ### The answer from the code

    Yes. Two passes of the same store can hold and wait for the same writer lock.

    The path, step by step:

    1. `MarketplaceStore.sync(remote:atIndex:force:)` calls `makeFolders()` and then `await remote.cache.withWriterLock { try await installHead(...) }`. The asynchronous `withWriterLock` opens the lock file, takes `flock(LOCK_EX)`, and holds the open descriptor over the `await` of the remote head and of the fetch. This is on purpose (marketplace.md §7.6).
    2. An `await` gives up the actor. `MarketplaceStore` is an actor, thus no two calls run its isolated code at the same time, but the suspended pass does not hold the actor while the fetch runs. A second call can enter.
    3. `start()` runs `applyPendingSnapshots()` first, with no `await` in it. When `state.json` holds a pending record for the same marketplace, that call reaches `MarketplaceCache.adopt(snapshotSha:ref:)`, which calls the synchronous `withWriterLock` and thus `flock(descriptor, LOCK_EX)` on a second open of the same lock file.
    4. `flock(2)` belongs to the open file description, not to the thread or the process. A second open of the same file is a second description, thus the exclusive lock conflicts with the first one even inside one process. The file already says this, in the doc comment of `installUnderWriterLock(snapshotAt:sha:ref:)`: "a second lock of the same file from the same process would wait forever".
    5. That second `flock` blocks the thread that runs the actor. The first pass needs the same actor to resume after the fetch, thus it can never release the lock. This is a deadlock, not a slow wait.

    The in-flight map in `result(of:atIndex:)` does not cover this. It makes a second `update()` or `check()` join the running pass, thus those never reach a second lock. `applyPendingSnapshots()` runs before that map is consulted, so `adopt` is the one call of `start()` that meets the holder.

    Conditions: one marketplace whose `state.json` record holds a `pending` snapshot, and a pass over that same marketplace that is suspended in its fetch. `MarketplacePolicy.ApplyUpdates.nextLaunch` writes that record, and a second process over the same cache can write it while a pass of this process runs.

    Thus the fix must remove the wait.
  timestamp: 2026-09-15T23:33:35.003140+00:00
- actor: claude-code
  id: 01m2kq3hs4s3bkyh2pt0hphhey
  text: |-
    ### What the test showed, and the fix

    The test `aSecondStartFinishesWhileAPassHoldsTheWriterLock` in `Tests/FoundationModelsSkillsTests/MarketplacePinTests.swift` reproduces the wait:

    1. A store with `.nextLaunch` starts, then updates, so `state.json` holds a pending snapshot.
    2. A `GatedGitTransport` holds the fetch of the next pass. That pass is a `start()`, and it holds the writer lock over the hold.
    3. The test writes a pending record into `state.json`, as a second process over the same cache does.
    4. A second `start()` runs. Its `applyPendingSnapshots()` reaches `MarketplaceCache.adopt`.

    Before the fix the run hung: `swift test --filter aSecondStartFinishesWhileAPassHoldsTheWriterLock` did not end within 120 seconds, and the process needed a kill. That is the deadlock, proved.

    The fix takes the wait out of the lock, not out of `start()`:

    - `MarketplaceCache.openWriterLock()` now calls `flock(descriptor, LOCK_EX | LOCK_NB)`.
    - A held folder gives the new `MarketplaceCacheError.writerLockHeld(path:)`, whose text is `Another writer holds the marketplace folder of "<lock file>" now.`
    - The call also reads `errno` before `close(2)`, because a close can replace the value. The old code read it after the close.

    Both entry points of the lock are in the actor path, thus both are now free of a wait: the synchronous `withWriterLock` that `adopt` and `install` use, and the asynchronous one that `sync` holds over its fetch.

    What a caller sees: the refused pass keeps the snapshot that it serves, publishes `MarketplaceEvent.failed`, and records an error diagnostic. A pending record that the adopt did not apply stays in `state.json`, thus the next launch applies it. Nothing retries on a timer, and the change adds no time value at all.

    This also removes a second wait that the card did not name: two processes over one cache. A blocking `flock` there would hold the actor thread of this process for the whole fetch of the other process. Now the second process reports the refusal and keeps its snapshot.

    Evidence: `swift test` gives 677 tests in 51 suites passed. `swift build --build-tests` gives no warning.

    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift, Tests/FoundationModelsSkillsTests/MarketplacePinTests.swift; `swift test` 677 tests in 51 suites passed, 0 failed, 0 warnings
    - next: /review
  timestamp: 2026-09-15T23:40:46.756458+00:00
- actor: claude-code
  id: 01m2kq9k7st8m0wbgcsmsfhcke
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` clean (0 warnings); `swift test` — 677 tests, 51 suites, 0 failed, 0 skipped, 0 warnings
    - confirmed: `aSecondStartFinishesWhileAPassHoldsTheWriterLock()` in `MarketplacePinTests.swift` passed
    - next: ready for review
  timestamp: 2026-09-15T23:44:04.857010+00:00
position_column: doing
position_ordinal: '80'
title: 'MarketplaceCache: a blocking flock can wait on a holder that needs the actor'
---
## What

The audit of ^zj5b7r9 raised this. `MarketplaceCache.openWriterLock()` calls the blocking `flock(descriptor, LOCK_EX)`. The async `withWriterLock` holds that lock over a suspension point on purpose, because the fetch in the middle of a sync is asynchronous (marketplace.md §7.6).

Thus, if a pass of an earlier `start()` is suspended at an `await` while it holds the writer descriptor, and a second `start()` on the same actor reaches `flock`, the second call blocks a thread while it waits for a holder that needs the actor to make progress. `adopt` runs at the head of `start()` and takes the blocking lock, so `start()` is the call that can meet this.

This is a liveness question, not a proved defect. No test makes it happen today. Answer it, and make the answer a test.

Two ways out, if the risk is real:
- make `start()` refuse to overlap a live pass, so a second pass never reaches the lock while the first holds it, or
- take the lock with `LOCK_EX | LOCK_NB` in the actor path and give the caller a clear error or a retry on an event.

Never add a hard-coded time value, and never add a sleep or a retry interval.

## Acceptance Criteria
- [x] The question is answered in writing on this task: can two passes of the same store hold and wait for the same writer lock?
- [x] If yes, the fix removes the wait, and a test proves that two overlapping `start()` calls both finish
- [x] If no, a test proves that a second `start()` cannot reach the lock while a pass holds it
- [x] No hard-coded time value is part of the fix or the test

## Tests
- [x] A test in `Tests/FoundationModelsSkillsTests/MarketplacePinTests.swift` or `MarketplaceStoreTests.swift` that holds a fetch with `GatedGitTransport` and calls `start()` a second time
- [x] Run `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace