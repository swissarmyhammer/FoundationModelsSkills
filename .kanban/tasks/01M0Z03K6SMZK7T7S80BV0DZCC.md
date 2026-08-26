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
- actor: claude-code
  id: 01m0z85gazppp9rkwn83wn2v4k
  text: |-
    ### commit — changed
    - evidence: 360d2c1 test(run-script): cover ScriptProcessRunner's failed-to-spawn branch (^bv0dzcc)
    - next: review HEAD~1..HEAD
  timestamp: 2026-08-26T14:39:11.711409+00:00
- actor: claude-code
  id: 01m0z87shmgjnf7p9cms2jactn
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings (7 validators attempted, 0 confirmed, 0 refuted); 1 file reviewed, `.kanban/` excluded by `.reviewignore`
    - next: task moved to done
  timestamp: 2026-08-26T14:40:26.676491+00:00
- actor: claude-code
  id: 01m0z885f02308t55w5613313a
  text: |-
    ### finish iteration 1 — review clean, task moved to done
    - implement: changed — Tests/FoundationModelsSkillsTests/RunScriptTests.swift (new failed-to-spawn test, `@testable import`, `failedToSpawnTimeoutSeconds`, helper returns the script URL)
    - test: green — `swift test` 370 passed, 0 failed, 1 known gated skip (^tb86z9q)
    - commit: 360d2c1
    - review: clean — `review sha HEAD~1..HEAD`, 0 findings
  timestamp: 2026-08-26T14:40:38.880263+00:00
position_column: done
position_ordinal: b280
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