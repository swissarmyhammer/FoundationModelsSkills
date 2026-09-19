---
depends_on:
- 01M2WWWJ05944J8A9G1VA3JM8Z
position_column: todo
position_ordinal: '8180'
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