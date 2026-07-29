---
position_column: todo
position_ordinal: 9c80
title: 'UseSkill required-arg check: use SkillParameter.required, not placeholder text'
---
## What
Variance from §7/§6.1: the missing-required-argument corrective must come from the STRUCTURED §6.1 model, but `UseSkill.firstMissingRequiredParameterName` re-derives requiredness from the rendered placeholder's first character (anything not starting with `[` = required — `Operations/UseSkill.swift:200-206`, self-documented at `:184-193`). `SkillParameter.required` exists (`Listing/SkillParameter.swift:49`) but `SkillsRegistry.parameterSummary` flattens it away (`Registry/SkillsRegistry.swift:571-575`), passing raw `argument-hint:` text through. A skill with `argument-hint: "env"` (no brackets) is misclassified as required.

Fix: carry the structured `[SkillParameter]` (or at least name+required+variadic) through `SkillMetadata`/the ops context alongside the display summary, and make `UseSkill` consult `required` directly. Display strings remain for `SkillRow.parameters`.

## Acceptance Criteria
- [ ] A skill whose hint is unbracketed text with a satisfied/absent optional arg dispatches without a bogus missing-argument corrective
- [ ] A genuinely missing required parameter still draws the corrective naming it
- [ ] `SkillRow.parameters` display output unchanged (existing snapshots green)

## Tests
- [ ] Extend `Tests/FoundationModelsSkillsTests/SkillOperationsTests.swift` — unbracketed-hint matrix (required flag from `arguments:` vs hint-only vs body-inferred)
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.