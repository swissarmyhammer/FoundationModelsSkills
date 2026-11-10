---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m734nc38jehc2rew6gm02s9j
  text: |-
    Research done.
    - The fused schema takes the description of a field from the first operation that declares it (SchemaFusion). Thus `id` keeps the `use skill` text, `path` keeps the `read resource` text, and `layer` and `content` get the text of `add skill`, which is first of the three new operations.
    - ParamType has no enum case. Thus `layer` is a `.string` with the guide text, and the operation checks the value.
    - SkillsToolDescription and SkillsToolSchema do not list the operations, thus they need no change for the new operations.
    - AG-9 is not in FoundationModelsAgents yet (no `Where to write` text there). The guide text comes from this card.
    - `SkillsRegistry(roots:)` labels each root `.project`, thus a test of the default `user` layer uses `SkillsRegistry(layers:)` with a `.user` layer. The fixture registry of SkillOperationsTests is over `Examples/skill-library`; the resolver tests there must not write, thus they use correctives (an existing folder for `add`, a missing folder for `edit` and `remove`).
    - Defaults map create/new to add and remove/rm/del to delete. No default maps edit or update.
  timestamp: 2026-11-10T16:29:06.024092+00:00
- actor: claude-code
  id: 01m7359gex6axc9zv1f89n1rmr
  text: |-
    Implementation landed.
    - New: `Operations/AddSkill.swift`, `EditSkill.swift`, `RemoveSkill.swift`, and `Operations/SkillWriteSupport.swift` (the shared `layer` and `content` parameters, the check of the layer name, the sentence of a write, `SkillWriteAnswer = CorrectiveOutcome<String>`). Each operation calls `SkillWriter`; no write logic is copied.
    - Answers: ``Added the skill `x` to the user layer: `<path>`.``, ``Edited the skill `x` in the user layer: `<path>`.``, ``Removed the skill `x` from the user layer: `<folder>`.`` A bad layer gives ``The layer `global` is not valid. Give `user` or `project`, or leave it out for `user`.``
    - `SkillsTool.verbAliasOverrides`: `remove`/`delete`/`rm`/`del` → `remove`, `update` → `edit`. The defaults give `create`/`new` → `add`.
    - `PlainTextOperations` has markers for the three operations. `SkillsToolDescription` and `SkillsToolSchema` list no operations, thus no change there.
    - Existing tests changed for the new operation list: `SkillOperationsTests.fusedToolExposesExactlyTheNineCanonicalOps` and `SkillsToolAssemblyTests.expectedOperationNames`/`expectedParameterNames`. The README code block is unchanged, because `ReadmeExampleTests` compares it with its own copy.
    - TDD note: the resolver tests and the notice/endpoint tests were checked RED by a removal of the aliases and of `AddSkill` from the operation list, then GREEN after the restore. Without `AddSkill`, the endpoint test waits on the subscription until its one-minute time limit.
    - The guide text of `layer` is not changed from the card, thus no message to foundationmodelsagents-d7 is necessary.
  timestamp: 2026-11-10T16:40:05.853043+00:00
- actor: claude-code
  id: 01m7359kean123vjkabfpjdapx
  text: |-
    ### implement — changed
    - evidence: `swift test` 780 tests in 67 suites passed, 0 issues, no compiler warning from the package (only the SwiftPM `missing creator` line of the mlx bundle, which was there before). Files: Sources/FoundationModelsSkills/Operations/{AddSkill,EditSkill,RemoveSkill,SkillWriteSupport}.swift (new), SkillsTool.swift, PlainTextOperations.swift, SkillsCatalogTool.swift; Tests/FoundationModelsSkillsTests/SkillWriteOperationsTests.swift (new), SkillOperationsTests.swift, SkillsCatalogNoticeTests.swift, SkillsCatalogToolEndpointTests.swift, SkillsToolAssemblyTests.swift; docs/operations.md; README.md.
    - next: /review
  timestamp: 2026-11-10T16:40:08.906079+00:00
