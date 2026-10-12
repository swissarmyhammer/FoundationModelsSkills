---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4r73yc13q26y0q6pdrfc4ax
  text: |-
    Research and implementation notes:
    - The new sentence is `SkillCatalogText.descriptionFilesRule`, beside `descriptionUseRule`. It is made from `callTheTool(with:)`, `call(op:id:path:)`, `ReadResource.opString`, and `UseSkill.opString`. No op name is a literal.
    - The sentence is on its own line after the use rule. `SkillsToolDescription.make` puts it in the header only, thus the empty catalog text does not change and the sentence does not count against `characterLimit`.
    - The example path `references/guide.md` is now one constant, `ResourcePathRules.examplePath`. The `path` parameter description and the new sentence both use it. The text of the parameter description did not change.
    - `ReadResource.operationDescription` now starts "Read a file of a skill. Give the path relative to the skill directory, as the `use skill` answer lists it." The binary-file sentence from ^cdtjwz9 stays.
    - `SearchListPlainTextTests.theToolDescriptionHoldsTheNewUseRuleWordForWord` expected a blank line after the use rule. The use rule is now followed by one line break and the files sentence, thus the test now expects one line break.
    - `DocumentationTests` has no test that compares the example block of `docs/operations.md`. A new test in `SkillsToolDescriptionTests` checks that the guide holds the files sentence one time.
  timestamp: 2026-10-12T14:08:58.241875+00:00
- actor: claude-code
  id: 01m4r742pej5ee21jqadn4tw8x
  text: |-
    ### implement — changed
    - evidence: `swift test` gives 602 tests in 56 suites, all pass. No compiler warning; the one SwiftPM "missing creator" line about the mlx bundle existed before this change. RED was seen first: 12 issues in 3 suites. Files: Sources/FoundationModelsSkills/Operations/SkillCatalogText.swift, Sources/FoundationModelsSkills/Operations/SkillsToolDescription.swift, Sources/FoundationModelsSkills/Resources/ReadResource.swift, Sources/FoundationModelsSkills/Resources/ResourceSupport.swift, Tests/FoundationModelsSkillsTests/SkillsToolDescriptionTests.swift, Tests/FoundationModelsSkillsTests/SkillsCatalogToolTests.swift, Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift, Tests/FoundationModelsSkillsTests/SearchListPlainTextTests.swift, docs/operations.md
    - next: /review. Not committed.
  timestamp: 2026-10-12T14:09:02.670554+00:00
- actor: claude-code
  id: 01m4r795phnn4xzkg280wn4126
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (a799f8e). 0 findings, 0 confirmed, 1 refuted. 8 files reviewed. The review did not examine docs/operations.md, because no validator matches it. An ignore rule excluded the .kanban/ files.
    - next: none. The task is in done.
  timestamp: 2026-10-12T14:11:49.585068+00:00
- actor: claude-code
  id: 01m4r79d8y2bkz4we5aesxjp7j
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 9 files
    - test: green — swift test, 602 passed in 56 suites
    - commit: a799f8e
    - review: clean — 0 findings
  timestamp: 2026-10-12T14:11:57.342812+00:00
depends_on:
- 01M4R0BGFCECWZYT3BWRFXG8ZA
- 01M4R0B0XATW46VEWB0CDTJWZ9
position_column: done
position_ordinal: ff9e80
title: 'Tool description: tell the model to get the files of a skill with read resource and a relative path'
---
## What
The description of the fused `skills` tool tells the model about `use skill` only. Add one fixed sentence. The sentence tells the model that a skill can have files, and that `read resource` gets a file with a path relative to the skill.

- `Sources/FoundationModelsSkills/Operations/SkillsToolDescription.swift`: add a fixed sentence after the use rule, for example: `A skill can have files, such as references/guide.md. To read one, call this tool with {"op": "read resource", "id": "<id>", "path": "<path relative to the skill>"}. The answer of use skill lists the files of the skill.` Put the text in `SkillCatalogText` beside `descriptionUseRule`, and make it from `SkillsTool.toolName` and the verb and noun constants of the operations, not from literals. This sentence is a fixed sentence: it does not count against `catalogCharacterLimit`, and it is never cut. It is not in the description when no skill is visible.
- `ReadResource.operationDescription`: "Read a file of a skill. Give the path relative to the skill directory, as the `use skill` answer lists it." Keep the binary-file text that the binary task added.
- `docs/operations.md`: update "The tool description and the `id` enum": the new sentence in the example text block, and the count of fixed sentences.
- Update the doc comment of `SkillsToolDescription` (it says "two fixed sentences").

## Acceptance Criteria
- [ ] The description of a tool over a catalog with a minimum of one visible skill has the new sentence after the use rule, and before the skill list.
- [ ] The description of an empty catalog does not change.
- [ ] At step 4 of the limit (ids only, then the count line), the new sentence is still there, and it does not use characters of the list limit.
- [ ] `ReadResource.operationDescription` says that the path is relative to the skill.
- [ ] The added text holds no `</` and no `<word>…</word>` pair.

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillsToolDescriptionTests.swift`: update the exact-text tests; add a test that the sentence is there at each of the four limit steps, and not there for an empty catalog.
- [ ] `Tests/FoundationModelsSkillsTests/DocumentationTests.swift`: if a test compares the example text of `docs/operations.md` with the code, update it.
- [ ] `swift test` passes with no failure.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.