---
depends_on:
- 01M34XXTN3HQ3VFJ0KHKEZXK6C
- 01M34XXTWAM72JQ59NAMZW32K2
position_column: todo
position_ordinal: '8280'
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

- [ ] A skill with `arguments: [target]` and no `argument-hint:` lists the command hint `[target]`.
- [ ] A skill with `argument-hint: "<target> [mode] files..."` lists that hint verbatim.
- [ ] `rg -n "required|variadic" Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift` finds no line inside `parameterSummary(parameter:)` or its doc comment.
- [ ] `rg -n "\[name\]" CHANGELOG.md` finds a line under Unreleased.

## Tests

- [ ] `SlashCommandProvidingTests.commandWithUnhintedArgumentsSynthesizesABracketedPlaceholder` (new expectation `[target]`).
- [ ] `SlashCommandProvidingTests.commandWithMultipleHintedParametersJoinsThemInPositionOrderWithTheVariadicTailRenderedAsEllipsis` still passes.
- [ ] `swift test` passes with no failure and no warning.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass. #skills