depends_on:
- 01M7301PF00406K3KN37EW4CHN
position_column: doing
position_ordinal: '80'
title: 'SK-6c: The skills tool gets the add, edit and remove operations with the layer option'
---
## What
Part of SK-6. Put the writes of `SkillWriter` (SK-6b) on the `skills` tool.
- Create `Sources/FoundationModelsSkills/Operations/AddSkill.swift`, `EditSkill.swift`, `RemoveSkill.swift` (operations `add skill`, `edit skill`, `remove skill`; the same verb shape as `add agent`, `edit agent`, `remove agent` of AG-9). `add skill`: `id` and `content` (the full `SKILL.md`). `edit skill`: `id`, optional `path` (default `SKILL.md`), `content`. `remove skill`: `id`. Each answer is one short plain-text sentence that names the skill, the layer and the path, or a corrective.
- Each of the three has the optional string parameter `layer`, values `user` and `project`; an absent `layer` is `user` (D175). Use this exact `@Guide` text, which is the same as the agents tool (AG-9) with `.skills` in place of `.agents`: "Optional. Where to write: user (the user folder, for all projects) or project (the .skills folder of this project). Leave it out for user." An other value gives a corrective that names the two values. If the words change, tell foundationmodelsagents-d7 so that the agents tool changes to match.
- Add the three to the `operations` list of `SkillsTool.make` (`Sources/FoundationModelsSkills/Operations/SkillsTool.swift:73-80`), after `run script`. Update the operation order in the doc comment of `make`.
- Verb aliases: `OperationResolver.defaultVerbAliases` (`../FoundationModelsExtras/Sources/Operations/OperationResolver.swift:30-32`) maps `remove`, `rm` and `del` to `delete`. Thus `remove skill` does not resolve unless `verbAliasOverrides` maps `remove`, `delete`, `rm` and `del` to `RemoveSkill.verb`. The defaults also map `create` and `new` to `add`, which is correct. Check `edit`/`update` too. Add an alias only when each literal op still resolves.
- Update `SkillsToolDescription.swift` and `SkillsToolSchema.swift` if the schema or text lists the operations. Update `PlainTextOperations.swift` so the three answers are plain text.
- Update `docs/operations.md` and `README.md` with the three operations and the `layer` option.
- No gate. The tool call card of the session shows each write (the host does this; no code here).

## Acceptance Criteria
- [x] The schema of the `skills` tool has `add skill`, `edit skill` and `remove skill`, each with `layer` (`user` | `project`) and the exact guide text above.
- [x] A call with no `layer` writes the user layer. A call with `layer: "global"` gives a corrective that names `user` and `project`, and writes nothing.
- [x] `remove skill`, `delete skill`, `rm skill` and `del skill` resolve to `RemoveSkill`.
- [x] After `add skill`, `use skill` of the new id in the same session gives its body.
- [x] One write through the tool gives exactly one catalog notice on `catalogNoticeBoard`.
- [x] After each write, a `subscription` of the `skills` endpoint of the same tool gets one change event.
- [x] `run script`, `read resource` and the other existing ops still resolve.

## Tests
- [x] `Tests/FoundationModelsSkillsTests/SkillWriteOperationsTests.swift`: drive `SkillsCatalogTool.call(arguments:)` for each op with and without `layer`, and with a bad `layer`; assert the files on disk, the answer text and the `use skill` result. Assert the guide text of `layer` in the schema.
- [x] `Tests/FoundationModelsSkillsTests/SkillsCatalogNoticeTests.swift`: one write gives exactly one notice, with a `watch: true` registry.
- [x] `Tests/FoundationModelsSkillsTests/SkillsCatalogToolEndpointTests.swift`: a write through the tool gives one change event on the `skills` endpoint.
- [x] `Tests/FoundationModelsSkillsTests/SkillOperationsTests.swift`: resolver cases for `remove`/`delete`/`rm`/`del`, `create`/`new`, and the other new verbs; the existing cases still pass.
- [x] `DocumentationTests`, `ReadmeExampleTests` and `swift test` pass with no warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1