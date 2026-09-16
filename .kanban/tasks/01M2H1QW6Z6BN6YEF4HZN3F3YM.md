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