---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2kx1c1skv608q7a2ypwvp8w
  text: |-
    Research, before the code.

    What the code already gives:
    - `MarketplaceCLI.run(arguments:context:)` gives back a `MarketplaceCLIResult` with the text and the exit code. It prints nothing itself, thus the demo prints the text.
    - `MarketplaceCLIContext(stack:environment:)` takes the configuration stack and the environment. `MarketplaceCLIContext.cacheDirectory` calls `MarketplaceCache.cacheDirectory(environment:)`, which reads `SKILLS_MARKETPLACE_CACHE`. Thus the demo needs no cache code of its own: it gives the context the environment of the process, which is the default.
    - `FixtureStack.make()` is the `skills` dotfolder stack over `Examples/skill-library`. Its user layer is `Examples/skill-library/user`.

    One thing the card did not say, and the acceptance criterion needs: the fixture library held no `marketplaces.yaml`. `MarketplaceCLITable.lines` gives no line at all for an empty row list, thus `list` printed nothing and there was no "configured source" to show. Thus the work adds `Examples/skill-library/user/marketplaces.yaml` with one source:

    - `github:swissarmyhammer/skills`, alias `demo-skills`, `autoUpdate: false`.

    A `github:owner/repo` form parses with no I/O, and `list` reads only `state.json` of the cache folder. Thus the new mode opens no connection, and `autoUpdate: false` keeps every other demo mode off the network too.

    `SkillsRegistry` does not read `marketplaces.yaml`, thus the new file changes no skill of the fixture library. `ReadmeExampleTests` and `SkillsToolAssemblyTests`, which build a registry over the same folders, stay as they were.
  timestamp: 2026-09-16T01:24:26.809363+00:00
- actor: claude-code
  id: 01m2kx5gnndasygxw2kdma7a7q
  text: |-
    The work, in TDD order.

    RED: the two new cases in `SkillsDemoTests` failed. `--marketplace list` gave the exit code 64 and the text "Unknown option '--marketplace'". The first shape of the unknown-subcommand case asserted only a non-zero exit code, and it passed with no code at all, because an unknown option also gives a non-zero exit. Thus the case now also asserts that the text names the subcommand, and that assertion failed before the code.

    GREEN: `SkillsDemoMain` holds the `--marketplace` flag, the dispatch, and `runMarketplace(arguments:)`. The mode gives the arguments after the flag to `MarketplaceCLI.run(arguments:context:)` over a `MarketplaceCLIContext(stack: FixtureStack.make())`.

    Two things that the work found:
    - `runCLI` and `runMarketplace` both write the text and end the process on a failure. Thus the two share one `report(output:exitCode:)`. There is no second copy of that tail.
    - `MarketplaceCLIResult.output` already holds a line break after each line, and `print(_:)` writes one more. Thus `report` drops one line break at the end of the text, and `--marketplace list` writes no empty line after the table. The CLI mode gives text with no line break at the end, thus the drop does nothing there.

    The mode over the fixture library, by hand:

    ```
    ID           URL                                            CURRENT  CATALOG  CHECKED  STATUS
    demo-skills  https://github.com/swissarmyhammer/skills.git  -        -        -        not installed
    ```

    No line of the output holds a credential: `MarketplaceRow` shows only a URL that parsed, and a URL with a credential is no §5.1 form.
  timestamp: 2026-09-16T01:26:42.613499+00:00
- actor: claude-code
  id: 01m2kx5mz8g6enhqqjv821aqnv
  text: |-
    ### implement -- changed
    - evidence: 3 files -- Examples/skills-demo/SkillsDemoMain.swift, Examples/skill-library/user/marketplaces.yaml, Tests/FoundationModelsSkillsTests/SkillsDemoTests.swift. `swift build --build-tests` gives zero warnings. `swift test` gives 698 tests in 53 suites, all pass (696 before, thus 2 new). `swift test --filter SkillsDemoTests` gives 7 tests, all pass.
    - next: /review
  timestamp: 2026-09-16T01:26:47.016077+00:00
