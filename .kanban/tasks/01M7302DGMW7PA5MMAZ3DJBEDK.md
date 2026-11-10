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
- actor: claude-code
  id: 01m735gwfqe81easvfk49v4c1y
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (76393d0); 5 findings (5 confirmed, 6 refuted) — Tests/FoundationModelsSkillsTests/SkillsCatalogNoticeTests.swift:93, Tests/FoundationModelsSkillsTests/SkillsCatalogToolEndpointTests.swift:158 (x2), Tests/FoundationModelsSkillsTests/SkillsCatalogToolEndpointTests.swift:168 (x2)
    - next: implement the open items of "Review Findings (2026-11-10 10:40)". Put the cursor read and the change-event read in one shared test support file. Put the one-notice check in one helper that takes the trigger.
  timestamp: 2026-11-10T16:44:07.543409+00:00
- actor: claude-code
  id: 01m735hdv75sn2rydvnhkcneqj
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 14 files
    - test: green — swift test, 780 passed in 67 suites, 0 warnings
    - commit: 76393d0
    - review: findings — Tests/FoundationModelsSkillsTests/SkillsCatalogNoticeTests.swift:93, Tests/FoundationModelsSkillsTests/SkillsCatalogToolEndpointTests.swift:158 (x2), Tests/FoundationModelsSkillsTests/SkillsCatalogToolEndpointTests.swift:168 (x2)
  timestamp: 2026-11-10T16:44:25.319346+00:00
- actor: claude-code
  id: 01m735teg4qzwwb7kj75gsdbk1
  text: |-
    Review findings of 2026-11-10 10:40 are fixed.
    - New `Tests/FoundationModelsSkillsTests/GraphQLTestSupport.swift`: `object(_:)`, `data(of:)`, `codes(of:)`, `changeEvent(in:)`, `cursor(of:)`. Both `SkillsGraphChangesTests` and `SkillsCatalogToolEndpointTests` use it. `SkillsGraphChangesTests` lost its private `ResponseText` and `ChangeEvent.event(in:)`; `Endpoint.cursor()` forwards to the shared helper. The endpoint suite lost its private `cursor(of:)`, `changeEvent(in:)` and `data(of:)`.
    - `SkillsCatalogNoticeTests`: new private `expectExactlyOneNotice(on:after:)` takes the trigger as a closure. The two tests call it, thus the four-argument `expectExactlyOneEvent` call is written once.
    - Discovery: the first full run failed the `edit` and `remove` cases of `eachWriteThroughTheToolGivesOneChangeEventOnTheEndpoint`. `SkillChangeFeed` appends events on its own task, thus the cursor read after the setup `add` can come before the event of that add, and the subscription then gave the add event. The previous run passed by chance. The test now subscribes from the first cursor before the setup `add`, and reads the add event from the stream; no poll, no time value.
    - Do not run `swift format` with no configuration: the default is 2 spaces and 100 columns, and it keeps the line breaks it adds. Use a configuration with `lineLength: 120` and `indentation.spaces: 4`.
  timestamp: 2026-11-10T16:49:20.900965+00:00
- actor: claude-code
  id: 01m735tgs9cg647qajgcfvnfcq
  text: |-
    ### implement — changed
    - evidence: `swift test` 780 tests in 67 suites passed, 0 issues, no compiler warning (only the SwiftPM `missing creator` line of the mlx bundle, which was there before). Files: Tests/FoundationModelsSkillsTests/GraphQLTestSupport.swift (new), SkillsCatalogNoticeTests.swift, SkillsCatalogToolEndpointTests.swift, SkillsGraphChangesTests.swift. Findings: 5 of 5 checked.
    - next: /review
  timestamp: 2026-11-10T16:49:23.241041+00:00
- actor: claude-code
  id: 01m735wsjrkecngkyekxwrpnzw
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (e6864ec): 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed. All 5 prior findings are checked.
    - next: none. The task is in done.
  timestamp: 2026-11-10T16:50:37.784837+00:00
- actor: claude-code
  id: 01m735x2ese6b9gsqfkkf8eq0r
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 4 test files
    - test: green — swift test, 780 passed in 67 suites, 0 warnings
    - commit: e6864ec
    - review: clean — 0 findings; task in done
  timestamp: 2026-11-10T16:50:46.873778+00:00
depends_on:
- 01M7301PF00406K3KN37EW4CHN
position_column: done
position_ordinal: ffac80
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

## Review Findings (2026-11-10 10:40)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 12 file(s) reviewed, 4 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file
> - `docs/operations.md` — no validator matches this file

- [x] `Tests/FoundationModelsSkillsTests/SkillsCatalogNoticeTests.swift:93` `duplication/duplication` — The new test `oneWriteThroughTheToolOfAWatchedRegistryPostsExactlyOneNotice` repeats the `expectExactlyOneEvent` argument list from the test just above it. The only difference is the trigger. The argument list is the same: `countGetter`, `since: 0`, `signalTimeout`, and `settleWindow`. Move the repeated check into a helper that takes the trigger as a closure, for example `expectOneNoticeAfter(session:, trigger:)`. Both tests then call it with their own trigger, and the four-argument call is written once.
- [x] `Tests/FoundationModelsSkillsTests/SkillsCatalogToolEndpointTests.swift:158` `duplication/duplication` — The new private helper `cursor(of:)` repeats the body of `Endpoint.cursor()` in SkillsGraphChangesTests.swift. Both send the query `{ cursor }`, read `data`, and read the `cursor` field. The two copies can drift apart. Move the cursor query into one shared test helper that both suites call, and delete the copy this change added. Editing SkillsGraphChangesTests.swift to use the shared helper is a separate task, because that file is outside this change. Within this change, the new suite should call the shared helper and not keep its own copy.
- [x] `Tests/FoundationModelsSkillsTests/SkillsCatalogToolEndpointTests.swift:158` `reuse/reuse` — The new private static `cursor(of:)` helper repeats the logic of the existing `cursor()` helper on the endpoint in SkillsGraphChangesTests. Two copies of the same GraphQL cursor read can drift apart. Move the cursor read into one shared test helper, for example in a support file, and call it from both suites. Or make the existing `Endpoint.cursor()` reachable from here and drop this copy.
- [x] `Tests/FoundationModelsSkillsTests/SkillsCatalogToolEndpointTests.swift:168` `duplication/duplication` — The new helper `changeEvent(in:)` repeats the logic of the private `ChangeEvent.event(in:)` in SkillsGraphChangesTests.swift. Both read the `data` object and then the `changes` object of a subscription response. Put the response-to-event read in one shared test helper, and have both suites call it. The `ChangeEvent.event` copy is `private`, so this suite cannot call it as it stands. Move the helper to shared test support, and make the change to SkillsGraphChangesTests.swift a separate task.
- [x] `Tests/FoundationModelsSkillsTests/SkillsCatalogToolEndpointTests.swift:168` `reuse/reuse` — The new `changeEvent(in:)` helper repeats the event-reading logic of the existing `ChangeEvent.event(in:)` helper in SkillsGraphChangesTests. It parses the same `changes` field from a subscription response. Share one subscription-event parser between the two suites, in a common test support file. Keep only one copy.
