---
depends_on:
- 01KYNCQK5WG7HZTYB9R5YS0SYX
position_column: todo
position_ordinal: '8780'
title: File watcher over every stack layer root
---
## What
The M2 watcher (plan §7, decision #29 as amended): Extras' machinery locates, it never watches — we watch **every host-supplied layer root** and trigger rebuild.

- `Sources/FoundationModelsSkills/Registry/SkillWatcher.swift` — DispatchSource/FSEvents-based watcher over each existing root in the ordered root list the host supplied (whatever those roots are — the watcher names no convention). Fires a coalesced "changed" signal on add/remove/edit anywhere under a root (recursive — `SKILL.md` bodies and `_partials/` both count). Debounce bursts (e.g. 100–250 ms) so an editor save producing multiple events yields one rebuild. Nonexistent roots are skipped without error; a root appearing later is handled only if cheap, otherwise document the limitation.
- Lifecycle: start/stop; no retained callbacks after stop; safe teardown in deinit.
- No registry logic here — the watcher only reports "something changed"; the registry reload task owns rebuild.

## Acceptance Criteria
- [ ] Creating, editing, and deleting a `SKILL.md` under a watched temp root each produce exactly one coalesced callback within the debounce window
- [ ] Events under an ignored dir (`.git/`) still coalesce safely (no crash; rebuild is cheap and discovery re-filters)
- [ ] A nonexistent root in the list is skipped without error
- [ ] Stop prevents further callbacks

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift` — temp-directory add/edit/remove with expectation-based waits; burst-coalescing case; nonexistent-root case; stop case
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.