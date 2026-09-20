---
comments:
- actor: claude-code
  id: 01m2zmhvq2c0sbwdynqpdzv493
  text: |-
    Research done. What holds the text today:

    - `SkillCatalogText.descriptionUseRule` (Sources/FoundationModelsSkills/Operations/SkillCatalogText.swift) holds the use rule; `SkillCatalogText.loadInstruction(exampleID:)` holds the four lines that end each `search skill` and `list skill` answer.
    - `SkillsToolDescription.useRule` reads `SkillCatalogText.descriptionUseRule`. The doc comments of `SkillsToolDescription` (type doc and `useRule`) and of `SkillsCatalogTool` say "matches the task".
    - The length budget: `SkillsToolDescription.make(catalog:characterLimit:)` gives `characterLimit` to `list(for:characterLimit:)` alone. The fixed sentences never count against it, thus the longer rule takes no room from the skill lines. The doc comment will state this.
    - Tests that hold the fixed texts word for word: `SearchListPlainTextTests` (rule and the four instruction lines), `SkillsToolDescriptionTests` (header), `SkillsCatalogToolTests` (fixed sentences), `SkillsToolAssemblyTests` (`loadInstructionLastLine`).
    - There is no suite that compares `docs/operations.md` with the real output. `DocumentationTests` holds the documents to the override rule only. Thus the documents case goes in `SearchListPlainTextTests`, as the card says, and it reads the file with `FixtureLibrary.readText(relativePath:)`.
    - `docs/operations.md` holds the rule one time (the description example) and the last line two times (the `search skill` example and the `list skill` example).
  timestamp: 2026-09-20T14:47:03.138392+00:00
- actor: claude-code
  id: 01m2zy7w2hjdkexyhmkjppv0xh
  text: |-
    Second pass. The first agent stopped at the prose of `docs/operations.md` and the CHANGELOG entry. Both were on the disk and complete. This pass read the full change against the card, and did the work that was not there.

    What the first agent had done, and this pass kept:

    - `SkillCatalogText`: the new `descriptionUseRule`, and a new private constant `loadInstructionLastLine` that `loadInstruction(exampleID:)` uses for its last line. The load call still comes from `useCall(id:)`, thus the three texts hold the same call.
    - The doc comments of `SkillCatalogText.descriptionUseRule`, `SkillsToolDescription` (type doc and `useRule`) and `SkillsCatalogTool`.
    - The length budget note: `SkillsToolDescription` says that the limit counts the list alone, thus the longer rule takes no room from the skill lines. No number changes.
    - The four test files, with the new texts word for word, and the new case `theHostGuideShowsTheUseReleAndTheLoadInstructionOfToday` that counts the rule one time and the last line two times in `docs/operations.md`.
    - `docs/operations.md` and the new CHANGELOG entry. The old CHANGELOG entry that quotes the old sentence is not touched.

    What this pass added:

    - `docs/operations.md`: the prose of the `search skill` and `list skill` section wrapped badly after the edit. The paragraph is wrapped again. The text does not change.
    - `README.md`: the sentence "tells the model to load a skill that matches the task" was the old rule. It now says "tells the model to load each skill that helps with any part of the task". The card does not name the README, but the sentence tells the reader what the tool does, thus a stale sentence is a fault of this change.
    - `plan.md` decision 22: the same stale sentence, and an amendment note in the form the file uses ("**Amended 2026-09-20 by ^4apmcft:**"). The file records each decision with a dated amendment, thus the note goes beside the text, not in place of it.

    Checks:

    - `rg 'When a task matches a skill|fits your task' Sources Tests docs` gives no match.
    - The load call literal `{"op": "use skill", "id": "<id>"}` stands in `SkillCatalogText.useCall(id:)` one time, and in each test that pins a text.
    - `swift build --build-tests`: 0 warnings. `swift test`: 809 tests in 66 suites, 0 failures.

    Open: item 7 of the card asks for the commit SHA of this change on `main`, for the live evaluation of the host. This pass does not commit, thus the SHA comes after the commit step.
  timestamp: 2026-09-20T17:36:21.585961+00:00
- actor: claude-code
  id: 01m2zy86d62fk84jfkx05k46te
  text: |-
    Correction to the comment above: the new documents test is `SearchListPlainTextTests.theHostGuideShowsTheUseRuleAndTheLoadInstructionOfToday`.

    ### implement — changed
    - evidence: 10 files — Sources/FoundationModelsSkills/Operations/SkillCatalogText.swift, Sources/FoundationModelsSkills/Operations/SkillsCatalogTool.swift, Sources/FoundationModelsSkills/Operations/SkillsToolDescription.swift, Tests/FoundationModelsSkillsTests/SearchListPlainTextTests.swift, Tests/FoundationModelsSkillsTests/SkillsCatalogToolTests.swift, Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift, Tests/FoundationModelsSkillsTests/SkillsToolDescriptionTests.swift, docs/operations.md, CHANGELOG.md, README.md, plan.md. `swift build --build-tests`: 0 warnings. `swift test`: 809 tests, 66 suites, 0 failures. Each acceptance item and each test item of the card is checked.
    - next: `/review`. After the commit is on `main`, write the SHA in a comment, for the live evaluation of the host (item 7).
  timestamp: 2026-09-20T17:36:32.166520+00:00
- actor: claude-code
  id: 01m2zyaw0emshhka1qg8z0f34s
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` — build complete, 0 warnings. `swift test` — 809 tests passed in 66 suites, 0 failed, 0 skipped.
    - next: ready for review.
  timestamp: 2026-09-20T17:37:59.822544+00:00
- actor: claude-code
  id: 01m2zyc2nt0pnje12d7dynxtt7
  text: |-
    ### commit — changed
    - evidence: 49fd2c2 docs(skills-tool): tell the model to load each skill that helps
    - next: none
  timestamp: 2026-09-20T17:38:39.418882+00:00
- actor: claude-code
  id: 01m2zygqp89q8r3dv5er1mz2fv
  text: |
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 49fd2c2) — 0 findings, 0 confirmed, 0 refuted, 7 files attempted, 0 failed. No prior Review Findings section, and every checklist item in the description is checked.
    - next: none. The card moves to done.
  timestamp: 2026-09-20T17:41:12.008609+00:00
- actor: wballard
  id: 01m2zyh8jt9xjdekph3ac1czbj
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 11 files (one earlier agent stopped at a usage limit; this pass finished it)
    - test: green — swift test, 809 passed, 0 warnings
    - commit: 49fd2c2
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-20T17:41:29.306058+00:00
position_column: done
position_ordinal: ff8580
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

- [x] The tool description starts with the purpose sentence, then the new use rule on one line, then a blank line, as before.
- [x] Each `search skill` and `list skill` answer with one skill or more ends with the new last line.
- [x] No file under `Sources/`, `Tests/` or `docs/` holds the text "When a task matches a skill" or "fits your task".
- [x] The load call in each text is still exactly `{"op": "use skill", "id": "<id>"}`.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/SearchListPlainTextTests.swift`: `descriptionUseRule` and the expected load instruction hold the new texts, word for word.
- [x] `Tests/FoundationModelsSkillsTests/SkillsToolDescriptionTests.swift` and `SkillsCatalogToolTests.swift`: the fixed sentences hold the new use rule.
- [x] `Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift`: `loadInstructionLastLine` holds the new last line.
- [x] A documents test (the suite that compares `docs/operations.md` with the real output, if there is one; else a new case in `SearchListPlainTextTests`): `docs/operations.md` holds the new rule one time and the new last line two times.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#skills #search