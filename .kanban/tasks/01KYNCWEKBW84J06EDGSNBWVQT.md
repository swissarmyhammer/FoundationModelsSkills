---
depends_on:
- 01KYNCSXAEKDVR36H387H5TYXR
- 01KYNCVWNHA30PC3104072SJVJ
position_column: todo
position_ordinal: '8e80'
title: Skill operations + fused OperationTool (search/list/use)
---
## What
The Layer-4 model surface (plan §7): three operation structs fused into one core Tool via `FoundationModelsOperations`.

- `Sources/FoundationModelsSkills/Operations/SkillsToolContext.swift` — registry + `SkillSearchAgent`; the assembly seam (decision #15-superseded: knobs live here and in registry construction).
- `Sources/FoundationModelsSkills/Operations/SkillRow.swift` — typed outputs exactly as §7: `SkillRow`, `SearchSkillResult`, `ListSkillResult`, `UseSkillResult` (all `Encodable`).
- `Sources/FoundationModelsSkills/Operations/SearchSkill.swift` — op `"search skill"`, params `query` (req), `limit?` default 5; delegates to the search agent over the model-visible catalog; returns ranked `SkillRow`s + `total`; empty/blank query → corrective message. Hand-conform `OperationDefinition` (the macro is optional, decision #20).
- `Sources/FoundationModelsSkills/Operations/ListSkill.swift` — op `"list skill"`, `filter?` case-insensitive substring over id+description; catalog order; no session; empty match → empty list with `total: 0`, not an error.
- `Sources/FoundationModelsSkills/Operations/UseSkill.swift` — op `"use skill"`, `id` (req), `arguments?`; dereferences the LIVE registry at dispatch; §5 render; unknown/stale/model-hidden id → corrective carrying the current id list (decision #22); missing required argument (§6.1) → corrective naming it; extra trailing args ride the auto-append.
- Fuse with `OperationTool(name: "skills", description:…, context:, operations:)`; verb aliases per decision #21: `find/discover → search`, `call/run/invoke/get → use` — verify upstream's shared resolver table supplies them, add per-op alias declarations if not.
- Corrective messages, never throws (upstream's return-don't-throw + retry-cap contract).

## Acceptance Criteria
- [ ] Dispatching the three ops against a stub-searcher context returns the §7 typed outputs
- [ ] Every corrective case in the §7 table is exercised: blank query, no-match filter (empty, not corrective), unknown id (carries current ids), model-hidden id, missing required arg
- [ ] Resolver accepts `skill search`, `skills list`, `use_skill` spellings AND the #21 verb aliases: `find skill` → search, `run skill` → use (pinned by test before M6 adds `run script` — the two must stay distinct)
- [ ] The fused tool exposes exactly one core `Tool` with the flat-union schema (op enum + optional fields)

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillOperationsTests.swift` — dispatch table over a stub context (plan §13: operation dispatch against a stub context); corrective matrix; resolver-alias cases including `find skill` and `run skill`; output JSON snapshots
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.