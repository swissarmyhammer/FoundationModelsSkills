---
depends_on:
- 01KYNCR37A3M7MYKAH7T0QREYS
position_column: todo
position_ordinal: '8580'
title: Parsed parameter model + SkillListing (§6.1)
---
## What
Build the structured parameter model and listing row from plan §6.1.

- `Sources/FoundationModelsSkills/Listing/SkillParameter.swift` — `name`, `position` (0-based), `required`, `variadic`, `placeholder` exactly as §6.1.
- `Sources/FoundationModelsSkills/Listing/SkillListing.swift` — `id`, `displayName` (frontmatter `name`, optional for Claude-style inputs), `description`, `license`, `compatibility`, `parameters`, `acceptsTrailingArguments`.
- `Sources/FoundationModelsSkills/Listing/ParameterInference.swift` — merge three sources by position, precedence `arguments:` > `argument-hint:` > body inference:
  - `arguments:` gives authoritative names/order.
  - `argument-hint:` parsing: `<x>` required, `[x]` optional, trailing `...` variadic; contributes placeholders + optionality.
  - Body inference: scan for `$0`/`$N`/`$ARGUMENTS[N]` when neither is present; synthesize positional params.
  - `acceptsTrailingArguments` true ONLY when the body references `$ARGUMENTS` (the §5 auto-append fallback never sets it).
  - Source-mismatch diagnostics (e.g. hint arity ≠ arguments arity).

## Acceptance Criteria
- [ ] `commit` fixture yields named params with hint placeholders and correct optionality
- [ ] A body-only skill (`$0`, `$2` present) synthesizes positions 0–2 (gaps filled)
- [ ] `acceptsTrailingArguments` is false when the body lacks `$ARGUMENTS`
- [ ] Mismatched sources produce a diagnostic, not a failure

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/ParameterInferenceTests.swift` — table-driven merge matrix over all three sources; hint-grammar cases (`<a> [b] c...`)
- [ ] `Tests/FoundationModelsSkillsTests/SkillListingTests.swift` — listing snapshot for the fixture stack
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.