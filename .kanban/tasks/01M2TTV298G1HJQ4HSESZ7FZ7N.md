---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2tvdy4qvhd5qzdbxyjdpgce
  text: |-
    Research result (before measurement).

    HOW IT WORKS: `SkillsRegistry.ReloadCoordinator` gives `SkillWatcher` the closure `rebuild` as `onChange`. `rebuild` builds the catalog, replaces `catalogBox`, and calls `broadcaster.publish(...)`. All of this runs synchronously on the watcher queue, inside `SkillWatcher.flush()`. `flush()` has this sequence: `onChange()`, then `cancelAllWatchedSources()`, then `armRoots()`.

    HYPOTHESIS: the publication goes out BEFORE the watcher cancels the old sources and opens the new ones. The test writes the next `SKILL.md` as soon as it sees the publication. If the watcher queue thread is slow (loaded host), that write arrives between `onChange()` and `armRoots()`. The old sources get the kernel event, but their handler is behind `flush()` on the serial queue, and `cancel()` drops it. The new sources open after the write, thus they see nothing. No timer starts, no rebuild runs, and the two consumers lose the same reload. This is a defect in the product code (`SkillWatcher.flush()`), not in the test: a host application that edits a file immediately after a reload loses that edit too.

    NEXT: measure the sequence under load to confirm or reject the hypothesis.
  timestamp: 2026-09-18T18:11:02.423785+00:00
- actor: claude-code
  id: 01m2tw532ex3pnhszbx1j9vk6a
  text: |-
    Measurement result: the step that loses the reload is the EVENT SOURCE step in `SkillWatcher.flush()`. The debounce and the reload are not the cause. The defect is in the product code, not in the test.

    Method: temporary trace lines (microsecond uptime) in `flush()` (`flush-begin`, `onChange-done`, `rearm-done`) and in `handleRawEvent()` (`raw-event`), plus a temporary bounded trace test (40 write cycles, 3 seconds maximum for each cycle) that logged `write-done` and `observed`. All trace code is removed.

    1. Loaded full runs (64 load processes, 18 full runs, 720 trace cycles): 0 lost reloads, 0 failures of the five-reload burst test. The natural rate is low, as the card says (2 in 53). Timing from 480 of these cycles: the time between `onChange-done` and `rearm-done` had a mean of 2.6 ms and a maximum of 50.1 ms. The test saw the publication as early as 140 microseconds after `rearm-done`, and 11 times less than 1 ms after it. The test polls each 10 ms, thus a window of 50 ms is sufficient for the test to write inside the window.

    2. Causal experiment: a temporary `usleep(30_000)` between `onChange()` and `cancelAllWatchedSources()` made the window 30 ms wider. Result with no load: 20 of 40 cycles lost. Each lost cycle has the same sequence:
       - `watcher onChange-done` (the publication is out)
       - `test observed N` then `test write-done N+1` (the test writes the next file)
       - `watcher rearm-done` (after the write)
       - no `raw-event` follows, no flush follows, and the test waits the full time limit.

    Cause: `flush()` calls `onChange()` first, and only then cancels the old sources and opens new ones. `onChange` is the registry rebuild, which publishes to `onReload` and `commandUpdates` on the watcher queue. A write that arrives after the rebuild read the file and before `armRoots()` completes goes to the OLD sources. Their event handlers are behind `flush()` on the serial queue, and `cancel()` drops them. The new sources open after the write and see nothing. The two consumers lose the same reload because the rebuild never runs.

    This also explains why only a loaded host shows it: the watcher queue thread must lose the CPU between the publication and the end of `armRoots()`.

    Planned correction: `flush()` makes the new watch tree BEFORE it calls `onChange()`. Then each change is either before the new sources (the rebuild reads it) or after them (a new source reports it). The class comment already says that the entries are watched "by the time `onChange` fires"; the code did not do that.
  timestamp: 2026-09-18T18:23:41.134088+00:00
