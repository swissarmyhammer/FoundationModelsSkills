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
depends_on:
- 01M2H13QJ24K9102WB19Z3SQS1
- 01M2H141Y80CJR0NPGAVEGYN0M
- 01M2H1P68DQAVE9B0SAC5HEFA3
- 01M2H1PT3B5H48CG7BKZJ5B7R9
- 01M2H1Q3VS6CRF692A1VX8MZZF
- 01M2H1QW6Z6BN6YEF4HZN3F3YM
position_column: todo
position_ordinal: '9480'
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

- [ ] `docs/marketplaces.md`
- [ ] The `docs/security.md` section
- [ ] The `docs/operations.md` note, the README link, and the `marketplace.md` status line
- [ ] A docs coverage test

## Acceptance Criteria
- [ ] Every public environment variable and every `skills marketplace` subcommand is described in `docs/marketplaces.md`
- [ ] `docs/security.md` has all seven marketplace points
- [ ] `ReadmeExampleTests` still passes

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceDocsTests.swift`: read `docs/marketplaces.md` (found from `#filePath`) and assert that it names `SKILLS_MARKETPLACE_CACHE`, `SKILLS_MARKETPLACE_SEED`, `SKILLS_MARKETPLACE_AUTOUPDATE`, and every subcommand name taken from the `MarketplaceCLI` configuration (not a hand-written list); assert that `docs/security.md` has a "Marketplaces" heading
- [ ] Run `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace