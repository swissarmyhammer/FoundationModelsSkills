---
position_column: todo
position_ordinal: '8180'
title: Surface frontmatter decode notes as registry diagnostics
---
## What
Reopens the unfinished third of the validation-edges task: mistyped `metadata.*` extension values are noted at decode time (`Frontmatter/SkillFrontmatter.swift:315-323`, wired through `resolveExtensionField`) and correctly ignored — but the note NEVER becomes a diagnostic. `SkillValidator`'s `RuleContext` does not carry `DecodedSkill.notes`, no rule consults them, and `grep '\.notes' Sources/` matches only `Frontmatter/`. So `metadata: { preload: "true" }` produces no `.advisory` in `registry.diagnostics` — contradicting the closed task's acceptance criterion. The pre-existing top-level/`metadata.*` conflict note has the same dead end.

Fix:
- Carry decoder notes into the validator's context and emit each as an `.advisory` `SkillDiagnostic` with the skill's winning-root provenance (both the mistyped-value notes and the both-spellings conflict note).
- Update the stale doc comment at `SkillFrontmatter.swift:155-157` ("currently just the … conflict case") to describe both note kinds.

## Acceptance Criteria
- [ ] `metadata: { preload: "true" }` yields an `.advisory` in `registry.diagnostics` naming the key and expected type; skill still loads
- [ ] A field present both top-level and under `metadata.*` yields the conflict advisory in `registry.diagnostics`
- [ ] Doc comment on `SkillFrontmatter.notes` matches reality

## Tests
- [ ] Extend `Tests/FoundationModelsSkillsTests/SkillValidatorTests.swift` (or `SkillsRegistryTests`) — decode-note → diagnostic rows for both note kinds, asserting id, severity, message, provenance
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.