---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2tqvr8tct92sxvcvr5gzt3t
  text: |-
    ### Research: the cause is the `posix_spawn` window, and `O_CLOEXEC` does not close it

    I read the comments of `^01M2K8A6` and `^01M2KP5S8`. All lock opens in `MarketplaceCache.swift` (the snapshot lease, the cleanup check, the writer lock) and the test probe `SnapshotLockProbe.isLocked` already set `O_CLOEXEC`. No other `open(2)` in the package touches a lock file or a snapshot folder. Each test uses its own temporary cache, thus no second test opens the same lock file. The only possible second holder is a child process.

    `O_CLOEXEC` closes a descriptor at the exec step. The kernel copies the descriptor table of the parent to the new process at the fork step of `posix_spawn`, and closes the close-on-exec entries later, at the exec step. Between the two steps the new process holds a reference to the open file description. `flock(2)` belongs to the open file description, thus a `close(2)` in the parent during that window does not release the lock. A loaded host makes the window longer. `Foundation.Process` and `ScriptProcessRunner` both use `posix_spawn`, and `RunScriptTests`, `ShellInjectionTests`, and `SkillsDemoTests` spawn processes in parallel with the cache tests.

    I proved this with a C experiment outside the package (scratchpad `window.c`). One thread does: open a folder with `O_CLOEXEC`, `flock(LOCK_SH)`, `close`, open again, `flock(LOCK_EX | LOCK_NB)`. Four threads call `posix_spawn("/usr/bin/true")` in a loop. Result with `O_CLOEXEC` only: 2299 stale locks in 200000 cycles. Result with `O_CLOEXEC | O_CLOFORK`: 0 stale locks in 200000 cycles. `O_CLOFORK` tells the kernel not to copy the descriptor to the new process at all, thus there is no window.

    This explains the two failures:
    - `aLeaseHoldsItsSnapshotUntilItIsReleased`: the lease descriptor was in a process that was between fork and exec when `releaseNow()` closed it, thus the probe found the folder locked.
    - `cleanupKeepsASnapshotThatASharedLockHolds`: the writer lock descriptor of one install was in such a process when the next install asked for the writer lock, thus `LOCK_NB` gave `writerLockHeld`.

    Plan: add `O_CLOFORK` to each lock open, through one shared helper, and prove the flags with a test that reads the descriptor flags. That test does not depend on host speed.
  timestamp: 2026-09-18T17:08:40.858412+00:00
