---
comments:
- actor: claude-code
  id: 01kyrkcpvfsv88d5r0ft61ywmj
  text: |-
    Implemented both §6.1 fixes:

    1. `SkillsRegistry.buildCatalog(layers:)` now calls `ParameterInference.infer(frontmatter:body:)` for every non-hidden validated skill and folds each diagnostic string into `SkillDiagnostic(severity: .advisory, skillID:, provenance:, message:)`, reusing the same `Provenance(discovered:)` idiom `validate(discovered:diagnostics:)` already uses. Corrected the stale `SkillListing.swift` doc comment (it claimed the registry already did this) to name the actual fold site.
    2. Added `SkillsRegistry.menuDescriptionMaxLength = 200` and `truncatedForMenu(_:)` (breaks on the last word boundary at/before the limit, appends "…"); `listing(for:)` now truncates through it. `metadata()` is untouched and stays full-length.

    Added to `SkillsRegistryTests.swift`: an arity-mismatch fixture proving the new diagnostic names the skill and cites both `arguments:`/`argument-hint:`; a >200-char fixture proving `commandListing()` truncates while `metadata()` stays full-length; a boundary fixture (exactly 200 chars) proving no truncation at the limit.

    `swift build --build-tests` clean; `swift test` 314/314 passed. Committing checkpoint next.
  timestamp: 2026-07-30T04:09:17.423226+00:00
position_column: doing
position_ordinal: '80'
title: 'Listing fidelity: surface parameter-mismatch diagnostics, truncate menu descriptions'
---
## What
Two §6.1 listing-surface gaps:

1. **Parameter source-mismatch diagnostics are computed then dropped** (§6.1: "Diagnostics flag mismatches between sources"): `ParameterInference.Result.diagnostics` is produced (`Listing/ParameterInference.swift:106-111`) but every consumer discards it — `SkillListing.init` ignores it (`SkillListing.swift:92-100`) and `SkillsRegistry` feeds its diagnostics surface from the validator only (`SkillsRegistry.swift:139-141, 428-444`). The comment at `SkillListing.swift:82-85` claims the registry folds them in — it does not. Fix: plumb inference diagnostics into `SkillsRegistry.diagnostics` with skill id + winning-root provenance; correct or remove the stale comment.
2. **Menu descriptions are never truncated** (§6.1: `description: String? // rendered, truncated for the menu`): `SkillsRegistry` renders with no cap (`SkillsRegistry.swift:624-630`). Fix: truncate `commandListing()` descriptions to a sane menu length (pick a constant, e.g. 200 chars on a word boundary + ellipsis); `metadata()`/model rows stay full-length.

## Acceptance Criteria
- [ ] A fixture with `arguments:` arity ≠ `argument-hint:` arity produces a registry diagnostic naming the skill and the mismatch
- [ ] A >200-char description is truncated in `commandListing()` but full-length in `metadata()`
- [ ] Stale folding comment corrected

## Tests
- [ ] Extend `Tests/FoundationModelsSkillsTests/SkillsRegistryTests.swift` — mismatch-diagnostic case; truncation boundary cases
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.