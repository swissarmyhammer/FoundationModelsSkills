---
position_column: todo
position_ordinal: '80'
title: The skills tool must show its catalog and a use rule in its description, and give plain operation texts
---
## What

In the SWE-bench run of 2026-09-18 15:42 in `FoundationModelsACPAgent` (instance `django__django-13447`), the model searched for a skill but never loaded one. These are the texts of the `skills` tool as the model got them:

| Part | Text | Problem |
|---|---|---|
| Tool description | "Search, list, and use skills from the local skill library." | It does not say what a skill is, or that a skill that applies must be followed. The model does not see which skills exist. |
| `search skill` | "Search the skill library by query, returning ranked matches best-first." | It does not say what to search for. The model searched by the topic of the issue ("build app dict admin views"). |
| `use skill` | "Render and return a skill's body by id, substituting the given arguments." | It describes the inside of the tool, not what the model gets: a procedure to follow. |
| `id` | "The skill id to use." (any string) | The model cannot see the valid ids. |

## What other systems do

- The Agent Skills standard shows the catalog (name and description of each skill, approximately 50 to 100 tokens per skill) before the model plans. One of the two standard places is the description of the activation tool, which "naturally couples discovery with activation". Its suggested rule: "When a task matches a skill's description, call the activate_skill tool with the skill's name to load its full instructions." Source: https://agentskills.io/client-implementation/adding-skills-support
- Codex lists the skills at the start, limited to 2% of the context window (8,000 characters when the window is not known). When the list is too long, it shortens the descriptions first, then omits skills with a warning.
- The standard recommends that the skill name parameter is an enum of the valid names, so the model cannot invent a name.

## The work

1. **The tool description is made from the catalog when the tool is made.** It has three parts:
   - What a skill is: a procedure for a kind of work.
   - The rule: "When a task matches a skill below, you must load that skill with `use skill` and follow its instructions before you do the work."
   - Each visible skill: its id and its description.
   The list has a size limit, as in Codex. When the catalog is larger than the limit, shorten the descriptions first, then list the rest by id only, and say that `search skill` finds the others. The text comes from the registry, not from a fixed list.
2. **New operation texts.**
   - `use skill`: "Load the instructions of a skill. Follow them."
   - `search skill`: "Find the skills for the kind of work that you will do next, for example explore code, find callers, or run tests. Search by the kind of work, not by the topic of the task."
   - `list skill`: say that it gives each skill with its description.
3. **`id` is an enum** of the visible skill ids in the fused schema. When no skill is visible, do not register the tool.
4. **Hot reload.** A tool description is fixed when a session is made. A skill that is added during a session is found by `search skill`, and the next session gets it in the description. Write this in the documents.
5. **Tests.**
   - The description holds each visible id with its description, and no hidden id.
   - The size limit shortens descriptions first, and then lists ids only.
   - The `id` schema is an enum of the visible ids.
6. **Documents and CHANGELOG** for the new description and the enum.

No tag or wrapper is added around the body that `use skill` gives.

Card `^5q332eg` (the `use` call and the `next` rule in the search result) is separate. It stays for the search path.

## Where it was found

`FoundationModelsACPAgent`, SWE-bench run of 2026-09-18 15:42, transcript `bench/preds.code-context.transcripts/django__django-13447`. #search #cross-repo