- actor: claude-code
  id: 01m2ttxz5ex860bvfa5sjfhqwd
  text: |-
    ### What the loaded runs showed, and the correction

    **Reproduction.** I added temporary trace code (now removed): a probe after each lock release, and a trace test that did 400 install cycles with a lease. The command was `trace.sh 64 <n> FoundationModelsSkillsTests`.

    - The writer lock failure came back in a third test, `aReaderResolvesACompleteSnapshotDuringRepeatedInstalls`: `Another writer holds the marketplace folder of ".../skills-ce750fb6/lock" now.` Thus the defect is in the lock code, not in one test.
    - The trace found 3 stale snapshot locks in 7 loaded runs. Each lock became free with no action: after 36.5 ms (329 probes), after 3.9 ms (48 probes), and after 1.2 ms (39 probes).
    - `lsof` on the path named no holder each time, and `proc_listchildpids` gave an empty child list at the stale moment. The holder lives for milliseconds, which is less than the start time of `lsof`. A holder that a process list does not show, and that goes away with no action, agrees with a process that is between the fork step and the exec step of `posix_spawn`. The C experiment in the research comment is the direct proof: 2299 stale locks in 200000 cycles with `O_CLOEXEC`, 0 with `O_CLOEXEC | O_CLOFORK`.
    - A lock that is held for a long time (the writer lock during an install) is hit more frequently than a lock that is held for microseconds. A first trace loop with no install between lease and release found 0 stale locks in 9000 cycles.

    **A dead end, for the next agent.** One trace run hung for 9.5 minutes and the orchestrator stopped it. The stack sample showed all `openWriterLock()` samples at the `open` call and at the `throw cannotLock` line, none at `flock`. The cause was my trace, not a leaked holder: the loop asked for the writer lock before the first `install` made the marketplace folder, the closure read each throw as "locked", and the `while` loop had no bound. I gave the loop a bound and counted only `writerLockHeld` as a lock.

    **Correction.** `Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift` has a new constant `noInheritanceOpenFlags = O_CLOEXEC | O_CLOFORK`. The three opens that take a `flock(2)` lock use it: the snapshot lease (`sharedLock`), the cleanup check (`removeSnapshot`), and the writer lock (`openWriterLock`). `O_CLOFORK` tells the kernel not to copy the descriptor at the fork step, thus the window does not exist. The doc comment of the constant tells why `O_CLOEXEC` alone is not sufficient. `SnapshotLockProbe.isLocked` in the test support uses the same constant. The change adds no retry, no skip, and no time value.

    **Tests that do not depend on host speed.** Three new tests in `MarketplaceCacheTests.swift` read the descriptor flags with `fcntl(F_GETFD)` while the lock is held: `aLeaseDescriptorStaysOutOfEachChildProcess`, `aSnapshotInUseDescriptorStaysOutOfEachChildProcess`, `theWriterLockDescriptorStaysOutOfEachChildProcess`. The new helper `OpenDescriptorProbe` in `MarketplaceTestSupport.swift` finds the descriptor by its path (`proc_pidinfo(PROC_PIDLISTFDS)` and `F_GETPATH`). RED before the correction: `flags → [1]`, expected `[3]`, in all three tests. GREEN after it. The descriptor of the cleanup check is open for too short a time to read; it uses the same constant.

    **Proof under load.** With the trace still in the tree after the correction: 8 loaded runs with 3200 install cycles gave 0 stale locks (before: 3 in 7 runs). With the trace removed: 25 loaded full runs gave 0 failures of a marketplace test. 1 of the 25 runs failed in `SkillsRegistryReloadTests.twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst` (`onReload observed 4 of 5 reloads`). That is a different defect; it also failed one time before the correction. I made card `^sz7fz7n` for it and did not correct it here. Thus the third subtask stays open in the description, with this state written beside it.

    **Rules.** `dump validators` gave a file of 657 KB. I read the sections that apply to Swift (the swift, duplication, reuse, test-integrity, invariant-propagation, and disallowed-constructs sections). I did not read the sections for Dart, Go, Python, Rust, and TypeScript.

    **Not changed, found on the way.** `sharedLock(onDirectory:)` reads `errno` after `close(2)` in its `flock` failure path; `openWriterLock()` reads it before. `SkillWatcher` opens its event descriptors with `O_EVTONLY` and no close-on-exec flag; they hold no lock. No card holds these two items.
  timestamp: 2026-09-18T18:02:19.182086+00:00
- actor: claude-code
  id: 01m2tty6d89gvj0e5w71c614g5
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift, Tests/FoundationModelsSkillsTests/MarketplaceCacheTests.swift, Tests/FoundationModelsSkillsTests/MarketplaceTestSupport.swift. `swift build --build-tests`: 0 warnings. `swift test` with no load: 708 tests in 54 suites passed, 0 failed. 25 loaded full runs (64 load processes): 0 failures of a marketplace test; 1 run failed in `SkillsRegistryReloadTests.twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst`, which card `^sz7fz7n` holds. All temporary trace code is removed (`TemporaryTraceTests.swift` deleted, no `TemporaryTrace` text in `Sources` or `Tests`).
    - open: the third subtask ("Make sure that 25 loaded full runs pass") is not checked, because 24 of 25 runs passed. The one failure is not a lock failure. A person must decide if that is sufficient for this card, or if this card waits for `^sz7fz7n`.
    - next: /review
  timestamp: 2026-09-18T18:02:26.600459+00:00
- actor: claude-code
  id: 01m2tv2ft54jdevacw8mptsxaq
  text: |-
    ### test — green
    - evidence: swift test — 708 tests, 54 suites, 0 failed, 0 skipped (first run: SkillsRegistryReloadTests.twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst failed with "expected at least 5 events, observed 4"; this is the known flaky test on card ^sz7fz7n and its code was not changed; second run: all 708 tests passed)
    - next: ready for review
  timestamp: 2026-09-18T18:04:47.301099+00:00
- actor: claude-code
  id: 01m2tv3jbxk5870mgs4f1kfzq2
  text: |-
    ### commit — changed
    - evidence: 002c1a0 fix(marketplace): stop a child process from holding the flock lock
    - next: none
  timestamp: 2026-09-18T18:05:22.685653+00:00
- actor: claude-code
  id: 01m2tvb4529nktjz2b7vjc1qt6
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 002c1a0). Counts: 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed. 3 files reviewed. 6 `.kanban/` files not reviewed (`.reviewignore`). The description has no prior `## Review Findings` section.
    - subtask note: the subtask "Make sure that 25 loaded full runs pass" stays unchecked. This step did not check it and did not change the description. The `review` skill gates the move to `done` on new findings and on prior `## Review Findings` items only. It has no rule about an unchecked subtask. Thus the task moved to `done`. The 1 failed run of 25 is `SkillsRegistryReloadTests.twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst`, which card `^sz7fz7n` holds.
    - next: a person decides if the unchecked subtask must be checked, or if the task must go back to `review` until card `^sz7fz7n` is done.
  timestamp: 2026-09-18T18:09:30.274043+00:00
