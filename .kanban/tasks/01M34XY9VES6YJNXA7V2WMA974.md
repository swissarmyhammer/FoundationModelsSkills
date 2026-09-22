---
comments:
- actor: claude-code
  id: 01m350vxefhvsqq6e9p12p8fnx
  text: |-
    Research done. The tree is clean at 8c0d98b.

    - `SkillParameter.required` has these readers: none in Sources. The Tests give it in each `SkillParameter` literal (ParameterInferenceTests.swift, SkillListingTests.swift line 39) and in one `allSatisfy` at ParameterInferenceTests.swift line 255.
    - `SkillMetadata.parameterDetails` has one writer, `SkillsRegistry.metadata()` line 887, and no reader.
    - `UseSkill.swift` has `required` only in the `ParamMeta` schema lines 81 and 83 and in prose that says no argument is required. Those lines stay.
    - `ParameterInference.swift`: `HintToken.required`, `BracketPattern.required`, `bracketPatterns`, `parseHintToken`, `mergeArgumentsWithHint` and `inferFromBody` all set the flag. The doc comments of `parseHint`, `parseHintToken`, `BracketPattern`, `mergeArgumentsWithHint` and `inferFromBody` speak of the flag and of the "conservative default".
    - CHANGELOG.md Unreleased holds three "### Changed:" entries. Each has one sentence on source compatibility, a **Cause.** paragraph and a **What changed.** list. The new entry takes the same shape with the heading "### Removed:".
  timestamp: 2026-09-22T16:58:27.663075+00:00
- actor: claude-code
  id: 01m3513nd5vefvwxn1a9hhp20r
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsSkills/Listing/SkillParameter.swift, Sources/FoundationModelsSkills/Listing/ParameterInference.swift, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Tests/FoundationModelsSkillsTests/ParameterInferenceTests.swift, Tests/FoundationModelsSkillsTests/SkillListingTests.swift, CHANGELOG.md
    - tdd: the test edits came first; `swift build --build-tests` failed with "missing argument for parameter 'required' in call"; after the code edits `swift test --filter 'FoundationModelsSkillsTests.(ParameterInferenceTests|SkillListingTests)'` passed 23 tests in 2 suites with no warning.
    - acceptance: the five `rg` checks of the card give the results the card asks for.
    - next: /test, the full `swift test`.
  timestamp: 2026-09-22T17:02:41.573304+00:00
- actor: claude-code
  id: 01m351591q9qhwn4rte9t20x8f
  text: |-
    ### test — green
    - evidence: `swift test` — 562 tests in 53 suites passed, 0 failed, 0 skipped, 0 warnings
    - next: /commit
  timestamp: 2026-09-22T17:03:34.455796+00:00
depends_on:
- 01M34XXTWAM72JQ59NAMZW32K2
- 01M34XY1G0QF2AGV90WB7WA4FG
position_column: doing
position_ordinal: '80'
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

- [x] `rg -n "required" Sources/FoundationModelsSkills/Listing Sources/FoundationModelsSkills/Registry` finds no line.
- [x] `rg -n "required" Sources/FoundationModelsSkills/Operations/UseSkill.swift` finds only `ParamMeta(... required: ...)` schema lines.
- [x] `rg -n "parameterDetails" Sources/ Tests/` finds no line.
- [x] `ParameterInference.infer` for `argument-hint: "<a> [b] c..."` gives the names `a`, `b`, `c`, the placeholders verbatim, and `c` variadic.
- [x] `rg -n "parameterDetails" CHANGELOG.md` finds a line under Unreleased.

## Tests

- [x] `ParameterInferenceTests`: each test updated as above; one new test `hintBareOrMalformedTokenKeepsItsRawTextAsNameAndPlaceholder` over `env [env <target`.
- [x] `SkillListingTests.commitFixtureYieldsNamedParameterWithHintPlaceholderAndTrailingArguments` updated.
- [x] `swift test` passes with no failure and no warning.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass. #skills