---
position_column: todo
position_ordinal: '9980'
title: 'Rewrite the use rule of the skills tool: a skill helps with a task, more than one can apply, read again when the work changes'
---
## What

The ACP agent host (`FoundationModelsACPAgent`) asked for this change on 2026-09-20. The use rule of the `skills` tool description is a bad instruction for a model. `SkillCatalogText.descriptionUseRule` (`Sources/FoundationModelsSkills/Operations/SkillCatalogText.swift`) says today:

```
When a task matches a skill below, load it: call this tool with {"op": "use skill", "id": "<id>"}. The answer is the text of the skill. Do the work the way it says.
```

Three faults, from the owner of that host:

1. "When a task matches a skill" is vague. A model reads "matches" as a match of words. A task does not match a skill; a skill helps with a task.
2. The sentence permits one skill only. More than one skill can help with one task, and the model must be able to load each of them.
3. The rule speaks about the start of the task only. When the work changes, the model must read the list again.

The last line of `SkillCatalogText.loadInstruction(exampleID:)`, which ends each `search skill` and `list skill` answer, has the same faults: "If a skill in this list fits your task, load it now, and do the work the way it says."

1. **The new use rule**, on one line, as `descriptionUseRule` is now:

```
Read the skills below before you start. If a skill helps with any part of your task, load it now: call this tool with {"op": "use skill", "id": "<id>"}. Load each skill that helps. More than one can apply. The answer is the text of the skill. Do the work the way it says. Read this list again when the work changes.
```

2. **The new last line of the load instruction:**

```
If a skill in this list helps with any part of your task, load it now, and do the work the way it says. Load each skill that helps. More than one can apply. Search again when the work changes.
```

3. You can change a word when you find a better one, but keep the three properties: "helps with", not "matches" or "fits"; more than one skill; read again when the work changes. Keep the exact load call text, because `SkillCatalogText.useCall(id:)` writes it for all three texts.
4. Update the doc comments that say "a skill that matches the task": `SkillCatalogText.descriptionUseRule` and `SkillsToolDescription.useRule` (`Sources/FoundationModelsSkills/Operations/SkillsToolDescription.swift`).
5. If `SkillsToolDescription` holds a length budget for the description, check that the longer rule still leaves the same room for the skill lines, or state the new numbers in its comment.
6. Documents: `docs/operations.md` shows the rule one time and the last line two times; `CHANGELOG.md` gets a new entry (do not edit the old entry that quotes the old sentence).
7. The host has a live evaluation that measures this text: it drives a small model over ACP with a fixture skill library and reads which skill the model loads. When this card is on `main`, write the commit SHA in a comment on this card, so the host session can run the evaluation against it.

## Acceptance Criteria

- [ ] The tool description starts with the purpose sentence, then the new use rule on one line, then a blank line, as before.
- [ ] Each `search skill` and `list skill` answer with one skill or more ends with the new last line.
- [ ] No file under `Sources/`, `Tests/` or `docs/` holds the text "When a task matches a skill" or "fits your task".
- [ ] The load call in each text is still exactly `{"op": "use skill", "id": "<id>"}`.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/SearchListPlainTextTests.swift`: `descriptionUseRule` and the expected load instruction hold the new texts, word for word.
- [ ] `Tests/FoundationModelsSkillsTests/SkillsToolDescriptionTests.swift` and `SkillsCatalogToolTests.swift`: the fixed sentences hold the new use rule.
- [ ] `Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift`: `loadInstructionLastLine` holds the new last line.
- [ ] A documents test (the suite that compares `docs/operations.md` with the real output, if there is one; else a new case in `SearchListPlainTextTests`): `docs/operations.md` holds the new rule one time and the new last line two times.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#skills #search