---
assignees:
- claude-code
position_column: todo
position_ordinal: '8e80'
title: 'Add tests for SkillWatcher: deep ancestor walk and unreadable directory'
---
`Sources/FoundationModelsSkills/Registry/SkillWatcher.swift`

Coverage: 96.7% (118/122 lines)

Uncovered lines: 186-188, 303

Add these tests. Do not change `SkillWatcher.swift`.

1. Lines 186-188 -- the loop body of `nearestExistingAncestor(of:)`.
   The existing tests give a root whose direct parent already exists, so
   the `while` loop never runs a second time. Give a root that is nested
   two or more levels below the nearest directory that exists, for
   example `<tmp>/a/b/c/skills` where only `<tmp>` exists. The watcher
   must walk up to `<tmp>`. Then make the full path and write a skill
   into it. Make sure the watcher reports the new skill. This proves the
   walk found the correct ancestor.

2. Line 303 -- the `else` branch of `directoryContents(of:)`.
   The branch gives an empty array when `contentsOfDirectory` fails. Put
   a directory the process cannot read inside a watched root. Set its
   mode to `0o000` with `FileManager`. Make sure the watcher starts, does
   not throw, and still reports changes to the readable skills in the
   same root.
   If the test runs as root, the read can succeed. In that condition,
   skip the test.

Put the tests in `Tests/FoundationModelsSkillsTests/`, next to the
`SkillWatcherTests` suite. #coverage-gap