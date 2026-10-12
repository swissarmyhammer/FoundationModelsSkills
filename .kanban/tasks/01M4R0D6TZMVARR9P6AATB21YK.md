---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4rbbfr1k44mycx5qvegr4ms
  text: 'Research: the fixture has 3 files (assets/logo.bin, references/changelog.md with 700 lines, scripts/build.sh). Tests that use the real fixture and count 3: ResourceOpsTests (list resource "total":3), SkillsCLITests (resource list "total":3), ListResourceTests (listing snapshot "total":3), UseSkillPlainTextTests (releaseNotesFilesText and the no-run-call text). StencilPassTests and RenderPipelineTests use the id release-notes only in temporary directories; the fixture change does not touch them. docs/operations.md shows the use skill answer of release-notes with 3 rows; it must show 4 rows.'
  timestamp: 2026-10-12T15:22:59.713638+00:00
- actor: claude-code
  id: 01m4rbfkv3bbwv7pket5njy7sf
  text: |-
    Implementation landed (TDD: RED 10 issues in 15 tests, then GREEN).
    - SKILL.md body: names `references/changelog.md` (read resource), `scripts/build.sh` (run script), `assets/logo.bin` (read resource, binary gives absolute path). No plan.md. Ends with {% include "references/style.md" %}.
    - New file references/style.md (ASD-STE100).
    - references/changelog.md not changed (700 lines).
    - Discovery: ListResourceTests.swift has no row list; it tests only the init and generatedContent of ListResource. The row-list snapshot test of release-notes is in ResourceOpsTests.swift; the references/style.md row was added there.
    - New tests in UseSkillPlainTextTests: useSkillOfReleaseNotesGivesTheIncludedReferenceTextThenTheFourFileRows, theBodyOfReleaseNotesNamesEachFileByItsExactRelativePath. Both file-list texts now have four rows.
    - docs/operations.md: the release-notes example answer now shows four rows.
    - The one build warning ("missing creator for mutated node ... mlx-swift_Cmlx.bundle") comes from SwiftPM for the mlx-swift dependency, not from this change.

    ### implement — changed
    - evidence: swift test: 620 tests in 56 suites passed, 0 failures. Files: Examples/skill-library/project/.skills/release-notes/SKILL.md, Examples/skill-library/project/.skills/release-notes/references/style.md (new), Tests/FoundationModelsSkillsTests/UseSkillPlainTextTests.swift, Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift, Tests/FoundationModelsSkillsTests/SkillsCLITests.swift, docs/operations.md
    - next: /review
  timestamp: 2026-10-12T15:25:14.979766+00:00
depends_on:
- 01M4R0BGFCECWZYT3BWRFXG8ZA
- 01M4R0CD6932FN7X9TCG2BZBMB
position_column: doing
position_ordinal: '80'
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