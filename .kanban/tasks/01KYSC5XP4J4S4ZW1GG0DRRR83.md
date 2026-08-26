---
comments:
- actor: claude-code
  id: 01m0z1yebj035va2depm6n8je0
  text: |-
    ### research
    - `watchEntry(at:eventMask:)` at `Sources/FoundationModelsSkills/Registry/SkillWatcher.swift:221-235` writes `watchedSources[url.path] = source` with no cancel of the old source. With roots `[A/missing, A]`, `armRoots()` opens a source on `A` for the missing child first, then `watchTree(at: A)` opens a second source on `A`. The first source is lost and its cancel handler never runs, so its descriptor stays open.
    - `armRoots()` at `:166-174` skips an ancestor when `watchedSources[ancestor.path] != nil`. Two missing roots under one ancestor share one source. A filter of ancestor events must keep a set of awaited children for each ancestor, not one child.
    - `handleRawEvent()` at `:252-260` is the event handler for every source. An ancestor source can use its own handler that stats the awaited children and the ancestor before it calls `handleRawEvent()`. One stat for each event is cheap, so the filter is in scope.
    - Tests run in parallel. A count of process descriptors from `/dev/fd` is not stable. The plan is a counter in the watcher: `+1` in the open path, `-1` in the cancel handler, read through a `@testable` accessor on `queue`.
    - Plan: (1) `installSource` cancels the old source for a path before it stores the new one; (2) `armAncestor(_:awaiting:)` and `handleAncestorEvent(at:)` filter ancestor events; (3) type doc discloses the busy-ancestor cost; (4) three tests: overwrite-cancellation, post-escalation edit, ancestor filter.
  timestamp: 2026-08-26T12:50:28.850753+00:00
- actor: claude-code
  id: 01m0z24376kf7y95mwamteme31
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsSkills/Registry/SkillWatcher.swift, Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift
    - `installSource(at:eventMask:onEvent:)` now cancels the source stored for a path before it stores the replacement, and counts open descriptors (`+1` on open, `-1` in the cancel handler). `openDescriptorCountForTesting` reads that count on `queue`.
    - `armAncestor(_:awaiting:)` records each awaited child for an ancestor in `awaitedChildren` and installs one filtered source. `handleAncestorEvent(at:)` stats the awaited children and the ancestor; only a created child or a removed ancestor restarts the debounce timer. `ancestorArming(for:)` returns the ancestor and the awaited child together. `cancelAllWatchedSources()` also clears `awaitedChildren`.
    - The type doc comment discloses the busy-ancestor cost and the filter.
    - Tests: `rootListedBeforeItsOwnParentLeaksNoDescriptor` (fails with 2 issues when the cancel line is removed, passes with it), `editingAFileUnderALateCreatedRootFiresAfterEscalation`, `unrelatedActivityUnderAnArmedAncestorProducesNoCallback`. Helpers `withTempDirectory`, `withWatcher(over:)`, `waitUntil(timeout:_:)` added; `withWatchedTempRoot` and `waitForCount` now use them.
    - `swift test --filter SkillWatcherTests`: 15 tests, 15 passed.
    - All acceptance boxes are checked in the description.
    - next: `/test`, then `/commit`, then `/review`.
  timestamp: 2026-08-26T12:53:34.054380+00:00
- actor: claude-code
  id: 01m0z27svvf1e3aqpwkxwfn335
  text: |-
    ### test — green
    - evidence: `swift test` — 333 passed, 0 failed, 0 unexpected. One env-gated skip (`SKILLS_INTEGRATION_TESTS`) in `HotReloadLiveTests`; the `test-integrity` rule permits a platform-conditional skip with a clear condition. `swift build --build-tests` has no source warning; the one `missing creator for mutated node` line is a SwiftPM dependency-bundle warning that is also present on the stashed clean tree.
    - When the gated test runs with `SKILLS_INTEGRATION_TESTS=1`, it fails at `HotReloadLiveTests.swift:66` with `Encountered content that cannot be completed into valid JSON`, the same on the clean tree. Filed as `^tb86z9q`.

    ### commit — changed
    - evidence: 85a5d72 fix(watcher): cancel a replaced source and filter armed-ancestor events
    - next: `/review 01KYSC5XP4J4S4ZW1GG0DRRR83 HEAD~1..HEAD`
  timestamp: 2026-08-26T12:55:35.547545+00:00
