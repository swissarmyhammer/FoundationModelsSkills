---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2tnr2zvp4j72at6dmn0sm3d
  text: |-
    ### Research: the cause is found

    I added a temporary trace to the burst test. The trace printed the time that the five writes took. I ran the full `swift test` 12 times with 64 `yes` load processes.

    Result: 11 runs passed. The burst took 7 ms to 110 ms in each of them. 1 run failed with the two expectations of this card. In that run, and only in that run, the burst took 181 ms.

    The watcher in the tests has a debounce interval of 150 ms. The test writes on the real clock, and the watcher counts the quiet period on the real clock. When the host is loaded, the five writes take more than 150 ms. The first flush then occurs in the middle of the burst. The flush makes the watch tree again, the new tree sees the subsequent writes, and a second callback follows. The count is 2, not 1. `SkillWatcher` is correct: the writes were not in one debounce window.

    Thus the cause is in the test. The test assumes that its file work is faster than 150 ms, and no code makes that true. Each test that calls `expectExactlyOneSignal` has the same cause (`writeSkillFile` makes a folder and then writes a file; a delay of more than 150 ms between the two gives two callbacks).

    What did not reproduce the failure: 40 runs of `--filter SkillWatcherTests` only, with 96 to 160 CPU load processes, gave one failure with no captured output. CPU load only is a weak trigger. The full parallel suite (file system load) is the trigger.

    ### Plan

    Do not increase 150 ms. Remove the real clock from the assertion:

    - `SkillWatcher` gets an internal initializer with a debounce timer seam. The default timer is `queue.asyncAfter`, as before.
    - The tests that assert "exactly one callback" use a manual timer. The test makes its file changes, waits until the watcher started a timer, and then ends the quiet period itself. The speed of the host cannot divide a burst.
    - The tests of `stop()` and of the descriptor count keep the real timer, thus the `asyncAfter` path stays covered.
  timestamp: 2026-09-18T16:31:43.611367+00:00
- actor: claude-code
  id: 01m2tq2bjq74kczth3gm8dnbtv
  text: |-
    ### Implementation

    Production, `Sources/FoundationModelsSkills/Registry/SkillWatcher.swift`:

    - New internal `typealias DebounceTimer` and a new internal initializer `init(roots:debounceInterval:startDebounceTimer:onChange:)`. The public initializer has the same signature as before. It is now a `convenience` initializer that gives the production timer (`queue.asyncAfter`). `SkillsRegistry`, the only production caller, needs no change.
    - `pendingFlush: DispatchWorkItem?` is replaced by `newestTimerNumber: Int`. Each event increases the number and starts a timer that remembers it. `flushIfCurrent(_:)` drops a timer whose number is not the newest. `stop()` increases the number too. The behavior is the same as the cancelled work item, but the closure that goes through the seam is `@Sendable` (a `DispatchWorkItem` is not).

    Tests, `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift`:

    - New `ManualDebounceTimer` (a `Mutex` guards its list) and `WatchedSignals`. `withWatcher` gives each watcher the manual timer.
    - `expectExactlyOneSignal` now: waits for the timer start, asserts that the events made no callback by themselves, ends the quiet period, then asserts exactly one callback.
    - The burst test makes the skill first (so the folder and `SKILL.md` have sources of their own), writes five times, and waits for two timer starts or more before it ends the quiet period.
    - `unrelatedActivityUnderAnArmedAncestorProducesNoCallback` now asserts zero timer starts. With a manual timer, a callback count of zero proves nothing by itself.
    - Three tests that made their own watcher now use `withWatcher`. The tests of `stop()`, of the reentrant `stop()`, and of the descriptor count keep the real timer.
    - No test is skipped, disabled, or retried. No time limit changed: 150 ms, 10 s, and 1 s are the same.

    ### Evidence

    - RED: the test build failed with `'DebounceTimer' is not a member type` and `extra argument 'startDebounceTimer'`.
    - GREEN: `swift test --filter SkillWatcherTests` — 17 tests passed.
    - The tests can fail: with the `guard timerNumber == newestTimerNumber` line removed for a moment, 8 tests failed, the burst test included. The line is restored.
    - 25 full runs with 64 load processes: `SkillWatcherTests` failed 0 times (before the change: 1 of 12).
    - 20 full runs with no load, and one full `swift test`: 705 tests in 54 suites passed each time. The build has no warnings.

    ### Found on the way

    In the 25 loaded runs, two tests of `MarketplaceCacheTests` failed one time each (`aLeaseHoldsItsSnapshotUntilItIsReleased`, `cleanupKeepsASnapshotThatASharedLockHolds`). They do not touch `SkillWatcher`. New card: `^wycfkqk`.

    Note for the next agent: I did one text replacement in the test file with a shell script, not with the file tool. The result was read back and compiled.
  timestamp: 2026-09-18T16:54:48.663838+00:00
