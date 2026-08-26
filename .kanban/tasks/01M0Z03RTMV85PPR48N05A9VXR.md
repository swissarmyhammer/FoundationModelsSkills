---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0z8gdgdcd71pgtn5254w4tc
  text: |-
    Research: The card line numbers are from before ^0drrr83. The function `nearestExistingAncestor(of:)` is now `ancestorArming(for:)`. Its `while` body is at lines 234-237. The `else` branch of `directoryContents(of:)` is at line 414. The suite already has the helpers `withTempDirectory`, `withWatcher(over:)`, `expectExactlyOneSignal`, and `writeSkillFile`. I used them. `SkillsRegistryTests` has a private `isRoot` and a mode-0o000 fixture pattern. I made the same small helpers in `SkillWatcherTests`.

    Implementation: Two tests added to `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift`.
    - `rootNestedSeveralLevelsBelowItsNearestExistingAncestorIsArmedThere`: root is `<tmp>/a/b/c/skills`, only `<tmp>` exists. A skill write fires one signal, and an edit after the escalation fires one more.
    - `unreadableDirectoryInsideARootIsSkippedAndReadableSiblingsStillReport`: a mode-0o000 directory inside the root. The watcher starts and a readable skill write fires one signal. The test is disabled with `.disabled(if: isRoot, ...)` when the process is root. The defer restores mode 0o700 so the temp directory can be removed.

    Evidence: `swift test --filter SkillWatcherTests` passed 17 tests. `llvm-cov show` on the suite shows lines 234-237 run 3 times and line 414 runs 2 times.
  timestamp: 2026-08-26T14:45:09.261630+00:00
- actor: claude-code
  id: 01m0z8gesa5xcy2q4hq2cdcj5f
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift (2 tests, 4 helpers); `swift test --filter SkillWatcherTests` 17 passed
    - next: test
  timestamp: 2026-08-26T14:45:10.570221+00:00
- actor: claude-code
  id: 01m0z8j27ypdr5tbqs8pgzpvfe
  text: |-
    ### test — green
    - evidence: `swift test` — 372 passed, 0 failed in 25 suites; 1 skip is the gated live-model test (^tb86z9q, known); no source warnings
    - next: commit
  timestamp: 2026-08-26T14:46:03.262130+00:00
position_column: doing
position_ordinal: '80'
title: 'Add tests for SkillWatcher: deep ancestor walk and unreadable directory'
---
`Sources/FoundationModelsSkills/Registry/SkillWatcher.swift`

Coverage: 96.7% (118/122 lines)

Uncovered lines: 186-188, 303 (line numbers from before ^0drrr83; now the `while` body of `ancestorArming(for:)`, lines 234-237, and the `else` branch of `directoryContents(of:)`, line 414)

Add these tests. Do not change `SkillWatcher.swift`.

- [x] 1. Lines 186-188 -- the loop body of `nearestExistingAncestor(of:)`.
   The existing tests give a root whose direct parent already exists, so
   the `while` loop never runs a second time. Give a root that is nested
   two or more levels below the nearest directory that exists, for
   example `<tmp>/a/b/c/skills` where only `<tmp>` exists. The watcher
   must walk up to `<tmp>`. Then make the full path and write a skill
   into it. Make sure the watcher reports the new skill. This proves the
   walk found the correct ancestor.

- [x] 2. Line 303 -- the `else` branch of `directoryContents(of:)`.
   The branch gives an empty array when `contentsOfDirectory` fails. Put
   a directory the process cannot read inside a watched root. Set its
   mode to `0o000` with `FileManager`. Make sure the watcher starts, does
   not throw, and still reports changes to the readable skills in the
   same root.
   If the test runs as root, the read can succeed. In that condition,
   skip the test.

Put the tests in `Tests/FoundationModelsSkillsTests/`, next to the
`SkillWatcherTests` suite. #coverage-gap