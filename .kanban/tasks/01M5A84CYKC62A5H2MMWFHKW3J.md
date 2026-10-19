---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: Make the skills `id` a plain string, and let the use skill corrective name the closest ids and say to call search skill
---
## What
Decision (a), from foundationmodelsacpagent-a5 on 2026-10-19. The owner wants added skills announced in a running session. The `id` enum in `SkillsCatalogTool.parameters` (`SkillsToolSchema`) is fixed when the tool is made, so the model cannot write an id that a reload added. The agents tool makes the same change for `name` (foundationmodelsagents-93, task ^x27vjcb).

- `SkillsToolSchema` makes `id` a plain string for every session. The schema is still byte-identical for the whole session.
- The live registry checks the id at call time. It already does: `registry.call` → `UnknownSkillError`.
- The unknown-id corrective of `use skill` (and of the resource operations, which share `ResourceSupport.unusableIDMessage`) names the closest visible ids and says to call `search skill`. A small model without the enum will sometimes guess an id.
- Correct the `SkillsCatalogTool` doc comment that says a hot-reload skill cannot be loaded until the next session.

## TDD: failing tests first
- [ ] the `id` field of `parameters` has no enum, for an empty catalog and a full one
- [ ] `use skill` with a skill that a reload added, after the tool was made, gives the skill text
- [ ] `use skill` with a near-miss id (for example `explor`) gives a corrective that names `explore` first and holds the `search skill` call
- [ ] the corrective lists at most N closest ids, in a stable order
- [ ] update the existing `SkillsToolSchema` and `SkillsCatalogTool` tests that pin the enum

## Acceptance
- [ ] Tests written first and seen failing, then passing; full `swift test` green #skills