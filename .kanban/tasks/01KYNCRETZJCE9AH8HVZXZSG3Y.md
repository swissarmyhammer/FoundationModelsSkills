---
depends_on:
- 01KYNCQK5WG7HZTYB9R5YS0SYX
- 01KYNCR37A3M7MYKAH7T0QREYS
position_column: todo
position_ordinal: '8480'
title: Lenient validation + diagnostics (skills-ref parity)
---
## What
Domain validation per plan §4 and decision #27 — the lenient posture of the agentskills.io client-implementation guide, parity target `skills-ref validate`.

- `Sources/FoundationModelsSkills/Validation/SkillDiagnostic.swift` — diagnostic type: severity (advisory/warning/skip), skill id, winning-layer provenance, message.
- `Sources/FoundationModelsSkills/Validation/SkillValidator.swift` — rules over `DecodedSkill`:
  - `name` rules (1–64 chars, `[a-z0-9-]`, no leading/trailing/consecutive hyphens, `name == directoryName`) → diagnostic, LOAD ANYWAY.
  - `description` required, 1–1024 chars → missing/empty ⇒ diagnostic + excluded from the model surface, kept user-invocable (our one softening of the guide's skip rule).
  - `compatibility` 1–500 chars → over-limit is a warning, data kept.
  - Unparseable YAML (skip result from the decoder) → skip + diagnostic.
  - `partial: true` → diagnostic + hidden from every surface (decision #29 retirement).
  - Shadowed id (from discovery) → advisory. `SKILL.md` body over 500 lines → advisory.
  - Unknown top-level keys → advisory only.
- Output: `ValidatedSkill` (frontmatter + body + flags: modelVisible-eligible, userInvocable-eligible, hidden) + `[SkillDiagnostic]`.

## Acceptance Criteria
- [ ] Every rule above has a table row proving load-anyway vs skip vs hide behavior
- [ ] `broken/` fixtures produce exactly the expected diagnostics with layer provenance
- [ ] A skill valid under `skills-ref` produces zero diagnostics (`spec-clean` fixture)

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillValidatorTests.swift` — table-driven rule matrix; diagnostics snapshot over the fixture stack including `broken/`
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.