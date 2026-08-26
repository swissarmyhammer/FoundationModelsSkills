---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0z83ssqn7xpexgy9dtjhdbp
  text: |-
    Research: `ScriptProcessRunner` is `internal`. `SkillWatcherTests` already reaches internal symbols with `@testable import FoundationModelsSkills`, so the test target can call the runner directly. The `posix_spawn` call fails with ENOENT when the shebang names an interpreter that does not exist, so the runner takes the `else` branch at lines 79-81 and gives back `failedToSpawn`.

    Implementation: `RunScriptTests.swift` now uses `@testable import FoundationModelsSkills`. New test `scriptProcessRunnerReportsFailedToSpawnWhenTheInterpreterDoesNotExist` writes an executable script with the shebang `#!/nonexistent/interpreter`, runs `ScriptProcessRunner.run` with a 1 second timeout (named constant `failedToSpawnTimeoutSeconds`) and a 1 minute test time limit, and checks status `.failed`, exit code `nil`, duration 0, lines 0, empty output. The helper `writeExecutableShebangScript` now returns the script URL (`@discardableResult`) so the direct test can reuse it. `ScriptProcessRunner.swift` is not changed.

    `swift test --filter RunScriptTests`: 16 tests passed.
  timestamp: 2026-08-26T14:38:15.863299+00:00
- actor: claude-code
  id: 01m0z847g2b506y29dasmh5h3t
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsSkillsTests/RunScriptTests.swift (new test `scriptProcessRunnerReportsFailedToSpawnWhenTheInterpreterDoesNotExist`, `@testable import`, `failedToSpawnTimeoutSeconds` constant, `writeExecutableShebangScript` returns the script URL). `swift test --filter RunScriptTests`: 16 tests passed.
    - next: test, commit, review
  timestamp: 2026-08-26T14:38:29.890247+00:00
- actor: claude-code
  id: 01m0z852c42fpwdz9zar0fvvyv
  text: |-
    ### test — green
    - evidence: `swift test` — 370 tests in 25 suites passed, 0 failed. One gated skip is the known `HotReloadLiveTests` case (^tb86z9q). No compiler warnings on project code.
    - next: commit
  timestamp: 2026-08-26T14:38:57.412853+00:00
position_column: doing
position_ordinal: '80'
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

- [x] The outcome status is the failed-to-spawn status, not `exited`.
- [x] The exit code is `nil`.
- [x] The call gives a result and does not hang. Set a short timeout so a
   hang fails the test fast.

Test the runner directly, if it is reachable from the test target.
Otherwise drive it through `RunScript.execute(in:)` with script
execution enabled and the script granted in `allowed-tools`.

Line 186 -- `return (nil, true)` after the SIGKILL -- is a defensive
branch. The wait task always gives `.exited` after the process group
dies. Leave it uncovered.

Put the test in `Tests/FoundationModelsSkillsTests/`, next to the
`RunScriptTests` suite. #coverage-gap