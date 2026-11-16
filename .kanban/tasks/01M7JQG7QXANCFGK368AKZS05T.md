---
assignees:
- claude-code
position_column: done
position_ordinal: ffb380
title: Skill mutations on the skills GraphQL endpoint (D190)
---
Request from testudoapp-75 (D190, D100): the app must add, edit and remove a skill through the `skills` endpoint.

## Work
- Add `addSkill(input: AddSkillInput!)`, `updateSkill(input: UpdateSkillInput!)`, `removeSkill(input: RemoveSkillInput!)` to `SkillsGraph` (rule 7 form of EXTRAS-9).
- `AddSkillInput { id, description, body, layer }`. `UpdateSkillInput { id, description, body, layer }`: an absent field does not change. `RemoveSkillInput { id, layer }`.
- Use `SkillWriter`, the same writer as `add skill`, `edit skill` and `remove skill` of the `skills` tool.
- Add `body` and `rawDescription` to the `Skill` type, so that the app can edit the text that is on disk.
- Errors: `NOT_FOUND`, `SKILL_EXISTS`, `SKILL_READ_ONLY`, `INVALID_SKILL`.
- The write reloads the registry, thus the `changes` subscription gives one `SkillChange` for each mutation.
- Update the golden schema `Tests/Fixtures/skills.graphql` and the docs that say "no Mutation type".

## Acceptance
- Tests for each mutation, each error and the change event pass.
- `swift test` passes.