---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
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

- [ ] Reproduce the failure under a loaded full parallel run, and record which step loses the reload (the event source, the debounce, or the reload).
- [ ] Write a test that reproduces the loss with no dependence on host speed, and see it fail.
- [ ] Correct the cause in the source.
- [ ] Make sure that 25 loaded full runs pass.

## Acceptance Criteria

- [ ] The card comments name the step that loses the reload, with the evidence.
- [ ] A new test in `Tests/FoundationModelsSkillsTests/` reproduces the loss with no sleep and no wall-clock wait, fails before the correction, and passes after it.
- [ ] `twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst` passes in 25 of 25 loaded full runs (64 load processes).
- [ ] The diff adds no retry, no skip, no disabled test, and no larger time value.

## Tests

- [ ] Add the regression test to `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift` or `Tests/FoundationModelsSkillsTests/SkillsRegistryReloadTests.swift`, in the file of the component that has the cause.
- [ ] Run `swift test --filter FoundationModelsSkillsTests`: all tests pass, with no warning.
- [ ] Run `swift test --skip-build --filter FoundationModelsSkillsTests` 25 times with 64 `yes > /dev/null` load processes: 0 failures.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass.