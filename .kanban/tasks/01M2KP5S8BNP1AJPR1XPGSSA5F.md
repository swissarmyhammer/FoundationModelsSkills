---
assignees:
- claude-code
position_column: todo
position_ordinal: 9a80
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
- [ ] The question is answered in writing on this task: can two passes of the same store hold and wait for the same writer lock?
- [ ] If yes, the fix removes the wait, and a test proves that two overlapping `start()` calls both finish
- [ ] If no, a test proves that a second `start()` cannot reach the lock while a pass holds it
- [ ] No hard-coded time value is part of the fix or the test

## Tests
- [ ] A test in `Tests/FoundationModelsSkillsTests/MarketplacePinTests.swift` or `MarketplaceStoreTests.swift` that holds a fetch with `GatedGitTransport` and calls `start()` a second time
- [ ] Run `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace