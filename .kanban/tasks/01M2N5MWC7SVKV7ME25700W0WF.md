---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2qvxvqyezc3j5pa4gg3zv8d
  text: |-
    Picked up the card and moved it to doing.

    Research: the duplicated pattern is `FixtureLibrary.packageRoot().appendingPathComponent(<relative path>)` plus `String(contentsOf:encoding:.utf8)`. It was in four places, all in the test target:
    - `MarketplaceDocsTests.text(ofDocument:)`
    - `DependencyGraphTests.planText()`
    - `DependencyGraphTests.readmeUsageBlock(under:)`
    - `DependencyGraphTests.compiledUsageBlockCopy(under:)`

    `FixtureLibrary` already had `url(relativePath:thisFile:)`, which resolves against the fixture-library root and refuses `..`, `/` and `~`. The new reader must resolve against the package root instead, thus the two resolutions now share one private `resolve(relativePath:under:)` and the path rule can never differ between them.

    `DependencyGraphTests.resolvedIdentities()` keeps its own read, because it reads `Data` for a JSON decode and not UTF-8 text.

    TDD: two new cases in `FixtureLibraryTests` came first and failed to compile with "type 'FixtureLibrary' has no member 'readText'". One case reads `Package.swift`, the other proves that the path is taken from the package root, and not from `Examples/skill-library`.
  timestamp: 2026-09-17T14:22:00.958314+00:00
- actor: claude-code
  id: 01m2qw1gzdmbtc5s5g7pr9vedh
  text: |-
    Implementation landed.

    `FixtureLibrary` now holds `readText(relativePath:thisFile:)`, which resolves against the package root and reads UTF-8 text. It shares a new private `resolve(relativePath:under:)` with `url(relativePath:thisFile:)`, thus the "no `..`, no `/` or `~` prefix" rule is written one time and both resolutions obey it.

    Six read sites now call it, and every private copy is gone:
    - `MarketplaceDocsTests.text(ofDocument:)` -- deleted; the suite calls `readText` directly. The suite no longer needs `import Foundation`, thus that import is gone too.
    - `DependencyGraphTests.planText()` -- deleted; the two callers call `readText`.
    - `DependencyGraphTests.readmeUsageBlock(under:)` and `compiledUsageBlockCopy(under:)` -- each lost its `root` parameter, because `readText` finds the package root itself.
    - `CIWorkflowTests.workflowLines()` -- reads through `readText`.
    - `SkillsRegistryTests.registrySourceNamesNoDotfolderConventionLiteral()` -- reads through `readText`.

    The last two were not named on the card, but they hold the same cause: `packageRoot()` plus `appendingPathComponent` plus `String(contentsOf:)`. The card asks for one file-reading helper in the test target, thus they had to go as well.

    Left as they are:
    - `DependencyGraphTests.resolvedIdentities()` reads `Data` for a JSON decode, not text.
    - The suites that read a fixture through `FixtureLibrary.url(relativePath:)` resolve against the fixture-library root, which is a different base and a different reader.

    Verification: `swift build --build-tests` gives zero warnings and zero errors. `swift test` gives "Test run with 702 tests in 54 suites passed". The count is 702 and not 700 because of the two new cases of `FixtureLibraryTests`.
  timestamp: 2026-09-17T14:24:01.005472+00:00
- actor: claude-code
  id: 01m2qw1mfqnra16v9y48rhtk7r
  text: |-
    ### implement -- changed
    - evidence: 6 files -- Tests/FoundationModelsSkillsTests/FixtureLibrary.swift, FixtureLibraryTests.swift, MarketplaceDocsTests.swift, DependencyGraphTests.swift, CIWorkflowTests.swift, SkillsRegistryTests.swift. `swift build --build-tests`: 0 warnings, 0 errors. `swift test`: 702 tests in 54 suites passed.
    - next: /review
  timestamp: 2026-09-17T14:24:04.599003+00:00
- actor: claude-code
  id: 01m2qw4wq3np5ark8vckna2wez
  text: |-
    ### test — green
    - evidence: `swift test`, run twice — 702 tests, 54 suites, 0 failures, 0 warnings, 0 errors, 0 skipped, both runs
    - run 1 log: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer-FoundationModelsSkills/b9d0155a-2dfe-4435-b619-18918c20ca30/scratchpad/test_run1.log
    - run 2 log: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer-FoundationModelsSkills/b9d0155a-2dfe-4435-b619-18918c20ca30/scratchpad/test_run2.log
    - next: hand off to review
  timestamp: 2026-09-17T14:25:51.331366+00:00
- actor: claude-code
  id: 01m2qwajgab44b3t3ctq32vh7s
  text: |
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 441ba4d) — 0 findings, 0 confirmed, 0 refuted; 7 validators attempted, 0 failed; 6 files reviewed
    - next: task moved to `done`; all prior checklist items are checked
  timestamp: 2026-09-17T14:28:57.482855+00:00
- actor: claude-code
  id: 01m2qwavyy0cz87zzvsamb5cw0
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 6 files: FixtureLibrary, FixtureLibraryTests, MarketplaceDocsTests, DependencyGraphTests, CIWorkflowTests, SkillsRegistryTests
    - test: green — swift test x2, each 702 tests in 54 suites, 0 failed, 0 warnings
    - commit: 441ba4d refactor(tests): use one file-read method in FixtureLibrary
    - review: clean — 0 findings, 7 validators, 6 files
    - result: the card is in done. The implementer found two more sites of the same cause (CIWorkflowTests, SkillsRegistryTests) and removed those also.
  timestamp: 2026-09-17T14:29:07.166342+00:00
position_column: done
position_ordinal: e780
title: MarketplaceDocsTests duplicates the fixture file-reading helper
---
## What

A review of commit `7876a31` reported this, but the finding arrived on the wrong card (it came out of a review run that targeted the wrong repository). It is recorded here so that it is not lost.

`Tests/FoundationModelsSkillsTests/MarketplaceDocsTests.swift:94` holds a file-reading helper that repeats the pattern of `DependencyGraphTests.planText()`. Move one shared `readText(relativePath:)` into `FixtureLibrary`, and make both suites call it.

- [x] Add `readText(relativePath:)` to `FixtureLibrary`
- [x] Make `MarketplaceDocsTests` and `DependencyGraphTests` call it
- [x] Delete both copies

## Acceptance Criteria
- [x] Only one file-reading helper is present in the test target
- [x] `swift test` stays green with zero warnings

## Tests
- [x] The tests that already exist in both suites keep their results; no new test is necessary
- [x] Run `swift test`; expect green

## Workflow
- Use `/tdd` -- write failing tests first, then implement to make them pass. #marketplace