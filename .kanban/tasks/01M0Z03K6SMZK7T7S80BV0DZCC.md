---
assignees:
- claude-code
position_column: todo
position_ordinal: 8d80
title: 'Add test for ScriptProcessRunner: the failed-to-spawn branch'
---
`Sources/FoundationModelsSkills/Resources/ScriptProcessRunner.swift`

Coverage: 96.5% (109/113 lines)

Uncovered lines: 79-81

Add this test. Do not change `ScriptProcessRunner.swift`.

Lines 79-81 are the `else` branch of the `guard` on `Self.spawn(...)` in
`run(executableURL:arguments:workingDirectory:timeout:)`. The branch runs
when the spawn fails. It closes both ends of the pipe and gives back
`Self.failedToSpawn`.

`RunScript` gates on the executable bit and on a shebang line before it
calls the runner, so the script file must pass both gates and still fail
to exec. Write a script that gives a shebang for an interpreter that
does not exist, for example `#!/nonexistent/interpreter`. Set the
executable bit. Run it.

Make sure of these results:

1. The outcome status is the failed-to-spawn status, not `exited`.
2. The exit code is `nil`.
3. The call gives a result and does not hang. Set a short timeout so a
   hang fails the test fast.

Test the runner directly, if it is reachable from the test target.
Otherwise drive it through `RunScript.execute(in:)` with script
execution enabled and the script granted in `allowed-tools`.

Line 186 -- `return (nil, true)` after the SIGKILL -- is a defensive
branch. The wait task always gives `.exited` after the process group
dies. Leave it uncovered.

Put the test in `Tests/FoundationModelsSkillsTests/`, next to the
`RunScriptTests` suite. #coverage-gap