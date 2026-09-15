---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2kgj9p40bggjgy062cv5efv
  text: |-
    ### test — green

    Finding: The test `durationMs < 2000` was a fixed time limit. A fixed time limit is not allowed. The test result must not depend on the speed of the host.

    Fix, file Tests/FoundationModelsSkillsTests/RunScriptTests.swift:

    - `durationMsReportsTheSubSecondRemainderNotJustWholeSeconds` — I removed the two bound checks (`>= 200` and `< 2000`). I added one check: `result.durationMs % 1000 != 0`. This check proves the remainder is in the reported value. A whole-seconds-only bug would report an exact multiple of 1000 (0, for a 0.3 second sleep). A correct value is almost never an exact multiple of 1000. This check does not depend on host speed.
    - `goldenRunScriptResultAgainstTheReleaseNotesFixture` — I removed the `< 2000` check. I kept `result.durationMs >= 0` only. This proves the shape of the result (a real, not-negative duration) with no time limit.

    I did not raise the number 2000. I did not skip, disable, or serialize either test.

    Evidence: `swift build --build-tests` — build complete, no warnings. `swift test` run three times — each run: 658 tests, 50 suites, all passed, 0 failures, 0 skipped.
  timestamp: 2026-09-15T21:46:29.956991+00:00
position_column: done
position_ordinal: d980
title: 'RunScriptTests: the durationMs budget of 2000 ms fails under a loaded parallel run'
---
## What

`Tests/FoundationModelsSkillsTests/RunScriptTests.swift` asserts `result.durationMs < 2000` in two tests:

- `goldenRunScriptResultAgainstTheReleaseNotesFixture` (line 313)
- `durationMsReportsTheSubSecondRemainderNotJustWholeSeconds` (line 346)

Both pass when the suite runs alone (`swift test --filter RunScriptTests`). Both fail in a full `swift test` on a loaded computer, because the measured wall time of a spawned script grows with the load of the host. The failure has no relation to the code under test.

The number 2000 is a built-in time limit, which the project rules forbid.

## Acceptance Criteria
- [ ] No test asserts a wall-time limit that the load of the host can break
- [ ] The two tests still prove what they must prove: `durationMs` is present, and it reports the sub-second remainder and not only whole seconds
- [ ] `swift test` gives zero failures in a full parallel run

## Tests
- [ ] Run `swift test --filter RunScriptTests`, then a full `swift test`; all green #testing #marketplace