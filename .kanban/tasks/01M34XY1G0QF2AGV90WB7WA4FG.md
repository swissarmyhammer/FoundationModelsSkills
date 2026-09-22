---
comments:
- actor: claude-code
  id: 01m3503d2c856rpn806sagejm3
  text: |-
    Research: `parameterSummary(parameter:)` (SkillsRegistry.swift:859) reads `placeholder`, then `variadic`, then `required`. `variadic` is set only by `ParameterInference.parseHintToken(_:)`, which always gives `placeholder: token`. Thus a variadic parameter always has a placeholder, and the variadic branch is dead. `parameterSummary` has one caller (SkillsRegistry.swift:886, `entryParameters.map(Self.parameterSummary)`). No document outside the three card files states the `<name>` form.

    TDD red: renamed the two tests and set the expectation `[target]`. `swift test --filter 'SlashCommandProvidingTests.commandWithUnhintedArgumentsSynthesizesABracketedPlaceholder'` fails with `command.argumentHint → "<target>"`.
  timestamp: 2026-09-22T16:45:04.460992+00:00
- actor: claude-code
  id: 01m350kavj8h1yfpfshme6k08r
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift (`parameterSummary` is `parameter.placeholder ?? "[\(parameter.name)]"`, doc comment rewritten), Tests/FoundationModelsSkillsTests/SlashCommandProvidingTests.swift (two renames, expectation `[target]`), CHANGELOG.md (one "Changed" entry at the top of Unreleased). `swift build` clean. `swift test --filter SlashCommandProvidingTests`: 14 tests pass. The acceptance grep finds only lines 40 and 68, both in the `parameterDetails` doc that the card excludes.
    - next: /test (full suite), then /commit and /review.
  timestamp: 2026-09-22T16:53:46.482662+00:00
- actor: claude-code
  id: 01m350mgqsb1fmdqp7paehy5td
  text: |-
    ### test — green
    - evidence: swift test — 564 tests in 53 suites passed, 0 failed, 0 skipped, 0 warnings; exit 0
    - next: /commit
  timestamp: 2026-09-22T16:54:25.273887+00:00
depends_on:
- 01M34XXTN3HQ3VFJ0KHKEZXK6C
- 01M34XXTWAM72JQ59NAMZW32K2
position_column: doing
position_ordinal: '80'
title: Synthesize a [name] placeholder for a parameter with no hint
---
## What

`SkillsRegistry.parameterSummary(parameter:)` in `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift` synthesizes `<name>` when `required` is true and `[name...]` or `[name]` when it is false. No argument is required, thus the synthesized form is always `[name]`. An authored `argument-hint:` token stays verbatim.

A variadic parameter always carries a placeholder, because `variadic` comes from a hint token only (`ParameterInference.parseHintToken(_:)`), and a hint token is always the placeholder. Thus the variadic branch of `parameterSummary` is dead: the function becomes `parameter.placeholder ?? "[\(parameter.name)]"`.

Files:

- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: `parameterSummary(parameter:)` as above. Rewrite its doc comment: "built from `required`/`variadic`" goes. Do not touch `SkillMetadata.parameterDetails`: the card after this one removes that field.
- `Tests/FoundationModelsSkillsTests/SlashCommandProvidingTests.swift`: `commandWithUnhintedArgumentsSynthesizesARequiredPlaceholder` becomes `commandWithUnhintedArgumentsSynthesizesABracketedPlaceholder` and expects `[target]`. Rename `commandWithASingleRequiredHintedParameterGetsThatPlaceholderAsItsHint` to drop "Required".
- `CHANGELOG.md`: one "Changed" entry under Unreleased: the synthesized command hint is `[name]`, never `<name>`.

This card edits two files that the slash-command card also edits, thus it depends on that card as well.

## Acceptance Criteria

- [x] A skill with `arguments: [target]` and no `argument-hint:` lists the command hint `[target]`.
- [x] A skill with `argument-hint: "<target> [mode] files..."` lists that hint verbatim.
- [x] `rg -n "required|variadic" Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift` finds no line inside `parameterSummary(parameter:)` or its doc comment.
- [x] `rg -n "\[name\]" CHANGELOG.md` finds a line under Unreleased.

## Tests

- [x] `SlashCommandProvidingTests.commandWithUnhintedArgumentsSynthesizesABracketedPlaceholder` (new expectation `[target]`).
- [x] `SlashCommandProvidingTests.commandWithMultipleHintedParametersJoinsThemInPositionOrderWithTheVariadicTailRenderedAsEllipsis` still passes.
- [x] `swift test` passes with no failure and no warning.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass. #skills