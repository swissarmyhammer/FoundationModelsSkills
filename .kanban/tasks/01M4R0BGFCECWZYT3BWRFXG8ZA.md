---
assignees:
- claude-code
depends_on:
- 01M4R0ANACQ08YDG539AAJ8FA4
- 01M4R0B0XATW46VEWB0CDTJWZ9
position_column: todo
position_ordinal: '8280'
title: 'use skill: add the list of the skill''s files and the read call to the answer'
---
## What
Now, the `use skill` answer gives the rendered body only. The model is not told that the skill has files. After the body, add a plain-text list of the files of the skill and the exact calls that read a file or run a script. Do not use tags, XML or other wrappers. The user decided on plain text, because we cannot be sure that each model knows tags that we make.

The text to add, for the `release-notes` fixture:

```text
<rendered body>

Files of this skill:
- assets/logo.bin (asset)
- references/changelog.md (reference)
- scripts/build.sh (script)

To read a file, call the `skills` tool with {"op": "read resource", "id": "release-notes", "path": "<path>"}. Give the path as it is in this list.
To run a script, call the `skills` tool with {"op": "run script", "id": "release-notes", "path": "scripts/<name>"}.
```

- The file list comes from the combined view: the same rows that `list resource` gives (`SkillOverlay.entries()`, excluding `SKILL.md` and hidden files), in path order, with the same kind (`script`, `reference`, `asset`, `other`). Reuse the row logic of `Sources/FoundationModelsSkills/Resources/ListResource.swift`. Do not write a second copy of it.
- Use the same row limit as `list resource` (100). When the skill has more files, add the line `<N> more files are not listed. See them with {"op": "list resource", "id": "<id>"}.`
- Make the call text from `SkillsTool.toolName` and the verb and noun constants of the operations (`ReadResource.verb`, `resourceOperationNoun`, `RunScript.verb`, and the others), as `SkillCatalogText` does now. Do not write the names as literals.
- Add the `run script` line only when the list has a minimum of one `script` row AND the host policy permits scripts (`policy.isScriptExecutionDisabled` is false).
- A skill with no file other than `SKILL.md` gets no extra text. Its answer is the same as now.
- Put the code in `Sources/FoundationModelsSkills/Operations/UseSkill.swift`, with the text in a new `internal enum SkillFilesText` in `Sources/FoundationModelsSkills/Operations/SkillFilesText.swift` (or in `SkillCatalogText.swift` if it fits there). Add the list in `UseSkill.execute(in:)` only. `SkillsRegistry.call(id:arguments:)` and the user `/` command path do not change.
- A corrective answer (unknown id) does not change.
- Update the two texts that say the answer is the body "and nothing else": the `UseSkillOutput` doc comment in `UseSkill.swift`, and "The `use skill` answer" in `docs/operations.md`. Show the example above in the docs, and say that the list follows the body when the skill has files.

## Acceptance Criteria
- [ ] `use skill` of `release-notes` gives the body, then `Files of this skill:`, the three rows in path order, and the two call lines with the id `release-notes`.
- [ ] `use skill` of a skill that has only `SKILL.md` (for example `commit`) gives the same text as now.
- [ ] A skill with more than 100 files gives 100 rows and the `more files are not listed` line with the correct count.
- [ ] A file that only a lower layer holds is in the list.
- [ ] A skill with no `scripts/` file gets no `run script` line.
- [ ] When the host policy disables scripts, the answer has no `run script` line.
- [ ] The added text holds no `</` and no `<word>…</word>` pair.

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/UseSkillPlainTextTests.swift`: exact-text tests for `release-notes`, for a skill with only `SKILL.md`, for a skill with no script, for a disabled script policy, and for the 100-row limit over a generated temp skill; a lower-layer file is in the list.
- [ ] Update each test that compares the full `use skill` answer of a skill that has files (search for `release-notes` and `use skill` in `Tests/`).
- [ ] `swift test` passes with no failure.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.