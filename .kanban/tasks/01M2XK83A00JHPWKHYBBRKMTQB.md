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
- actor: claude-code
  id: 01m2xnvp6yj5gmt73xnt98dd9e
  text: |
    ### review — findings
    - evidence: 1 finding (1 confirmed, 0 refuted) — Tests/FoundationModelsSkillsTests/NoStandardOutWriteTests.swift:87; scope `review sha HEAD~1..HEAD`
    - next: remove the duplicated line-filter helper, then review again
  timestamp: 2026-09-19T20:31:24.894871+00:00
- actor: wballard
  id: 01m2xnwgckef03dx1sdk7prv1w
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 2 files, 1 new
    - test: green — swift test, 767 passed, 0 warnings
    - commit: 8a7a5c0
    - review: findings — Tests/FoundationModelsSkillsTests/NoStandardOutWriteTests.swift:87
  timestamp: 2026-09-19T20:31:51.699528+00:00
- actor: claude-code
  id: 01m2xp6zp5afty51am19x8gk86
  text: |
    Research for the review finding.

    `NoStandardOutWriteTests.disallowedCallLines(in:)` and `NoGitProcessTests.processLinesNamingGit(in:)` hold the same three steps: split the text into lines, keep the lines a test accepts, and give the number of each kept line. The two directory walks under them hold the same steps as well -- read each Swift file of a directory, and write `<directory>/<path>:<line>` for each reported line. Thus the cause is one copied reader, not one copied filter, and the fix removes both copies.

    The test target has no general support file. `FixtureLibrary` resolves paths, `SkillLineReader` reads the answer of a skill operation. The convention is one named `enum` in its own file, so the new reader is `SwiftSourceScan`. `SkillLineReader` has no suite of its own, but `FixtureLibrary` has `FixtureLibraryTests`, thus a suite for the new reader follows the convention.

    Rules read before the edit (`dump validators` over the test file): `reuse` asks for one shared function with the difference as a parameter; `duplication` calls a confirmed copy a blocker; Swift `immutability` says a function belongs to a type, thus the helper is a `static func` on an `enum` and not a top-level `func`; `magic-numbers-swift` allows 0, 1, -1 and 100 inline; `optionals` forbids `guard` in a test body.
  timestamp: 2026-09-19T20:37:35.045194+00:00
- actor: claude-code
  id: 01m2xpdx2dgn2g5g29b877gpe6
  text: |
    Work on the review finding.

    The new file `Tests/FoundationModelsSkillsTests/SwiftSourceScan.swift` holds the reader the two guards share. It gives two operations: `lineNumbers(in:matching:)`, which is the function the finding asks for, and `reportedLines(inDirectory:matching:)`, which walks the Swift files of a directory and writes `<directory>/<path>:<line>` for each reported line. The walk went in as well because the two guards held a copy of it too, and the finding says to remove the cause and not only the line it names. A walk that finds no Swift file now throws `ScanError.noSwiftFile`, which replaces the `#expect(!files.isEmpty, ...)` line each guard kept.

    Each guard now holds only what is its own: the text it looks for, and one function that tells whether a line breaks its rule. `NoStandardOutWriteTests` gives `writesToAStandardStream(_:)`, and `NoGitProcessTests` gives `startsAGitProcess(_:)`. `NoGitProcessTests` no longer imports Foundation, because it opens no file now.

    The case `theReportedLineNumberCountsFromOne` stood in both guards. It now stands one time, in the new suite `SwiftSourceScanTests`, beside three more cases: a text with no reported line, the form of a reported line, and the walk that finds no Swift file. Thus the count of tests goes from 767 to 769: four new cases, two removed copies.

    TDD: `SwiftSourceScanTests` came first and the build failed with `cannot find 'SwiftSourceScan' in scope`. `SwiftSourceScan` then made the four cases pass. The two guards moved onto it after that, and the whole suite stayed green.
  timestamp: 2026-09-19T20:41:21.741529+00:00
- actor: claude-code
  id: 01m2xpe24akm113fgpdb5dawxp
  text: |
    ### implement — changed
    - evidence: 4 files -- Tests/FoundationModelsSkillsTests/SwiftSourceScan.swift (new), Tests/FoundationModelsSkillsTests/SwiftSourceScanTests.swift (new), Tests/FoundationModelsSkillsTests/NoStandardOutWriteTests.swift, Tests/FoundationModelsSkillsTests/NoGitProcessTests.swift. `swift build --build-tests`: build complete, 0 warnings, 0 errors. `swift test`: 769 tests in 61 suites, 0 failed, 0 skipped.
    - next: /review
  timestamp: 2026-09-19T20:41:26.922426+00:00
- actor: claude-code
  id: 01m2xpjhc4v5tpw3pcbzszrr2p
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` gives 0 warnings and exit code 0. `swift test` gives 769 tests in 61 suites, all pass, 0 fail, 0 skip.
    - The suite `NoStandardOutWriteTests` and the suite `NoGitProcessTests` pass. Each one now calls the shared reader `SwiftSourceScan`. This reader has its own test suite, `SwiftSourceScanTests`, and it also passes.
    - The build has no `print`, `debugPrint`, `dump`, or `_printChanges` call in `Sources/` or in `Examples/skills-demo`.
    - next: send to review.
  timestamp: 2026-09-19T20:43:53.604363+00:00
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

## Review Findings (2026-09-19 15:27)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsSkillsTests/NoStandardOutWriteTests.swift:87` `reuse/reuse` — The `disallowedCallLines` function reimplements the line-filtering pattern that already exists as `processLinesNamingGit` in NoGitProcessTests.swift. Both take text, split into lines, filter based on conditions, and return line numbers. A shared parameterized function should be extracted instead of duplicating the logic. Extract a shared helper function like `func lineNumbers(in text: String, matching predicate: (String) -> Bool) -> [Int]` in a common test utilities module, or generalize one of the existing functions to accept a predicate parameter.
