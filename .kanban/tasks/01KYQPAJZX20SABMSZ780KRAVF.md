---
position_column: todo
position_ordinal: 9a80
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