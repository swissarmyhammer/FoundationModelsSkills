---
assignees:
- claude-code
depends_on:
- 01M4R0BGFCECWZYT3BWRFXG8ZA
- 01M4R0B0XATW46VEWB0CDTJWZ9
position_column: todo
position_ordinal: '8380'
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