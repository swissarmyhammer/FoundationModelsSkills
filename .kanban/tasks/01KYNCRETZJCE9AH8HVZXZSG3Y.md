---
comments:
- actor: claude-code
  id: 01kypfz5k77en903qam9vhedx6
  text: |-
    Implemented via TDD per plan.md §4 / decision #27.

    - Sources/FoundationModelsSkills/Validation/SkillDiagnostic.swift: severity enum (advisory/warning/skip), Provenance (rootIndex + root URL, derivable from a DiscoveredSkill), skillID, message.
    - Sources/FoundationModelsSkills/Validation/SkillValidator.swift: ValidatedSkill (id/frontmatter/body + isModelVisibleEligible/isUserInvocableEligible/isHidden) and SkillValidator.validate(discovered:outcome:) / validate(discovered:text:) convenience. Data-driven Rule table (8 rows: name irregularities, missing/empty description, description over-limit, compatibility over-limit, partial:true, shadowed id, body>500 lines, unknown top-level keys) iterated once, each Rule pairing an `evaluate` closure with a fixed `consequence` (.none / .excludeFromModelSurface / .hide) folded into the resulting flags. Unparseable YAML (decoder .skipped) is handled as its own switch arm producing a .skip diagnostic with no ValidatedSkill.
    - Tests/FoundationModelsSkillsTests/SkillValidatorTests.swift: wrote failing tests first (confirmed RED — compile errors for missing SkillValidator/SkillDiagnostic types), then implemented to GREEN. Covers every rule individually, a combined rule-matrix table (load-anyway vs hide), and a diagnostics snapshot over the real broken/ fixtures (bad-colon-description, missing-description, name-mismatch, partial-flag) plus spec-clean, asserting exact diagnostic counts/severities/provenance.

    Discovery: broken/bad-colon-description decodes successfully via the decoder's quoting-fallback retry (name==directory, description present), so it correctly produces ZERO SkillValidator diagnostics — a good test proving decode-time retry issues are decoder-level, not validator-level.

    Dead end avoided: Swift 6 strict concurrency initially rejected the rule-table's static-let arrays of closures ("not concurrency-safe... may have shared mutable state") until RuleContext/Rule/NameCheck were marked Sendable and their closures @Sendable.

    Local review tool flagged one suggestion: collapse ValidatedSkill's three boolean flags into an enum. Did NOT apply — the task spec explicitly calls for "flags: modelVisible-eligible, userInvocable-eligible, hidden" as three named booleans, and this matches the established pattern of other public model types in this codebase (SkillFrontmatter, SkillListing) trusting direct field assignment in their memberwise inits with no invariant enforcement. The only production code path (validateDecoded) keeps the three flags mutually consistent by construction.

    swift test: 138/138 passing, 0 failures, exit 0. Adversarial double-check dispatched next per really-done.
  timestamp: 2026-07-29T08:30:59.175490+00:00
- actor: claude-code
  id: 01kypgde4q7x94enw1ya4w4mb7
  text: |-
    Adversarial double-check (round 1) found a real bug: bodyLineCountDiagnostic over-counted by one whenever the body ends in a trailing newline (the normal shape of a real SKILL.md file read from disk), because `components(separatedBy: "\n")` produces a spurious empty trailing element. A genuinely 500-line body would have been spuriously flagged as 501 lines. The existing boundary tests used `Array(...).joined(separator:)` with no trailing newline, so they never exercised this shape and could not catch it.

    Fixed: added a `lineCount(of:)` helper in SkillValidator.swift that strips exactly one trailing empty element after splitting on "\n" (guarding the empty-string case), used by bodyLineCountDiagnostic. Added two regression tests with realistic trailing-newline-terminated bodies at the 500/501 boundary (bodyAtExactlyFiveHundredLinesWithATrailingNewlineProducesNoDiagnostic, bodyOverFiveHundredLinesWithATrailingNewlineDrawsAnAdvisoryDiagnostic), verified the first would have failed pre-fix.

    Round 2 double-check re-verified the fix by hand against empty string / no-trailing-newline / one-trailing-newline / multiple-trailing-newlines cases, confirmed no over-correction in the other direction, and re-ran swift test fresh: PASS, 140/140, 0 failures.

    Final state: swift test — 140/140 passing, exit 0, run fresh in this session. Task left in `doing` per /implement's process (review column transition belongs to /review, not implement).
  timestamp: 2026-07-29T08:38:46.679462+00:00
depends_on:
- 01KYNCQK5WG7HZTYB9R5YS0SYX
- 01KYNCR37A3M7MYKAH7T0QREYS
position_column: done
position_ordinal: '8980'
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
- [x] Every rule above has a table row proving load-anyway vs skip vs hide behavior
- [x] `broken/` fixtures produce exactly the expected diagnostics with layer provenance
- [x] A skill valid under `skills-ref` produces zero diagnostics (`spec-clean` fixture)

## Tests
- [x] `Tests/FoundationModelsSkillsTests/SkillValidatorTests.swift` — table-driven rule matrix; diagnostics snapshot over the fixture stack including `broken/`
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.