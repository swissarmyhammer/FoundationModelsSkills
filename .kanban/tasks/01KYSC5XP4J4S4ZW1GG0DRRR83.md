---
position_column: todo
position_ordinal: '8380'
title: 'SkillWatcher: cancel overwritten sources, disclose busy-ancestor cost'
---
## What
The late-root arming fix (76c1528) works but introduced a latent defect and left two gaps:

1. **Un-cancelled source overwrite / descriptor leak**: `watchEntry` overwrites `watchedSources[url.path]` without cancelling the prior source (`Registry/SkillWatcher.swift:233`). Newly reachable via ancestor arming when roots are ordered `[<missing child of A>, A]`: the ancestor watch on `A` is installed first, then `watchTree(at: A)` replaces it — the old DispatchSource is released un-cancelled, its cancel handler (which closes the descriptor, `:230-232`) never runs. Fix: cancel any existing source for the path before storing a replacement.
2. **Busy-ancestor rebuild storms undisclosed**: the nearest existing ancestor of a missing root can be a busy directory (e.g. `~` when `~/.skills` is absent); unrelated activity there triggers a full catalog rebuild every debounce window. Disclose this in the type's doc comment (`SkillWatcher.swift:14-19`) and, if cheap, filter ancestor events to ones that could create the awaited path component before flushing.
3. **Coverage gap**: no test asserts an EDIT to a file under a late-created root fires after the watch escalates from ancestor to recursive tree — the delete-recreate case's signal can be attributed to the ancestor watch alone. Add: create root late → await escalation → edit an existing file under it → exactly one coalesced callback.

## Acceptance Criteria
- [ ] Roots `[missing-child-of-A, A]` produce no leaked descriptor (source for A cancelled before replacement; assert via cancel-handler side effect or descriptor counting)
- [ ] Post-escalation edit fires a callback (new test)
- [ ] Busy-ancestor cost documented (and filtered if implemented)

## Tests
- [ ] Extend `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift` — overwrite-cancellation case; post-escalation edit case
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.