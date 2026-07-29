---
position_column: todo
position_ordinal: a280
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