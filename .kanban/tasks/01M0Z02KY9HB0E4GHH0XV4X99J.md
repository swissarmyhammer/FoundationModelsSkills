---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0z5pd2kj0ee3dbpc2h0c3j4
  text: |-
    Research and implementation notes:
    - `SkillsRegistry` is a struct with no public reload function and no protocol, so a test double is not possible without a change to `UseSkill.swift`.
    - `UseSkill.execute(in:)` calls `context.visibilityPredicate` one time between the `metadata()` snapshot (line 122) and `registry.call(id:arguments:)` (line 136). This is the injected hook.
    - The predicate deletes the skill directory, then waits until the `watch: true` registry drops the id from the live catalog (poll, 10 s limit). It always gives `true`. The watcher rebuild runs on a GCD queue, so the block in the predicate does not stop it.
    - The predicate runs a second time inside `unusableIDMessage`. That call returns at once because the directory is gone and the catalog is already rebuilt. The message lists `widget` as usable because it is built from the pre-race snapshot.
    - Refactor: `makeTempContext` now uses a new `writeWidgetSkill` helper (returns the temp root) and `FixtureLibrary.makeSkillsToolContext`. The new test uses `writeWidgetSkill` directly.
    - The new test passes in 0.26 s. The reload lands in about 200 ms (the watcher debounce).
  timestamp: 2026-08-26T13:55:59.699595+00:00
- actor: claude-code
  id: 01m0z5peq05ykynbw8hykk9x64
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsSkillsTests/SkillOperationsTests.swift (new test `useSkillWhoseIDVanishesBetweenTheLookupAndTheCallReturnsTheUnusableIDCorrective`, helper `makeCatalogRemovalPredicate`, helper `writeWidgetSkill`); `swift test --filter SkillOperationsTests` = 43 tests passed
    - next: test
  timestamp: 2026-08-26T13:56:01.376574+00:00
- actor: claude-code
  id: 01m0z5q9whwqz9f101nem99rk3
  text: |-
    ### test — green
    - evidence: `swift test` — 361 tests in 24 suites passed, 0 failed; the one skip is the gated `HotReloadLiveTests` (known, ^tb86z9q); the only warning is the SwiftPM build-system note about the mlx bundle, not a source warning
    - next: commit
  timestamp: 2026-08-26T13:56:29.201151+00:00
position_column: doing
position_ordinal: '80'
title: 'Add test for UseSkill: the UnknownSkillError hot-reload race branch'
---
`Sources/FoundationModelsSkills/Operations/UseSkill.swift`

Coverage: 88.2% (45/51 lines)

Uncovered lines: 139-144

Add this test. Do not change `UseSkill.swift`.

Lines 139-144 are the `catch is UnknownSkillError` branch of
`execute(in:)`. The branch runs when the catalog changes between the
lookup at line 123 and the `registry.call(id:arguments:)` at line 136 --
a race with a hot reload. The branch gives back the same corrective
message as an id that was unusable at lookup time.

The test must make that race happen:

1. Build a registry that holds one skill.
2. Look up the skill and get a `SkillsToolContext`.
3. Delete the skill directory, then reload the registry, so the id goes
   away from the live catalog. Do this after `metadata()` gives its
   snapshot but before `call(id:arguments:)` runs. Use a test double for
   the registry, or an injected hook, if the timing is not possible
   another way.
4. Make sure `execute(in:)` gives `.corrective(_:)`, and that the message
   is the same one `unusableIDMessage(id:catalog:visibilityPredicate:)`
   builds.

Make sure the operation does not throw. A `UnknownSkillError` must not
reach the caller. Any other error must still propagate; the existing
tests already prove that.

Put the test in `Tests/FoundationModelsSkillsTests/`, next to the tests
that are there for this operation. #coverage-gap