- actor: claude-code
  id: 01m2tq2knczc5pqpend162rpm6
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsSkills/Registry/SkillWatcher.swift, Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift. `swift test`: 705 tests in 54 suites passed, 0 failures, 0 warnings. 25 loaded full runs: 0 `SkillWatcherTests` failures. 20 full runs with no load: 0 failures.
    - next: `/review`. The two `MarketplaceCacheTests` failures under load are on card `^wycfkqk`.
  timestamp: 2026-09-18T16:54:56.940108+00:00
- actor: claude-code
  id: 01m2tqge53awt693bf3zymea4m
  text: |-
    ### test — green
    - evidence: swift test — 705 tests, 54 suites, 0 failures, 0 warnings, 0 skipped (two clean runs in a row)
    - context: one run under this same command showed a transient failure in SkillsRegistryReloadTests.twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst. I checked this against a stash of the DebounceTimer/ManualDebounceTimer diff: the clean tree also failed once, in a different suite (SkillWatcherTests), under three repeat runs. The machine has two long-running sourcekit-lsp processes pinned over 100% CPU each (unrelated to this task). This is the same real-CPU-contention timing pattern already tracked on card ^wycfkqk for MarketplaceCacheTests. It is not caused by this diff.
    - no change made to MarketplaceCache.
    - next: none, ready for review.
  timestamp: 2026-09-18T17:02:30.051551+00:00
- actor: claude-code
  id: 01m2tqhtzmg5v449mwdyqjt7df
  text: |-
    ### commit — changed
    - evidence: 5c07ea6 fix(tests): use a DebounceTimer seam so SkillWatcher debounce tests do not wait on host speed
    - next: none, ready for review.
  timestamp: 2026-09-18T17:03:15.956042+00:00
- actor: claude-code
  id: 01m2tqqnr3y7ba8e1171eaznvj
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 5c07ea6). Counts: findings 0, confirmed 0, refuted 2, attempted 7, failed 0, skipped 0. 2 files reviewed: `Sources/.../Registry/SkillWatcher.swift` and `SkillWatcherTests.swift`. 6 `.kanban/` files were not reviewed because of `.reviewignore`. The description has no prior `## Review Findings` section, thus no prior item is open.
    - next: none. The task is in `done`.
  timestamp: 2026-09-18T17:06:27.203685+00:00
- actor: claude-code
  id: 01m2tqr3k89yph80762k1qb08m
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files (SkillWatcher.swift, SkillWatcherTests.swift)
    - test: green — swift test, 705 tests in 54 suites, 0 failures, 0 warnings, 0 skipped (two clean runs)
    - commit: 5c07ea6
    - review: clean — HEAD~1..HEAD, findings 0, refuted 2, 7 validator runs, 2 files reviewed. The task moved to done.
  timestamp: 2026-09-18T17:06:41.384663+00:00
position_column: done
position_ordinal: f080
title: 'SkillWatcherTests: the debounce burst test fails now and then in a full parallel run'
---
## What

`SkillWatcherTests.burstOfWritesWithinTheDebounceWindowProducesExactlyOneCallback` failed one time in a full `swift test` run on 2026-09-18, during the work on card `^nvnv7ep`. The subsequent full run passed with no change to the code, thus the failure depends on timing.

The two failed expectations were:

- `afterFirst == baseline + 1`
- `afterSettling == baseline + 1`

The work on `^nvnv7ep` changed only documents, doc comments, and two text strings. It did not touch `SkillWatcher`.

## The work

- [x] Run the test many times under a loaded parallel run and find why the count is not `baseline + 1`.
- [x] Correct the cause. Do not add a retry, and do not only increase a time limit.
- [x] Make sure that the full `swift test` run is stable.