---
position_column: todo
position_ordinal: '9580'
title: 'Render: give Stencil and the quarantine to Extras; keep the two grammar passes of the skill format'
---
## What

The render pipeline of a skill has three passes: argument substitution, shell injection, Stencil. The first two are the schema of the skill format (`$ARGUMENTS`, `$ARGUMENTS[N]`, `$N`, `$name`, `${SKILL_DIR}`, `` !`command` `` and the fenced form, "body only, never metadata"). They stay in this package. The third is Stencil work, and this package rebuilt all of it because Extras gave no entry point: `Render/StencilPass.swift` holds a mirror of the internal `WellKnownValues` of Extras (with a `FileManager.default.currentDirectoryPath` call), a copy of the precedence ladder, a copy of the partial scope rule, a copy of the trust mapping, and the bridge from quarantined spans to one template. `Render/QuarantinedText.swift` is generic too.

This card needs the Extras card `^ay84ekh` on the `FoundationModelsExtras` board ("Render text that a consumer holds ..."): a public `QuarantinedText`, and `StenciledDotfolderStack.render(_:in:)` for a `QuarantinedText` and a layer.

1. **Check the upstream first.** Run `swift package update FoundationModelsExtras`. If the resolved revision has no `StenciledDotfolderStack.render(_:in:)`, stop, write a comment on this card, and leave it in To Do.
2. **Delete `Render/QuarantinedText.swift`.** `ArgumentSubstitution` and `ShellInjection` use the `QuarantinedText` of Extras through the same seams (`mappingOriginalSpans`, the async form, the preceding character).
3. **Make `StencilPass` thin.** For each render it makes a `StenciledDotfolderStack(base: DotfolderStack(layers: layers), variables:)` and calls `render(text, in: request.winningLayer)`. The `variables` are schema work and stay here: the named arguments of the `arguments:` frontmatter list, first occurrence wins, in agreement with `$name` of pass 1. Delete from this package: `WellKnownValues` and `current(layers:)`, the ladder merge, `partialsStack(for:)`, `resolvedTrust(for:)`, `template(for:injectingQuarantinedSpansInto:)`, `endsInsideOpenDelimiter`, `movingTrailingBraces`, and each direct use of `TemplateEngine`, `TemplateContext` and `TemplateValue`.
4. **The environment rung.** The ladder of this package today is: well-known values, then the process environment, then the named arguments. The stack of Extras keeps the environment out. Keep the behavior: put the process environment into `variables` below the named arguments. Take the environment one time from `ProcessInfo` in the registry and pass it down, so a test can give its own.
5. Map `TemplateEngineError` to the render error that this package gives today, with the same corrective text.
6. `RenderPipeline`, `RenderPass`, `ShellRenderPass`, `RenderRequest`, `RenderPolicy`, `ArgumentSubstitution`, `ShellInjection` and `NamedCaptureGroup` stay. `renderMetadata` still runs passes 1 and 3 only.
7. Tests: delete the cases of `StencilPassTests.swift` and `RenderPipelineNoRescanTests.swift` that moved to Extras with that card (trust by layer, partial scope, the bridge, the open delimiter, the trailing brace, the one budget). Keep the cases that prove the wiring of this package: the named arguments reach Stencil, the environment rung, the marketplace layer renders untrusted, a substituted `{{ x }}` comes out verbatim end to end.

## Acceptance Criteria

- [ ] `Render/QuarantinedText.swift` does not exist, and no file of `Sources/FoundationModelsSkills/` names `TemplateEngine`, `TemplateContext`, `TemplateValue` or `WellKnownValues`.
- [ ] No file under `Sources/FoundationModelsSkills/Render/` names `FileManager`.
- [ ] The rendered text of each skill of `Examples/skill-library` is the same as before, for the body and for the metadata fields.
- [ ] A skill from a `.defaults` layer renders trusted; each other layer, a marketplace layer included, renders untrusted.
- [ ] A marketplace skill reads a partial from its own marketplace and from the local layers only.
- [ ] A substituted argument value and a shell output that hold template syntax come out verbatim.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/StencilPassTests.swift`: `{{ name }}` gives the named argument; an environment value is below a named argument of the same name; a `.marketplace` layer refuses the `now` tag.
- [ ] `Tests/FoundationModelsSkillsTests/RenderPipelineNoRescanTests.swift`: `$1` with the value `{{ secret }}` and a shell output of `{% include "x" %}` come out verbatim, through the three passes.
- [ ] `Tests/FoundationModelsSkillsTests/MarketplacePartialScopeTests.swift`: passes with no change of its expected values.
- [ ] `Tests/FoundationModelsSkillsTests/HotReloadTests.swift` and the use skill tests: the same rendered text as before.
- [ ] A source scan test: no file under `Sources/` names `TemplateEngine` or `WellKnownValues`.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills #blocked-upstream
