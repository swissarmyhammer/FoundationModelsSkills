---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2xnbyxddd7ke577caw9pf9z
  text: |
    Research: `StandardStream` (Sources/FoundationModelsSkills/CLI/StandardStream.swift) is the one line writer. `WatchMode` and `SkillsDemoMain` call it. `ChatMode` held the last four `print(...)` calls of the repository -- a grep of every Swift file found no other one; the only other hit is a doc comment in `MarketplaceCredential.swift` that names `dump(_:)`, which is text, not code.

    `Tests/.../NoGitProcessTests.swift` gives the pattern for a guard of this shape: it reads every Swift file under `Sources/` and reports each line that breaks a rule. The new suite follows it.

    The `no_direct_standard_out_logs` rule reads an identifier, thus a comment and a string literal never report. The new guard passes over a comment line for the same reason.
  timestamp: 2026-09-19T20:22:49.517547+00:00
- actor: claude-code
  id: 01m2xnc63y51pzv3dzj2v6gdnr
  text: |
    Work: the new guard suite `NoStandardOutWriteTests` came first, and it failed with the four ChatMode lines (103, 123, 140, 142). Then `ChatMode` moved to `StandardStream.output.write(line:)` for each one, with the same text. `printUnavailable(reasonText:)` is now `writeUnavailable(reasonText:)`, because the name said what the body no longer does. The `"none"` text of a turn with no tool call is now the named constant `noCallText`, which also keeps the write line short.

    The end-to-end case `SkillsDemoTests.chatModeDegradesCleanlyWhenForcedUnavailable` still passes, thus the unavailable line reaches standard output with the same text.

    ### implement — changed
    - evidence: 2 files -- Examples/skills-demo/ChatMode.swift, Tests/FoundationModelsSkillsTests/NoStandardOutWriteTests.swift (new). `swift build --build-tests`: 0 warnings, 0 errors. `swift test`: 767 tests in 60 suites, 0 failures.
    - next: /review
  timestamp: 2026-09-19T20:22:56.894850+00:00
- actor: claude-code
  id: 01m2xnhy27jh91kfy5mzv5e3x0
  text: |-
    ### test — green
    - command: `swift build --build-tests` — build complete, 0 warnings.
    - command: `swift test` — 767 tests in 60 suites, all passed, 0 failed, 0 skipped.
    - The new suite "No standard out write" passed. It reads each Swift file under `Sources/` and `Examples/skills-demo/` and reports a call to `print`, `debugPrint`, `dump`, or `_printChanges`. It found none.
    - No test is skipped or ignored. No warning is present in the build log.
    - next: send the task to review.
  timestamp: 2026-09-19T20:26:05.255393+00:00
position_column: doing
position_ordinal: '80'
title: The demo chat mode writes to standard out with print
---
## What

`Examples/skills-demo/ChatMode.swift` writes four lines with `print(...)`:

- `printUnavailable(reasonText:)` — the "Foundation Models unavailable" line.
- The `catch` of the live validation — "Live validation failed: ...".
- The `[OK]`/`[MISS]` line of each scripted turn.
- The `[ERROR]` line of a scripted turn that throws.

The rule `code-hygiene/disallowed-constructs-swift` -- `no_direct_standard_out_logs` -- forbids `print(…)`, `debugPrint(…)`, `dump(…)` and `_printChanges()` in code that is committed. The review of card ^977h3a0 named the same cause in `WatchMode.swift`, and that file now writes through `FileHandle.standardOutput`, the way `SkillsDemoMain` writes the output of a mode. `ChatMode.swift` was not in the scope of that finding, thus it still holds `print`.

## Acceptance Criteria

- [x] `Examples/skills-demo/ChatMode.swift` holds no `print(…)`, `debugPrint(…)`, `dump(…)` or `_printChanges()`.
- [x] Each line it wrote before goes to standard output with the same text.
- [x] `WatchMode`, `ChatMode` and `SkillsDemoMain` share one writer instead of three copies, or the duplication is shown to be none.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

#skills #code-hygiene