- actor: claude-code
  id: 01m2kxajewesd30frt7qym28tz
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` (0 warnings, 0 errors); `swift test` run 1 of 3 — 698 tests, 53 suites, 0 failures, 0 skipped; run 2 of 3 — 698 tests, 53 suites, 0 failures, 0 skipped; run 3 of 3 — 698 tests, 53 suites, 0 failures, 0 skipped. Full logs at /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer-FoundationModelsSkills/b9d0155a-2dfe-4435-b619-18918c20ca30/scratchpad/test-run-1.log, test-run-2.log, test-run-3.log.
    - next: send the task to review.
  timestamp: 2026-09-16T01:29:28.284500+00:00
- actor: claude-code
  id: 01m2kxetfmdpb3qynk7hafxqy0
  text: |-
    ### review — findings
    - evidence: 1 finding (1 confirmed, 0 refuted) — Examples/skills-demo/SkillsDemoMain.swift:96
    - scope: review sha HEAD~1..HEAD (b4eeb51)
    - next: remove the direct standard-out write in SkillsDemoMain.swift, then run /review again
  timestamp: 2026-09-16T01:31:47.572530+00:00
- actor: claude-code
  id: 01m2kxf5fq6n3714tdmrvm7p2t
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — Examples/skills-demo/SkillsDemoMain.swift, Examples/skill-library/user/marketplaces.yaml, Tests/FoundationModelsSkillsTests/SkillsDemoTests.swift
    - test: green — swift test x3, each 698 tests in 53 suites, 0 failed, 0 skipped
    - commit: b4eeb51 feat(skills-demo): add --marketplace mode to give the MarketplaceCLI group its arguments
    - review: findings — Examples/skills-demo/SkillsDemoMain.swift:96 (no_direct_standard_out_logs)
  timestamp: 2026-09-16T01:31:58.839465+00:00
- actor: claude-code
  id: 01m2kxjqeczhp1fsss3rja7j5h
  text: |-
    The finding `no_direct_standard_out_logs` in `SkillsDemoMain.swift`.

    The judgement: `skills-demo` is a command line demo, thus its normal output does belong on standard out. The rule permits two fixes. This file already writes its failure text with `FileHandle.standardError.write(Data(...))`. Thus the file gets the `FileHandle` fix, not a `swiftlint:disable` comment, and the two output paths of the file are the same shape.

    The change:
    - `report(output:exitCode:)` writes `FileHandle.standardOutput.write(Data((text + lineBreak).utf8))` in place of `print(text)`. The behavior stays the same: the call drops a line break at the end of the text and then puts one back, thus a text that already holds a line break for each line gets no empty line after it.
    - The doc comment of `report` names the new write and its equality with the standard-error path.
    - The doc comment of `lineBreak` no longer names `print(_:)`.
    - The two doc comments of `runCLI` and `runMarketplace` say "writing its output" in place of "printing its output".

    `print` is now absent from the whole file, thus the cause is gone, not only the one line. `ChatMode.swift` and `WatchMode.swift` still hold `print` calls, but those files are outside this change and outside the finding.

    Evidence: `swift build --build-tests` gives 0 warnings and 0 errors. `swift test` gives 698 tests in 53 suites, all pass. Log at /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer-FoundationModelsSkills/b9d0155a-2dfe-4435-b619-18918c20ca30/scratchpad/test-fix.log
  timestamp: 2026-09-16T01:33:55.532627+00:00
- actor: claude-code
  id: 01m2kxjypzkxegj0n61bvh5228
  text: |-
    ### implement — changed
    - evidence: 1 file — Examples/skills-demo/SkillsDemoMain.swift. `swift build --build-tests` gives 0 warnings and 0 errors. `swift test` gives 698 tests in 53 suites, 0 failures, 0 skipped.
    - next: /review
  timestamp: 2026-09-16T01:34:02.975784+00:00
- actor: claude-code
  id: 01m2kxpsc38mpxcwg3x341dett
  text: |-
    ### test — green

    - I ran `swift build --build-tests`. The build had 0 errors and 0 warnings.
    - I ran `swift test` two times, as a full suite each time.
      - Run 1: 698 tests in 53 suites. All tests passed. 0 failures.
      - Run 2: 698 tests in 53 suites. All tests passed. 0 failures.
    - I checked the test files for skip markers. I found one: `unreadableDirectoryInsideARootIsSkippedAndReadableSiblingsStillReport` in `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift`. This test has a guard: `.disabled(if: isRoot, ...)`. The guard stops the test only when the process runs as root. In both runs, the process did not run as root. The test ran in both runs. The test passed in both runs. This is not a skip to avoid a failure.
    - Logs: `/private/tmp/claude-501/-Users-wballard-github-swissarmyhammer-FoundationModelsSkills/b9d0155a-2dfe-4435-b619-18918c20ca30/scratchpad/build1.log`, `test1.log`, `test2.log`.
    - next: none. The build is clean.
  timestamp: 2026-09-16T01:36:08.579327+00:00
depends_on:
- 01M2H13QJ24K9102WB19Z3SQS1
position_column: doing
position_ordinal: '80'
title: Add a skills-demo --marketplace mode
---
## What

marketplace.md MK6 (the `--marketplace` mode in `skills-demo`). The compiled demo shows the marketplace commands in the same way it shows `--chat` and `--watch`.

- `Examples/skills-demo/SkillsDemoMain.swift`: add a `--marketplace` flag next to `--chat` and `--watch`. It passes the remaining arguments to `MarketplaceCLI`, with the demo's fixture stack (`Examples/skills-demo/FixtureStack.swift`) as the config stack. The cache folder comes from `SKILLS_MARKETPLACE_CACHE`.
- Update the doc comment on the demo entry point that lists the modes.

- [x] The `--marketplace` flag and the dispatch
- [x] The doc comment
- [x] The subprocess test

## Acceptance Criteria
- [x] `skills-demo --marketplace list` runs as a subprocess with `SKILLS_MARKETPLACE_CACHE` set to a temporary folder, exits with 0, and prints the configured sources
- [x] The existing `SkillsDemoTests` cases still pass

## Tests
- [x] `Tests/FoundationModelsSkillsTests/SkillsDemoTests.swift`: a subprocess case for `--marketplace list`, and one for an unknown subcommand (non-zero exit)
- [x] Run `swift test --filter SkillsDemoTests`; then `swift test`; all green

## Workflow
- Use `/tdd` -- write failing tests first, then implement to make them pass. #marketplace

## Review Findings (2026-09-15 20:30)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 7 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `Examples/skill-library/user/marketplaces.yaml` — no validator matches this file

- [x] `Examples/skills-demo/SkillsDemoMain.swift:96` `code-hygiene/disallowed-constructs-swift` — no_direct_standard_out_logs: Do not commit print(…), debugPrint(…), dump(…) or _printChanges(), which write to standard out in release. Log to a dedicated logging system, or silence one debug-only line with // swiftlint:disable:next no_direct_standard_out_logs and the reason after it.
