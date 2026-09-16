---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2jhzcpf0hw623fxt3azytc3
  text: |-
    ### carry-over from ^n3yvh8r — add to this task
    - `marketplace.md` §6.2 says that `alias` "wins over the catalog name". The new §5.3 text (commit 9ca51d5) says that the pre-fetch key (alias, else the repository name) sets validation and the cache folder name, and that the catalog name is the display id after a fetch. Change §6.2 so that it agrees with §5.3.
    - ^n3yvh8r added four validation rules that the plan did not state. Describe them in `docs/marketplaces.md`: a git URL must end in `.git`; an HTTPS URL with a user name or a password is refused (credentials come from `MarketplacePolicy.credentials`); a local folder has no ref and no sha; a pre-fetch key that is empty, or that has a `/` or a NUL character, is refused.
  timestamp: 2026-09-15T12:51:53.167809+00:00
- actor: claude-code
  id: 01m2kx26vgrdycgsba1rs90acj
  text: 'From ^zn3f3ym (the `skills-demo --marketplace` mode): `plan.md` §11 still says that `skills-demo` is "one binary, three modes" and lists the default CLI, `--chat`, and `--watch`. The binary now holds a fourth mode, `--marketplace`. Correct that line with the other documentation work of this card.'
  timestamp: 2026-09-16T01:24:54.256999+00:00
- actor: claude-code
  id: 01m2kybehkvq6stjw270rdx3f9
  text: |-
    Research, then the documentation. Each claim comes from the code that shipped, and not from the plan:

    - The cache directory is `SKILLS_MARKETPLACE_CACHE`, else `~/.cache/skills/marketplaces` (`MarketplaceCache.cacheDirectory(environment:)`). `SKILLS_MARKETPLACE_SEED` names the read-only seed folder. `SKILLS_MARKETPLACE_AUTOUPDATE=0` stops every automatic update (`MarketplacePolicy.automaticUpdateVariable`).
    - The `marketplace` group holds seven subcommands, and each one takes `--include-project`. `MarketplaceCLI.configuration.subcommands` is the list that the new test reads.
    - `marketplace.md` §6.2 said that `alias` "wins over the catalog name". The code says that the alias is the pre-fetch key (`MarketplaceIdentity.preFetchKey(for:)`), and that the catalog `name` is the display id after a fetch. §5.3 is right, thus §6.2 now agrees with it.
    - Two more §6.2 lines did not agree with the code: the sketch named `layers() -> [DotfolderStack.Layer]`, and the shipped call is `marketplaceLayers() -> [MarketplaceLayer]`. The sketch also had no `layerUpdates`, which is how the registry learns of an update. Both lines are corrected.
    - The writer lock is `LOCK_EX | LOCK_NB`, thus it never waits. A wait would hold the thread of the actor that the holder of the lock needs.
    - The credential rule holds at the parser: `MarketplaceLocation.httpsURL(_:)` throws `credentialsInURL` for a URL with a user name or a password. Thus no stored URL, no row of `marketplace list`, no diagnostic, and no error message can hold a credential.
    - The grants fold in `SkillsRegistry.effectivePolicy(for:)`: each axis is the more restrictive of the host `RenderPolicy` and the grant of the marketplace.

    `plan.md` §11 said "three modes"; it now says four, and it describes `--marketplace`.
  timestamp: 2026-09-16T01:47:25.619910+00:00
- actor: claude-code
  id: 01m2kybjmwgp0g1y6agn0tqfsq
  text: |-
    ### implement — changed
    - evidence: 7 files — docs/marketplaces.md (new), docs/security.md, docs/operations.md, README.md, marketplace.md, plan.md, Tests/FoundationModelsSkillsTests/MarketplaceDocsTests.swift (new). `swift build --build-tests`: 0 warnings. `swift test`: 700 tests in 54 suites passed (698 in 53 before this card; the new suite holds 2 tests).
    - next: /review
  timestamp: 2026-09-16T01:47:29.820700+00:00
- actor: claude-code
  id: 01m2kyg3bvc8v9qk45jjvw5s2f
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` clean (0 warnings, 0 errors). `swift test` run 1: 700 tests, 54 suites, 0 failures, 0 warnings. `swift test` run 2: 700 tests, 54 suites, 0 failures, 0 warnings. `MarketplaceDocsTests` suite passed both runs.
    - next: ready for review.
  timestamp: 2026-09-16T01:49:58.011440+00:00
depends_on:
- 01M2H13QJ24K9102WB19Z3SQS1
- 01M2H141Y80CJR0NPGAVEGYN0M
- 01M2H1P68DQAVE9B0SAC5HEFA3
- 01M2H1PT3B5H48CG7BKZJ5B7R9
- 01M2H1Q3VS6CRF692A1VX8MZZF
- 01M2H1QW6Z6BN6YEF4HZN3F3YM
position_column: doing
position_ordinal: '80'
title: 'Document marketplaces: host guide, security posture, CLI, and README link'
---
## What

marketplace.md §10 and the MK6 docs item. Write the documentation after the behavior exists, so it describes what the tests prove. Write it in ASD-STE100 Simplified Technical English, like the other docs in this repository.

- New `docs/marketplaces.md`, the host guide:
  - how to add sources in code and in `marketplaces.yaml`
  - the order rule: left to right, the last wins, and the full stack is `url[0] < … < url[n] < defaults < user < project`
  - the cache location and `SKILLS_MARKETPLACE_CACHE`
  - `SKILLS_MARKETPLACE_SEED` and `SKILLS_MARKETPLACE_AUTOUPDATE`
  - when checks run (at start and on request; an interval only if the host gives one)
  - pins, `checkOnly`, and `.nextLaunch`
  - skill selection and the catalog formats that are read
  - partial scope, and the grants
  - the `skills marketplace` CLI
  - how to publish a marketplace (point to the `swissarmyhammer/skills` layout)
- `docs/security.md`: add a "Marketplaces" section with the seven points of marketplace.md §10.
- `docs/operations.md`: state that the model surface has no marketplace operations, and that marketplace skills are ordinary rows.
- `README.md`: add `docs/marketplaces.md` to the Documentation list. Keep the usage block unchanged, so `ReadmeExampleTests` stays green.
- `marketplace.md`: add a short status line at the top that says the plan is implemented, and link `docs/marketplaces.md`.

- [x] `docs/marketplaces.md`
- [x] The `docs/security.md` section
- [x] The `docs/operations.md` note, the README link, and the `marketplace.md` status line
- [x] A docs coverage test

## Acceptance Criteria
- [x] Every public environment variable and every `skills marketplace` subcommand is described in `docs/marketplaces.md`
- [x] `docs/security.md` has all seven marketplace points
- [x] `ReadmeExampleTests` still passes

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceDocsTests.swift`: read `docs/marketplaces.md` (found from `#filePath`) and assert that it names `SKILLS_MARKETPLACE_CACHE`, `SKILLS_MARKETPLACE_SEED`, `SKILLS_MARKETPLACE_AUTOUPDATE`, and every subcommand name taken from the `MarketplaceCLI` configuration (not a hand-written list); assert that `docs/security.md` has a "Marketplaces" heading
- [x] Run `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace