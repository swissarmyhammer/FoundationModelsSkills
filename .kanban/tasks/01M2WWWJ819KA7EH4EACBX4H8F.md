---
comments:
- actor: claude-code
  id: 01m2wz2nmfnjrzg2asmz6f4t5p
  text: |-
    Research done. Findings:

    - `use skill` gives plain text through `PlainTextOperations` (a marker `OperationTool` that finds the payloads of plain-text operations) and `SkillsCatalogTool.dispatchAsPlainText`. The same path can serve `search skill` and `list skill`: add a marker for each, and make their outputs strings.
    - Plan: `SearchSkillOutput` becomes `CorrectiveOutcome<String>`. `ListSkill.Output` becomes `String`. The blank-query and empty-catalog correctives stay.
    - After this change, `SkillRow`, `SkillUseCall`, `SearchSkillResult`, `ListSkillResult` and `UseSkillResult` have no user. They are public, so the removal is a source break. It goes in the CHANGELOG.
    - Decision: the card gives the list line as `- <id>: <description>`. Thus a `list skill` line no longer shows the marketplace source (`SkillRow.source`). marketplace.md §9.1 says "can show", and the `/` command listing (`commandListing()`) keeps the source. The four list-skill cases in `MarketplaceProvenanceDisplayTests` change: the source cases go, and the no-URL case reads the text.
    - The CLI (`SkillsCLI`) dispatches through `operationTool`, thus it prints each answer as one JSON string, the same as `skills skill use` now.
    - Test files that read the JSON of search or list: SkillOperationsTests, SkillsToolAssemblyTests, SkillsCLITests, HotReloadTests, SkillsReloadFollowerTests, ReadmeExampleTests, MarketplaceProvenanceDisplayTests, SkillsDemoTests. A shared test helper will read the ids from the plain lines.
  timestamp: 2026-09-19T13:53:16.431882+00:00
- actor: claude-code
  id: 01m2wzn6vdtaffyy9kn628jv6j
  text: |-
    Implementation landed (not committed):

    - New `Operations/SkillCatalogText.swift`: the one place that writes the skill line `- <id>: <description>`, the load call `{"op": "use skill", "id": "<id>"}`, the four instruction lines, and the new second sentence of the tool description. `SkillsToolDescription` now uses it.
    - `SearchSkill`: `SearchSkillOutput = CorrectiveOutcome<String>`; answer is the query line + lines + instruction; no body, no `use`, no `next`, no `total`. No match gives `No skill matches this search.`. The selection-body code and its `os.Logger` are gone.
    - `ListSkill`: `Output = String`; the same lines and instruction; a filter with no match gives `No skill matches this filter.`; no visible skill gives `No skills are available.`.
    - `PlainTextOperations` now has markers for `search skill` and `list skill` too, thus `call(arguments:)` and `perform(_:)` give the decoded text.
    - Deleted `Operations/SkillRow.swift` (`SkillRow`, `SkillUseCall`, `SearchSkillResult`, `ListSkillResult`, `UseSkillResult`). No other repo in ../ uses them (checked with rg).
    - `SkillSearchAnswer.isSelection` is kept as public host API; its doc no longer says search loads a body.
    - TDD: new `SearchListPlainTextTests` and the changed header in `SkillsToolDescriptionTests` failed first (13 issues), for the expected reasons.
    - Found: several old negative checks such as `!json.contains("\"id\":\"alpha\"")` pass for any plain answer. They are changed to read ids with a new test helper `SkillLineReader`, so they still prove something.
    - Docs: docs/operations.md, docs/marketplaces.md (Provenance), CHANGELOG.md.
  timestamp: 2026-09-19T14:03:23.885971+00:00
- actor: claude-code
  id: 01m2wzydtf66xgxgq05spsn1km
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` 0 errors, 0 warnings; `swift test` 742 tests in 58 suites passed. Files: Sources/FoundationModelsSkills/Operations/{SkillCatalogText.swift (new), SearchSkill.swift, ListSkill.swift, PlainTextOperations.swift, SkillsCatalogTool.swift, SkillsTool.swift, SkillsToolDescription.swift, SkillRow.swift (deleted)}, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Sources/FoundationModelsSkills/Search/SkillSearchAnswer.swift; Tests: SearchListPlainTextTests.swift (new), SkillLineReader.swift (new), SkillOperationsTests, SkillsToolAssemblyTests, SkillsToolDescriptionTests, SkillsCLITests, SkillsDemoTests, HotReloadTests, SkillsReloadFollowerTests, ReadmeExampleTests, MarketplaceProvenanceDisplayTests, SkillsCatalogToolTests; docs/operations.md, docs/marketplaces.md, CHANGELOG.md.
    - Each card item is in the diff: item 1 (search form, no body, no use/next, limit and order kept), item 2 (no-match line), item 3 (new second sentence of the description), item 4 (list lines and instruction), item 5 (the five tests in SearchListPlainTextTests and SkillsToolDescriptionTests), item 6 (docs/operations.md, CHANGELOG).
    - Decision: a `list skill` line gives `- <id>: <description>` only, as the card orders; the three list-skill source cases of MarketplaceProvenanceDisplayTests are deleted; the `/` command listing keeps the source.
    - next: /review
  timestamp: 2026-09-19T14:08:25.935582+00:00
- actor: claude-code
  id: 01m2x07j38jqd7dfjh3r6sepx9
  text: |
    ### test — green
    - evidence: `swift package clean && swift build --build-tests` — build is OK, 0 warnings, 0 errors. `swift test` — 742 tests in 58 suites pass, 0 failures, 0 known issues, 0 skips.
    - note: `swiftlint` and `swiftformat` show many findings across the whole code base. These findings are old. They are present in files that this task did not change (for example `MarketplaceStore.swift`). No `.swiftlint.yml` or `.swiftformat` file is in the repo root. The task text names `swift build --build-tests` and `swift test` as the commands to run. This comment does not fix the old findings, because the fix would touch almost every file in the repo and is not part of this task.
  timestamp: 2026-09-19T14:13:25.224081+00:00
depends_on:
- 01M2WWWJ05944J8A9G1VA3JM8Z
position_column: doing
position_ordinal: '80'
title: The skills search result must be plain text that names the load command
---
## What

In the SWE-bench run of 2026-09-19 07:28 in `FoundationModelsACPAgent` (instance `django__django-13447`), the result of `search skill` was one JSON object of 9,343 characters:

- It held `matches` with `id`, `description`, `parameters`, `source` and a `use` object for each skill.
- It held the body of the first match as an escaped JSON string.
- Its `next` text was: "The first skill is loaded below. If it applies to your task, you must follow it. If a different skill applies, load it with its `use` call." This text does not say what the load command is, and a JSON object has no clear "below".

The model read the result, did not load or follow a skill, and made 0 `tools.code_context` calls.

This card replaces the JSON output of card `^5q332eg` and the rule sentence of card `^cbe0fv3`.

## The work

1. **`search skill` gives plain text, with no body.** Use this form exactly. Put the query of the call in the first line, and one line for each match:

   ```
   Skills that match "explore codebase and find symbol":

   - explore: Understand how unfamiliar code works before planning or changing it …
   - code-context: Code context verbs for symbol lookup, search, grep, call graph …
   - lsp: Diagnose the language servers of the workspace …

   To load a skill, call the `skills` tool with {"op": "use skill", "id": "<id>"}.
   For example: {"op": "use skill", "id": "explore"}
   The answer is the text of the skill: the steps of the work and the tools to use.
   If a skill in this list fits your task, load it now, and do the work the way it says.
   ```

   - The example line uses the id of the first match.
   - Remove the `use` object, the `next` field and the body of the first match. There is one way to get a skill: `use skill`.
   - Keep the `limit` parameter and the order of the matches.
2. **No match:** the result is the one line "No skill matches this search." with no load instruction.
3. **The tool description uses the same command.** Replace the second sentence of the description with:

   > When a task matches a skill below, load it: call this tool with {"op": "use skill", "id": "<id>"}. The answer is the text of the skill. Do the work the way it says.

   The first sentence ("Skills are procedures for kinds of work. Each one tells you how to do the work and which tools to use.") and the catalog lines do not change.
4. **`list skill`** gives the same plain lines as the search (`- <id>: <description>`), and the same load instruction at the end.
5. **Tests.**
   - A search with matches gives exactly the form of item 1: the query line, one line for each match in rank order, and the four instruction lines, with the id of the first match in the example.
   - A search with no match gives exactly "No skill matches this search.".
   - The search result holds no body and no JSON.
   - The tool description holds the new second sentence word for word.
   - `list skill` gives the plain lines and the instruction.
6. **Documents and CHANGELOG.** `docs/operations.md` shows the new outputs. The CHANGELOG records that `search skill` and `list skill` give plain text, and that the body is no longer in the search result.

No tag, marker or wrapper is added to the text.

## Where it was found

`FoundationModelsACPAgent`, SWE-bench run of 2026-09-19 07:28, transcript `bench/preds.code-context.transcripts/django__django-13447`. Depends on the card "`use skill` must give the text of the skill…". #search #skills #cross-repo