- actor: claude-code
  id: 01m2twzq2cehhnjfm86j0rx2e1
  text: |-
    Implementation notes.

    Correction: `SkillWatcher.flush()` now cancels the old sources and calls `armRoots()` BEFORE it calls `onChange()`. The two `isWatching` checks around `onChange()` became one check at the start: a reentrant `stop()` inside `onChange` cancels the sources that the flush opened, and nothing after `onChange` opens a source again. The only production caller of `SkillWatcher` is `SkillsRegistry.ReloadCoordinator`, whose `onChange` is a full rebuild, thus the new sequence needs no change there.

    Regression test: `SkillWatcherTests.aChangeMadeWhileOnChangeRunsIsReportedAfterTheFlush`. It edits `SKILL.md` inside `onChange` (new helper `OneTimeEdit`, new `duringOnChange:` parameter on `withWatcher`), thus the edit is in the flush on a host of any speed. RED before the correction: `Expectation failed: await Self.reportedTheEditInsideOnChange(signals)` after 10.0 seconds. GREEN after it.

    Known property of the new sequence: a change that arrives after `armRoots()` and before the rebuild reads the file is read by the rebuild AND reported by a new source. That gives one more reload with the same content. This is at-least-once delivery. The old sequence was at-most-once, which is the defect.

    What did not work: the natural failure did not occur in 18 loaded full runs (720 trace cycles). The proof of the cause is the causal experiment (30 ms wider window: 20 of 40 cycles lost) plus the deterministic test.

    Deviation to examine in the review: the rules file from `dump validators` has 12097 lines (657 KB), most of it for Dart, Go, Python, Rust, and TypeScript. I read the general `code-hygiene` rules at its start, the `disallowed-constructs-swift` rule list, and the full `swift` and `test-integrity` sections. I did not read the other sections.

    ### implement — changed
    - evidence: 2 files — `Sources/FoundationModelsSkills/Registry/SkillWatcher.swift`, `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift`. `swift test --filter FoundationModelsSkillsTests`: 709 tests passed, 0 warnings. 25 loaded full runs (64 load processes): 25 passed, 0 failures; `twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst` 0 failures of 25; `aChangeMadeWhileOnChangeRunsIsReportedAfterTheFlush` 0 failures of 25.
    - next: `/review`. The task stays in `doing`.
  timestamp: 2026-09-18T18:38:13.580762+00:00
- actor: claude-code
  id: 01m2tx1t65x720a2ncdfty6gtv
  text: |-
    ### test — green
    - evidence: `swift test` — 709 tests passed, 0 failed, 0 skipped, 54 suites; 0 warnings. New test `aChangeMadeWhileOnChangeRunsIsReportedAfterTheFlush` passed. No temp trace code found (`TEMPTRACE`, `TRC`, `usleep`, `TemporaryTrace`) in Sources or Tests.
    - next: ready for review.
  timestamp: 2026-09-18T18:39:22.309930+00:00
- actor: claude-code
  id: 01m2tx2rsp7d90cxas9g2xjxe5
  text: |-
    ### commit — changed
    - evidence: 75ef62a fix(watcher): open new sources before onChange in flush
    - next: none
  timestamp: 2026-09-18T18:39:53.654851+00:00
- actor: claude-code
  id: 01m2tx6de9c7p2gbshv90sxjfp
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 75ef62a), task-mode. Counts: 0 findings, 0 confirmed, 0 refuted, 7 validator runs attempted, 0 failed, 0 skipped. 2 files reviewed (`Sources/FoundationModelsSkills/Registry/SkillWatcher.swift`, `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift`). 4 `.kanban/` files were not reviewed because `.reviewignore` excludes them. The description had no prior `## Review Findings` section, thus no prior item is open.
    - notes from the implementer: (1) the new test uses the `waitUntil(timeout:_:)` poll of the suite to wait for the kernel event; (2) the natural failure did not occur under load, and the reproduction was a causal experiment. The engine reviewed the changed lines and gave no finding on them. The review skill makes the engine the analysis, thus the reviewer added no finding and dropped no finding. A person who does not agree with note (1) must decide on the acceptance text; the engine does not examine acceptance text.
    - next: none. The task moved to `done`.
  timestamp: 2026-09-18T18:41:53.097882+00:00
- actor: claude-code
  id: 01m2tx6w94aasrqwwar0az9wvt
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files (SkillWatcher.swift, SkillWatcherTests.swift). Cause: `flush()` called `onChange()` before it opened the new event sources, thus a write during the rebuild was lost. Correction: open the new sources first.
    - test: green — swift test, 709 passed, 0 failed, 0 skipped, 54 suites, 0 warnings (first run)
    - commit: 75ef62a
    - review: clean — HEAD~1..HEAD, 0 findings, 7 validator runs, 2 files reviewed. The task moved to done.
    - loaded runs: 25 of 25 passed with 64 load processes. Subtask 3 of `^wycfkqk` is now checked.
  timestamp: 2026-09-18T18:42:08.292481+00:00