- actor: claude-code
  id: 01m2tvbjnwvdp16mkvjvqgj8pm
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files (MarketplaceCache.swift, MarketplaceCacheTests.swift, MarketplaceTestSupport.swift). Cause: `O_CLOEXEC` alone lets a `posix_spawn` child hold the `flock` lock between the fork step and the exec step. Correction: `O_CLOEXEC | O_CLOFORK`.
    - test: green — swift test, 708 tests in 54 suites, 0 failed, 0 skipped on the second run. The first run failed one time in `SkillsRegistryReloadTests.twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst` (card `^sz7fz7n`).
    - commit: 002c1a0
    - review: clean — HEAD~1..HEAD, 0 findings, 1 refuted, 7 validator runs, 3 files reviewed. The task moved to done.
    - open: subtask 3 ("25 loaded full runs pass") is not checked. 0 marketplace failures in 25 loaded runs; 1 run failed in the `^sz7fz7n` test. Run the 25 loaded runs again after `^sz7fz7n` is done, and then check the subtask.
  timestamp: 2026-09-18T18:09:45.148030+00:00
- actor: claude-code
  id: 01m2twzc50s1p68ckjmzv71mdt
  text: 'The subtask "Make sure that 25 loaded full runs pass" is now checked. Card `^sz7fz7n` corrected the defect in `SkillWatcher.flush()` that lost one reload. After that correction: 25 loaded full runs of `swift test --skip-build --filter FoundationModelsSkillsTests` with 64 `yes > /dev/null` load processes (batches of 12, 12, and 1). Result: 25 of 25 runs passed, 709 tests in each run, 0 failures of any test. Counts by test name: `MarketplaceCacheTests.aLeaseHoldsItsSnapshotUntilItIsReleased` 0 failures, `MarketplaceCacheTests.cleanupKeepsASnapshotThatASharedLockHolds` 0 failures, `SkillsRegistryReloadTests.twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst` 0 failures. No trace code was in the tree during these runs.'
  timestamp: 2026-09-18T18:38:02.400871+00:00
position_column: done
position_ordinal: f180
title: 'MarketplaceCacheTests: two lock tests fail now and then in a loaded full parallel run'
---
## What

Two tests in the suite "Marketplace cache" (`Tests/FoundationModelsSkillsTests/MarketplaceCacheTests.swift`) failed during the work on card `^dfgw3nc`. The run was 25 full `swift test --filter FoundationModelsSkillsTests` runs with 64 `yes > /dev/null` load processes on 2026-09-18. Each test failed one time in 25 runs. Six runs with no load passed.

- `aLeaseHoldsItsSnapshotUntilItIsReleased` — `Expectation failed: !SnapshotLockProbe.isLocked(directory: directory)`. The snapshot folder was still locked after the release of the lease.
- `cleanupKeepsASnapshotThatASharedLockHolds` — `Caught error: Another writer holds the marketplace folder of ".../skills-ce750fb6/lock" now.`

The work on `^dfgw3nc` changed only `SkillWatcher.swift` and `SkillWatcherTests.swift`. It did not touch the marketplace cache.

## Context

Card `^01M2K8A6` found that a forked child process (from `RunScriptTests` or `ShellInjectionTests`) inherits an open lock file handle, and it added `O_CLOEXEC` to the `open(2)` calls. These two failures show the same symptom (a lock that stays after its owner released it, or a lock that a different holder has). Thus a path possibly remains where a child process gets a lock handle. An example: `posix_spawn` or `fork` that occurs between `open` and the moment the flag applies, or a handle that a different `open` call makes without the flag.

## The work

- [x] Reproduce the two failures under a loaded full parallel run. Use `lsof` on the lock file at the moment of failure to name the process that holds the lock.
- [x] Find the cause and correct it. Do not add a retry, a skip, or a longer wait.
- [x] Make sure that 25 loaded full runs pass. (State after the implement step: 25 loaded full runs gave 0 failures of a marketplace test. 1 of the 25 runs failed in `SkillsRegistryReloadTests.twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst`, which is a different defect. Card `^sz7fz7n` holds it. State after the correction of `^sz7fz7n`: 25 of 25 loaded full runs passed, with 0 failures of any test.)