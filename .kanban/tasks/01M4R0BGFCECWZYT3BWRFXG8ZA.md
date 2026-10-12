---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4r6cqj6w020tv0v44zgndan
  text: |-
    Research done.
    - ListResource has the row logic as private static `resourceRows(in:)`, `isListed`, `kind(forRelativePath:)` and `rowCap = 100`. Plan: make one internal entry `ListResource.listedRows(in:)` (sorted rows) and an internal `rowCap`, and call it from ListResource.execute and from the new SkillFilesText. No second copy.
    - UseSkill needs the overlay of the skill. `ResourceIDLookup.overlay(id:context:)` is private; plan: make it internal and call it from UseSkill.execute(in:) after the render. UseSkill opens no file itself, thus LoadingBoundaryTests stays green.
    - SkillCatalogText.useCall is private and writes `{"op": ..., "id": ...}`. Plan: add one internal call builder in SkillCatalogText (op, id, optional path) and let useCall use it, so the call text of SkillFilesText comes from `ReadResource.opString`, `RunScript.opString`, `ListResource.opString` and `SkillsTool.toolName`.
    - Host policy: `context.registry.policy.isScriptExecutionDisabled`.
    - The `run script` line reads all rows of the skill (not only the first 100), thus a script that sorts after row 100 still gets the line.
    - Docs to change: the `UseSkillOutput` doc comment and "The `use skill` answer" in docs/operations.md.
  timestamp: 2026-10-12T13:56:17.606348+00:00
- actor: claude-code
  id: 01m4r6n0gdx67e9qbdtxe1x7xe
  text: |-
    Implementation landed (TDD: RED run showed 5 failures in UseSkillPlainTextTests, then GREEN).
    - Discovery: the rendered body of each fixture ends with a line break. Body + "\n\n" gave two blank lines, not the one blank line of the card example. `SkillFilesText.appending(_:to:)` adds one line break after a body that ends with a line break, and two after a body that does not. The body itself does not change. SkillFilesTextTests holds both cases.
    - ListResource: the private `resourceRows(in:)` is now internal `listedRows(in:)` (sorted). `rowCap` and the new `scriptKind` are internal. ListResource.execute and UseSkill both call `listedRows(in:)`; there is no second copy of the row logic.
    - SkillCatalogText: new internal `call(op:id:path:)` and `callTheTool(with:)`; the load call uses them too. SkillFilesText makes its calls from `ReadResource.opString`, `RunScript.opString`, `ListResource.opString` and `SkillsTool.toolName`.
    - ResourceIDLookup.overlay(id:context:) is internal now; UseSkill reads the overlay after the render. UseSkill opens no file, and LoadingBoundaryTests passes.
    - The `run script` check reads all rows, also the rows after row 100.
    - The CLI `skills skill use` goes through UseSkill.execute, thus it prints the list too. `SkillsRegistry.call` and the `/` command path did not change.
    - No existing test compared the full `use skill` answer of a skill with files; the full suite passed with no test edit other than the new tests.
  timestamp: 2026-10-12T14:00:48.909489+00:00
- actor: claude-code
  id: 01m4r6n3pyqjkwzey7c3ykm8gb
  text: |-
    ### implement — changed
    - evidence: `swift test` — 597 tests in 56 suites passed, 0 failures (one SwiftPM build-system line "missing creator for mutated node" for the mlx bundle, not from source). Files: Sources/FoundationModelsSkills/Operations/SkillFilesText.swift (new), Sources/FoundationModelsSkills/Operations/UseSkill.swift, Sources/FoundationModelsSkills/Operations/SkillCatalogText.swift, Sources/FoundationModelsSkills/Resources/ListResource.swift, Sources/FoundationModelsSkills/Resources/ResourceSupport.swift, docs/operations.md, Tests/FoundationModelsSkillsTests/UseSkillPlainTextTests.swift, Tests/FoundationModelsSkillsTests/SkillFilesTextTests.swift (new).
    - next: /review
  timestamp: 2026-10-12T14:00:52.190754+00:00
- actor: claude-code
  id: 01m4r6v3mdb1nhfcqhb25g35rk
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (3d6cbb1). 0 findings, 0 confirmed, 2 refuted. 7 files reviewed. 5 files not reviewed: 4 .kanban files (ignore rule), docs/operations.md (no validator matches).
    - next: none. The task is in done.
  timestamp: 2026-10-12T14:04:08.717041+00:00
- actor: claude-code
  id: 01m4r6vayq4jjdb334pqvsda72
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 8 files
    - test: green — swift test, 597 passed in 56 suites
    - commit: 3d6cbb1
    - review: clean — 0 findings
  timestamp: 2026-10-12T14:04:16.215768+00:00
depends_on:
- 01M4R0ANACQ08YDG539AAJ8FA4
- 01M4R0B0XATW46VEWB0CDTJWZ9
position_column: done
position_ordinal: ff9d80
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