position_column: done
position_ordinal: f280
title: 'SkillsRegistryReloadTests: the five-reload burst test loses one reload now and then in a loaded full parallel run'
---
## What

`twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst` in `Tests/FoundationModelsSkillsTests/SkillsRegistryReloadTests.swift` fails now and then when the host has a high load.

Evidence from 2026-09-18:

- 2 failures in 53 loaded full runs during card `^wycfkqk`. The command was `swift test --skip-build --filter FoundationModelsSkillsTests` with 64 `yes > /dev/null` load processes. The first failure came while a temporary trace test of that card added 400 install cycles to the run. The second failure came with no trace code in the tree.
- 1 failure in the test step of card `^dfgw3nc`, while two `sourcekit-lsp` processes used more than 100% CPU each.
- Failure text: `expected at least 4 events, observed 3`, `expected at least 5 events, observed 4`, `onReload observed 4 of 5 reloads`, `commandUpdates observed 4 of 5 reloads`. The test failed after 24.7 seconds.

What the evidence shows: one reload of the five-write burst never arrives. Both consumers (`registry.onReload` and `registry.commandUpdates`) lose the same reload, thus the loss is before the fan-out. The cause is in the watcher or in the reload, not in one stream. The test already waits `ReloadTestSupport.expectedSignalTimeout` (10 seconds) for each write, thus the reload is lost, not late.

Places to examine:

- `Sources/FoundationModelsSkills/Registry/SkillWatcher.swift`: the file system event sources, the debounce, and the step that arms the sources again after a write that replaces a file (`writeSkillFile` writes atomically, thus the file is replaced). A write that arrives while the watcher arms its sources again is a possible cause.
- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: the reload that one watcher signal starts, and the publication to `onReload`. A reload that finds the same metadata as before publishes nothing; a write that the preceding reload already read is a possible cause.
- `Tests/FoundationModelsSkillsTests/ReloadTestSupport.swift`: `EventTally`, `tally(_:into:)`, and `poll(_:until:timeout:)`.

Rules for the correction: do not add a retry, a skip, a disabled test, or a longer time limit. Remove the dependence on host speed. Commit 5c07ea6 (card `^dfgw3nc`) shows the accepted approach: it gave `SkillWatcher` the `DebounceTimer` seam (`startDebounceTimer`), and the test drives the timer itself.

- [x] Reproduce the failure under a loaded full parallel run, and record which step loses the reload (the event source, the debounce, or the reload). (The natural failure did not occur in 18 loaded full runs with 720 trace cycles. A causal experiment that made the window 30 ms wider reproduced the loss in 20 of 40 cycles. The step is the event source step in `SkillWatcher.flush()`. See the comments.)
- [x] Write a test that reproduces the loss with no dependence on host speed, and see it fail.
- [x] Correct the cause in the source.
- [x] Make sure that 25 loaded full runs pass.

## Acceptance Criteria

- [x] The card comments name the step that loses the reload, with the evidence.
- [x] A new test in `Tests/FoundationModelsSkillsTests/` reproduces the loss with no sleep and no wall-clock wait, fails before the correction, and passes after it. (Note for the review: the edit is made inside `onChange`, thus no sleep and no clock puts it in the window. The test uses the `waitUntil(timeout:_:)` poll of the suite to wait for the kernel event, as the tests of commit 5c07ea6 do. The time limit only ends a failed run; it cannot change a result.)
- [x] `twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst` passes in 25 of 25 loaded full runs (64 load processes).
- [x] The diff adds no retry, no skip, no disabled test, and no larger time value.

## Tests

- [x] Add the regression test to `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift` or `Tests/FoundationModelsSkillsTests/SkillsRegistryReloadTests.swift`, in the file of the component that has the cause.
- [x] Run `swift test --filter FoundationModelsSkillsTests`: all tests pass, with no warning.
- [x] Run `swift test --skip-build --filter FoundationModelsSkillsTests` 25 times with 64 `yes > /dev/null` load processes: 0 failures.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass.