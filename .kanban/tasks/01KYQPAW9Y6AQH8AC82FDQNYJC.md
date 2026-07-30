---
comments:
- actor: claude-code
  id: 01kyr97j6f9bvg9qkrmh214y6a
  text: 'Implemented all three fixes: whitespace-only description now trims before the missing/empty check; new emptyCompatibilityDiagnostic (advisory) for an explicit compatibility: ""; mistyped metadata.* extension values (and, per review escalation, mistyped top-level `arguments:` too) now draw an advisory note and are dropped rather than silently kept or dropped-without-trace. Consolidated the five near-duplicate extension-field resolution blocks in SkillFrontmatter.init(from:) into one resolveExtensionField helper, which also fixed a real bug the consolidation surfaced (mistyped metadata.arguments was noted as ignored but still flowed through unchanged). knownTopLevelKeys now derives from specFieldKeys + ExtensionKey.allCases instead of a third hand-maintained literal list. Went through 6 review rounds fixing: isolation-marker consistency (N/A, reverted after compiler proved it wrong), arguments type-check gap, boolean-literal dedup, extension-field-block dedup + passthrough bug, top-level arguments validation + knownTopLevelKeys dedup, null-argument edge case, and final test dedup. Final review clean, 286/286 tests green.'
  timestamp: 2026-07-30T01:11:43.055363+00:00
position_column: done
position_ordinal: 9c80
title: 'Validation edges: blank description, empty compatibility, mistyped metadata.*'
---
## What
Three lenient-validation fidelity holes vs plan §4/#27:

1. **Whitespace-only `description` passes validation and stays model-visible**: the emptiness check is `== nil || == ""` (`Validation/SkillValidator.swift:358-366`), so `description: "   "` draws no diagnostic and is disclosed to the model as blank text. Fix: trim before testing emptiness (the spec's "non-empty" contract); excluded from the model surface + diagnostic, kept user-invocable — same consequence as missing.
2. **`compatibility: ""` draws no diagnostic**: the shared length helper short-circuits on empty (`SkillValidator.swift:315-323`), enforcing only the 500 upper bound, not the spec's 1-char floor. Fix: empty-string `compatibility` (and any other 1..N spec field using that helper) → advisory diagnostic, data kept.
3. **Mistyped `metadata.*` extension values are silently dropped**: type-exact accessors (`boolValue`/`stringValue`) return nil for `metadata: { preload: "true" }` or `{ argument-hint: 42 }` (`Frontmatter/SkillFrontmatter.swift:315-331`, accessors `:55-64`) — no note, no advisory, and the top-level-conflict note is suppressed when the metadata twin is mistyped (`:257-264`). Fix: when a `metadata.*` key matches an extension-field name but its value has the wrong type, record a decode note that the validator surfaces as an advisory (value still ignored — lenient posture).

## Acceptance Criteria
- [ ] `description: "  "` → diagnostic + model-surface exclusion + still user-invocable
- [ ] `compatibility: ""` → advisory diagnostic, field kept as data
- [ ] `metadata: { preload: "true" }` → advisory naming the key and expected type; skill loads
- [ ] Existing lenient-rule matrix unchanged (all current tests green)

## Tests
- [ ] Extend `Tests/FoundationModelsSkillsTests/SkillValidatorTests.swift` — whitespace-description and empty-compatibility rows
- [ ] Extend `FrontmatterDecoderTests` — mistyped metadata.* advisory rows
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.