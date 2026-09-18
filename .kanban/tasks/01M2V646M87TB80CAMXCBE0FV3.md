---
comments:
- actor: claude-code
  id: 01m2v6v8pv72av3be6jgbj7z5f
  text: |-
    Research (implement):
    - The factories `SkillsTool.make(registry:session:...)` and `SkillsTool.make(registry:embedder:...)` in `Operations/SkillsToolAssembly.swift` return `OperationTool<SkillsToolContext>`. `make(context:)` in `Operations/SkillsTool.swift` gives a fixed description "Search, list, and use skills from the local skill library."
    - The Extras `OperationTool` gets its schema only from `SchemaFusion.fuse`. That function does not read `ParamMeta.allowedValues` (a documented decision in Extras), and `ParamMeta` is static on each operation type. Thus the Extras API cannot give an `id` enum, and a factory that returns `OperationTool` cannot give another schema or `nil`.
    - The four operations `use skill`, `list resource`, `read resource` and `run script` all use the same fused `id` field, and each one takes a skill id. Thus one enum on `id` is correct for all of them.
    - plan.md decisions #18 and #22 say "no dynamic id enum". This card reverses that, thus plan.md must record the change.
    - ACPAgent `ToolCatalog.makeSkillsTool` returns `(any FoundationModels.Tool)?`, thus an optional return from the factory compiles there with no change, and `nil` means "do not register".

    Decisions (made by the implementer, as the coordinator asked):
    1. Work stays in this tree (no Extras change). A new public `SkillsCatalogTool: Tool` wraps the `OperationTool`. It gives its own fused schema (same `op` enum and same field union as the Extras fusion), where `id` is an enum of the visible skill ids. It forwards `call`, `operations`, `forked()` and `OperationDescribing`.
    2. The two registry factories return `SkillsCatalogTool?`. They return `nil` when no skill is visible. This breaks host source; the CHANGELOG records it.
    3. `make(context:)` stays the low-level door and still returns `OperationTool`. It now also takes its description from the catalog of the context (visible skills), so each door gets the catalog and the use rule. The wrapper schema has no root description, thus the catalog is not in the prompt two times.
    4. The catalog list has a budget of 8,000 characters (the Codex value when the context window is not known). Over the budget: shorten each description to one common length (not below a minimum), then give the remaining skills by id only on one line, then drop ids, and add a note that `search skill` finds the others.
    5. The word-break truncation of `SkillsRegistry.truncatedForMenu` moves to one shared `String` helper, so the menu and the catalog use one function.
  timestamp: 2026-09-18T21:30:33.563404+00:00
- actor: claude-code
  id: 01m2v7fvszt9eay400sq6y5xtt
  text: |-
    Implementation landed. It follows the decisions of the card author (session foundationmodelsacpagent-08). These replace decision 2 of my earlier comment: no factory returns `nil`.

    - New `SkillsCatalogTool` (public `Tool`, `ForkableTool`, `OperationDescribing`). It wraps `OperationTool<SkillsToolContext>` (`operationTool`), forwards `call`, `perform`, `operations` and `operationDescriptors`, and has its own schema from the new internal `SkillsToolSchema`. That schema is the same flat union as the Extras fusion, except that `id` is an enum of the visible ids. With no visible skill, `id` stays a plain string. The schema root has no description.
    - Every `SkillsTool.make` overload returns `SkillsCatalogTool`, and has `catalogCharacterLimit: Int = SkillsTool.defaultCatalogCharacterLimit` (8_000). `make(context:catalogCharacterLimit:)` reads `context.registry.metadata()` filtered by `context.visibilityPredicate` one time, and builds the description with the new internal `SkillsToolDescription`. The steps are (a) full, (b) `SkillsRegistry.truncatedForMenu` (now internal, not private; 200 characters), (c) one comma-separated id line, (d) the ids that fit plus "<N> more skills are not listed. Find them with `search skill`." The fixed sentences are never cut.
    - My reading of author item 5: with no visible skill, the description is "Skills are procedures for kinds of work." + newline + "No skills are installed now." (the first sentence only, word for word).
    - Operation texts and the `id` parameter text are changed as the author wrote them.
    - `SkillsCLI` gives `tool.operationTool` to `OperationCLIDriver`. The demo `makeTool` returns `SkillsCatalogTool`. ACPAgent `ToolCatalog.makeSkillsTool` returns `(any Tool)?`, thus it compiles with no change.
    - Docs: `docs/operations.md` (new section on the description, the enum, and hot reload), README, CHANGELOG (with `catalogCharacterLimit`), plan.md (amendments to decision #22, the §7 id bullet, and the reload paragraph).
    - Tests: new `SkillsToolDescriptionTests` (6 cases: steps a–d, one line, no skill) and `SkillsCatalogToolTests` (7 cases: description, limit, enum, op enum and field union, no skill, dispatch, op texts). I checked two mutants: with the enum off, and with step (b) skipped, the tests fail.
    - Existing test helpers now name `SkillsCatalogTool` in place of `OperationTool<SkillsToolContext>`. The HotReloadTests step-5 text now says that the schema is fixed when the tool is made.
    - Full suite: `swift test`, 735 tests in 56 suites pass. The build has no warnings.

    A process note: I made one edit to `SkillsToolAssembly.swift` with a python script, not with the edit tool. The build and the tests cover the result.
  timestamp: 2026-09-18T21:41:48.479745+00:00
- actor: claude-code
  id: 01m2v7g0fab05h8q1m3sdhzzx0
  text: |-
    ### implement — changed
    - evidence: 3 new source files (Operations/SkillsCatalogTool.swift, Operations/SkillsToolDescription.swift, Operations/SkillsToolSchema.swift); 7 changed source files (SkillsTool.swift, SkillsToolAssembly.swift, UseSkill.swift, SearchSkill.swift, ListSkill.swift, CLI/SkillsCLI.swift, Registry/SkillsRegistry.swift); 1 changed demo file (Examples/skills-demo/SkillsDemoAssembly.swift); 2 new test files (SkillsCatalogToolTests.swift, SkillsToolDescriptionTests.swift); 8 changed test files; 4 changed docs (README.md, CHANGELOG.md, docs/operations.md, plan.md). `swift test`: 735 tests in 56 suites pass, 0 warnings.
    - next: /review
  timestamp: 2026-09-18T21:41:53.258825+00:00
- actor: claude-code
  id: 01m2v7rj2w9pmbxbt1vpygkjhr
  text: |-
    ### test — green
    - evidence: swift build (clean rebuild) — 0 warnings, 0 errors; swift build --build-tests — 0 warnings; swift test — 735 tests, 56 suites, 0 failed, 0 skipped
    - next: no action needed. Board can move this task forward.
  timestamp: 2026-09-18T21:46:33.436451+00:00
position_column: doing
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