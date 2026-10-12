---
assignees:
- claude-code
depends_on:
- 01M4R0BGFCECWZYT3BWRFXG8ZA
- 01M4R0CD6932FN7X9TCG2BZBMB
position_column: todo
position_ordinal: '8580'
title: 'Example release-notes skill: use exact relative paths and include a reference'
---
## What
`Examples/skill-library/project/.skills/release-notes/SKILL.md` is the fixture that the tests and the demo use for resources. Now its body says "this skill's bundled `references/` changelog and `scripts/` build script (plan.md §7.3 resource ops)". `plan.md` was deleted. The body must show the correct pattern for authors.

- Change the body of `release-notes/SKILL.md`. The new body:
  - names each file with its exact relative path (`references/changelog.md`, `scripts/build.sh`, `assets/logo.bin`), as the agentskills.io specification recommends;
  - tells the model to read `references/changelog.md` with `read resource`, and to run `scripts/build.sh` with `run script`;
  - does not refer to `plan.md`.
- Add one small reference file (for example `references/style.md`) that the body includes with `{% include "references/style.md" %}`, so the fixture uses the include feature one time. The README says the fixture "uses each templating and visibility feature one time".
- Do not change the line count of `references/changelog.md`. The paging tests use it.
- The new file changes the file count of `release-notes` from 3 to 4. Update the tests that expect 3.
- Write the body and the new file in ASD-STE100 Simplified Technical English.

## Acceptance Criteria
- [ ] The body of `release-notes` holds the three exact relative paths and no reference to `plan.md`.
- [ ] `use skill` of `release-notes` gives the body with the included reference text, then the file list with four rows.
- [ ] `list resource` of `release-notes` gives the new file as a `reference` row, and `total` is 4.
- [ ] The paging test of `references/changelog.md` gives the same result as now.

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift`: update the `"total":3` checks to 4.
- [ ] `Tests/FoundationModelsSkillsTests/SkillsCLITests.swift`: update the `"total":3` checks to 4.
- [ ] `Tests/FoundationModelsSkillsTests/ListResourceTests.swift`: update the row list.
- [ ] `Tests/FoundationModelsSkillsTests/UseSkillPlainTextTests.swift`: update the exact-text test of `release-notes` from the `use skill` task; add a test that the answer holds the included text and the four file rows.
- [ ] Search `Tests/` for `release-notes` and update each other match that breaks.
- [ ] `swift test` passes with no failure.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.