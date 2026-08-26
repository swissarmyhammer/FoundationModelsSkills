---
assignees:
- claude-code
position_column: todo
position_ordinal: '8980'
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