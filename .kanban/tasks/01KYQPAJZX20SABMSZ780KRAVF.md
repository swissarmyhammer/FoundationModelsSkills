---
comments:
- actor: claude-code
  id: 01kyr4vtbqs5gykzy7vt9sevbg
  text: |-
    Implemented and checkpointed at 76c1528:
    - `SkillWatcher.watchExistingRoots()` renamed to `armRoots()`: an existing root still gets the real recursive watch; a missing root now watches its nearest existing ancestor directory instead of being skipped outright. `flush()`'s existing rebuild-from-scratch cycle re-resolves each root's existence every quiet period, so the ancestor watch escalates to the real recursive one the moment the root actually appears — no watcher restart needed. Delete-then-recreate flows through the same mechanism (the delete itself triggers a flush whose rebuild falls back to re-arming the ancestor).
    - Added `nearestExistingAncestor(of:)`, walking `deletingLastPathComponent()` up until something exists on disk.
    - Found and fixed a real flakiness landmine along the way: the existing `nonexistentRootInTheListIsSkippedWithoutError` test placed its bogus root directly under the shared system temp directory — with the new ancestor-arming, that meant watching `$TMPDIR` itself, which sees constant unrelated churn from every other test's own `makeTempDirectory()` calls. Moved the bogus root under a private per-test directory instead.
    - New tests: `creatingARootThatDidNotExistAtStartIsDetected`, `deletingAndRecreatingARootKeepsEventsFlowing` (`SkillWatcherTests`), and an end-to-end `aRootThatDidNotExistAtConstructionSurfacesItsSkillOnceCreated` (`SkillsRegistryReloadTests`).
    - Full suite green: 280/280, confirmed clean across 3 consecutive runs (one earlier run hit an unrelated one-off flake, not reproduced).
    - Scoped review running in background (task kj2ug29j6) — awaiting result.
  timestamp: 2026-07-29T23:55:23.895582+00:00
- actor: claude-code
  id: 01kyr5yp096a5d3fg6efbrhvnq
  text: 'Review clean at 8c95c70 (0 findings). Two prior review-finding fixes landed: directoryEventMask constant deduped across watchTree(at:)/armRoots() (76c1528 → follow-up), and WatcherTestSupport.swift extracted to dedupe makeTempDirectory() between SkillWatcherTests and SkillsRegistryReloadTests. Full suite green 280/280. Moving to done.'
  timestamp: 2026-07-30T00:14:26.313017+00:00
position_column: done
position_ordinal: 9b80
title: 'Watcher: arm layer roots created after start()'
---
## What
Variance from §7 ("file watcher over every stack layer root … fires on add/remove/edit up the stack"): `SkillWatcher` only arms roots that exist at `start()` (`Registry/SkillWatcher.swift:147-151`); re-arming happens only inside `flush()` (`:233-240`), i.e. only after some OTHER already-watched root fires. A host passing a not-yet-existing project root (the common `.skills` case) gets no reload when that root is first created and populated.

Fix: for each nonexistent root, watch its nearest existing ancestor directory (kqueue on the parent) and re-arm when the root appears; or poll nonexistent roots on a coarse timer folded into the debounce machinery. Update the documented limitation (`SkillWatcher.swift:14-16`) to match the new behavior.

## Acceptance Criteria
- [ ] Start the watcher with a root that does not exist; create the root and a `name/SKILL.md` under it → exactly one coalesced callback fires and the registry reload surfaces the new skill
- [ ] Deleting and re-creating a root keeps events flowing
- [ ] Existing coalescing/stop semantics unchanged (current tests stay green)

## Tests
- [ ] Extend `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift` — late-root-creation case; delete-recreate case
- [ ] Extend `SkillsRegistryReloadTests` — end-to-end late root through the registry
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.