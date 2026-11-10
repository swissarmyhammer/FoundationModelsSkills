---
assignees:
- claude-code
depends_on:
- 01M7301PF00406K3KN37EW4CHN
position_column: todo
position_ordinal: '8280'
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
- [ ] The schema of the `skills` tool has `add skill`, `edit skill` and `remove skill`, each with `layer` (`user` | `project`) and the exact guide text above.
- [ ] A call with no `layer` writes the user layer. A call with `layer: "global"` gives a corrective that names `user` and `project`, and writes nothing.
- [ ] `remove skill`, `delete skill`, `rm skill` and `del skill` resolve to `RemoveSkill`.
- [ ] After `add skill`, `use skill` of the new id in the same session gives its body.
- [ ] One write through the tool gives exactly one catalog notice on `catalogNoticeBoard`.
- [ ] After each write, a `subscription` of the `skills` endpoint of the same tool gets one change event.
- [ ] `run script`, `read resource` and the other existing ops still resolve.

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillWriteOperationsTests.swift`: drive `SkillsCatalogTool.call(arguments:)` for each op with and without `layer`, and with a bad `layer`; assert the files on disk, the answer text and the `use skill` result. Assert the guide text of `layer` in the schema.
- [ ] `Tests/FoundationModelsSkillsTests/SkillsCatalogNoticeTests.swift`: one write gives exactly one notice, with a `watch: true` registry.
- [ ] `Tests/FoundationModelsSkillsTests/SkillsCatalogToolEndpointTests.swift`: a write through the tool gives one change event on the `skills` endpoint.
- [ ] `Tests/FoundationModelsSkillsTests/SkillOperationsTests.swift`: resolver cases for `remove`/`delete`/`rm`/`del`, `create`/`new`, and the other new verbs; the existing cases still pass.
- [ ] `DocumentationTests`, `ReadmeExampleTests` and `swift test` pass with no warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1