- actor: claude-code
  id: 01m0z2d1mdhz3je2fqwgf8ryt6
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (85a5d72) — 0 findings, 0 confirmed, 0 refuted; 7 validators attempted, 0 failed; 2 files reviewed (`SkillWatcher.swift`, `SkillWatcherTests.swift`), 6 `.kanban/` files excluded by `.reviewignore`
    - no prior `## Review Findings` section exists on this card
    - next: move to `done`
  timestamp: 2026-08-26T12:58:27.341766+00:00
- actor: claude-code
  id: 01m0z2dbbc0nbrv3527dxvbttd
  text: |-
    ### finish iteration 1 — review clean, task moved to done
    - implement: changed — `Sources/FoundationModelsSkills/Registry/SkillWatcher.swift`, `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift`; all 5 description boxes checked
    - test: green — `swift test` 333 passed, 0 failed; 1 env-gated skip permitted by `test-integrity`; no source warning
    - commit: 85a5d72
    - review: clean — `review sha HEAD~1..HEAD`, 0 findings, 7 validators attempted, 0 failed
    - new work filed: `^tb86z9q` (gated `HotReloadLiveTests` fails on a clean tree too)
  timestamp: 2026-08-26T12:58:37.292063+00:00
- actor: claude-code
  id: 01m0z2e063zzrdyjaynmxvq1rp
  text: |-
    ### commit — amended
    - The kanban state this card wrote after 85a5d72 (the moves to `review` and `done`, the step comments) was folded into the same commit with `git commit --amend --no-edit`, as the `commit` skill instructs for `.kanban/` changes that appear after a commit. The commit is now 7463cf4 with the same subject. No push.
  timestamp: 2026-08-26T12:58:58.627836+00:00
position_column: done
position_ordinal: a880
title: 'SkillWatcher: cancel overwritten sources, disclose busy-ancestor cost'
---
## What
The late-root arming fix (76c1528) works but introduced a latent defect and left two gaps:

1. **Un-cancelled source overwrite / descriptor leak**: `watchEntry` overwrites `watchedSources[url.path]` without cancelling the prior source (`Registry/SkillWatcher.swift:233`). Newly reachable via ancestor arming when roots are ordered `[<missing child of A>, A]`: the ancestor watch on `A` is installed first, then `watchTree(at: A)` replaces it — the old DispatchSource is released un-cancelled, its cancel handler (which closes the descriptor, `:230-232`) never runs. Fix: cancel any existing source for the path before storing a replacement.
2. **Busy-ancestor rebuild storms undisclosed**: the nearest existing ancestor of a missing root can be a busy directory (e.g. `~` when `~/.skills` is absent); unrelated activity there triggers a full catalog rebuild every debounce window. Disclose this in the type's doc comment (`SkillWatcher.swift:14-19`) and, if cheap, filter ancestor events to ones that could create the awaited path component before flushing.
3. **Coverage gap**: no test asserts an EDIT to a file under a late-created root fires after the watch escalates from ancestor to recursive tree — the delete-recreate case's signal can be attributed to the ancestor watch alone. Add: create root late → await escalation → edit an existing file under it → exactly one coalesced callback.

## Acceptance Criteria
- [x] Roots `[missing-child-of-A, A]` produce no leaked descriptor (source for A cancelled before replacement; assert via cancel-handler side effect or descriptor counting)
- [x] Post-escalation edit fires a callback (new test)
- [x] Busy-ancestor cost documented (and filtered if implemented)

## Tests
- [x] Extend `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift` — overwrite-cancellation case; post-escalation edit case
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.