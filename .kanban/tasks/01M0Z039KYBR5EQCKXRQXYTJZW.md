---
assignees:
- claude-code
position_column: todo
position_ordinal: 8c80
title: 'Add test for SkillsRegistry.validate: the unreadable SKILL.md diagnostic'
---
`Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`

Coverage: 97.6% (279/286 lines)

Uncovered lines: 489-495

Add this test. Do not change `SkillsRegistry.swift`.

Lines 489-495 are the `catch` branch of
`validate(discovered:diagnostics:)`. The branch runs when
`String(contentsOf:encoding:)` fails on a SKILL.md that discovery already
found. It appends a `.skip` diagnostic and gives back `nil`, so the
skill drops out of the catalog instead of the load failing.

Write the test like this:

1. Build a skill directory that holds a SKILL.md file discovery accepts.
2. Make that SKILL.md unreadable. Set its mode to `0o000` with
   `FileManager`. A directory named `SKILL.md` also works, and does not
   depend on the file mode.
3. Load the registry.
4. Make sure the skill id is not in `metadata()`.
5. Make sure the diagnostics hold one entry whose severity is `.skip`,
   whose `skillID` is the dropped skill's id, and whose message starts
   with "SKILL.md could not be read:".
6. Make sure the registry loads without an error, and that a second,
   healthy skill in the same root is still in the catalog. This proves
   one bad skill does not stop the load.

If the test runs as root, a `0o000` file mode can still be readable. In
that condition, use the directory-named-SKILL.md form.

Put the test in `Tests/FoundationModelsSkillsTests/`, next to the
registry tests that are there. #coverage-gap