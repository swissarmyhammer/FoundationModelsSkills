---
depends_on:
- 01M34XXTWAM72JQ59NAMZW32K2
- 01M34XY1G0QF2AGV90WB7WA4FG
position_column: todo
position_ordinal: '8380'
title: Remove required from SkillParameter and ParameterInference
---
## What

The parameter model carries a `required` flag that nothing reads after the two cards before this one. `SkillMetadata.parameterDetails` exists only so that `use skill` could read that flag, and nothing reads the field now. Remove both.

Files:

- `Sources/FoundationModelsSkills/Listing/SkillParameter.swift`: remove the `required` property and its init parameter. The init becomes `init(name:position:variadic:placeholder:)`.
- `Sources/FoundationModelsSkills/Listing/ParameterInference.swift`: `HintToken` loses `required`. `parseHintToken(_:)` strips a well-formed `<x>` or `[x]` pair for the name and keeps the token verbatim as the placeholder; it sets no required flag. `BracketPattern` loses `required`. `mergeArgumentsWithHint(names:hintTokens:diagnostics:)` and `inferFromBody(_:)` build parameters with no `required`. Update the doc comments: the bare-token rule and the "conservative default" text go.
- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: remove `SkillMetadata.parameterDetails`, its init parameter, its doc comments, and the `parameterDetails:` argument in `metadata()`.
- `Tests/FoundationModelsSkillsTests/ParameterInferenceTests.swift`: drop `required:` from each `SkillParameter` literal. Collapse the three bare-token and optional tests into one that checks name and placeholder only.
- `Tests/FoundationModelsSkillsTests/SkillListingTests.swift`: drop `required: true` from the commit fixture assertion.
- `CHANGELOG.md`: one "Removed" entry under Unreleased for `SkillParameter.required` and `SkillMetadata.parameterDetails`.

## Acceptance Criteria

- [ ] `rg -n "required" Sources/FoundationModelsSkills/Listing Sources/FoundationModelsSkills/Registry` finds no line.
- [ ] `rg -n "required" Sources/FoundationModelsSkills/Operations/UseSkill.swift` finds only `ParamMeta(... required: ...)` schema lines.
- [ ] `rg -n "parameterDetails" Sources/ Tests/` finds no line.
- [ ] `ParameterInference.infer` for `argument-hint: "<a> [b] c..."` gives the names `a`, `b`, `c`, the placeholders verbatim, and `c` variadic.
- [ ] `rg -n "parameterDetails" CHANGELOG.md` finds a line under Unreleased.

## Tests

- [ ] `ParameterInferenceTests`: each test updated as above; one new test `hintBareOrMalformedTokenKeepsItsRawTextAsNameAndPlaceholder` over `env [env <target`.
- [ ] `SkillListingTests.commitFixtureYieldsNamedParameterWithHintPlaceholderAndTrailingArguments` updated.
- [ ] `swift test` passes with no failure and no warning.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass. #skills