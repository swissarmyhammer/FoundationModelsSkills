---
comments:
- actor: claude-code
  id: 01m325x5sz5gja8fbvrvy52xrg
  text: |
    ### Research

    Read the Extras surface at the pinned revision `cf4be5c`
    (`.build/checkouts/FoundationModelsExtras/`). Each piece the card needs is
    there:

    - `public struct QuarantinedText` with `spans`, `init(original:)`,
      `init(spans:)`, `flattened`, the three `mappingOriginalSpans` forms
      (plain, with the preceding character, and `awaiting:`), and a `public
      struct SpanBuilder` with a `public init()`. Thus `ArgumentSubstitution`
      and `ShellInjection` need no change at all.
    - `StenciledDotfolderStack.render(_:in:)` for a `QuarantinedText` and for a
      `String`. It holds the trust rule, the partial scope rule, the bridge
      from a quarantined span to one template, the open-delimiter refusal and
      the trailing-brace move. It throws `TemplateEngineError.renderingFailed`,
      which is the error that this package gives today, thus step 5 needs no
      map: the error travels out of the call.
    - `public struct WellKnownValues` with `current(partials:)`, which takes
      the LAST `.project` layer. That is the rule of this package today.
    - `StenciledDotfolderStack` gives `TemplateEngine` an empty environment,
      thus the ladder is: well-known values, then `variables`. The environment
      rung of this package goes into `variables`, below the named arguments.

    Two constraints stand together and shape the design:

    1. Acceptance: no file of `Sources/` may name `WellKnownValues` (and a
       source-scan test must prove it). `TemplateEngineError` holds the text
       `TemplateEngine`, thus no file of `Sources/` may name that error either.
    2. Step 7: `StencilPass` needs an internal init that passes a pinned set of
       well-known values through.

    A parameter typed `WellKnownValues?` cannot meet both. Thus the internal
    init takes a factory closure that makes the stenciled stack of one render.
    The public init gives the plain factory; a test gives a factory that pins
    the well-known values. Only the test names the type.

    Three tests wire the real `StencilPass` and prove that a `{{ HOME }}` of a
    spliced value stays literal (`RenderPipelineNoRescanTests`,
    `RenderPipelineTests`, `ShellInjectionTests`). An empty environment would
    make those assertions true for the wrong reason, thus each of the three
    gives `StencilPass` the process environment.
  timestamp: 2026-09-21T14:28:48.575276+00:00
- actor: claude-code
  id: 01m326b6p5by2hhcq404ycm3w5
  text: |
    ### Decisions of the build

    **Step 1, the pin.** `Package.resolved` pins
    `cf4be5cba0862c0326183196db80754116cf753c` on branch `main`, which is the
    revision the card names. That revision holds
    `StenciledDotfolderStack.render(_:in:)` and a public `WellKnownValues`, thus
    the check passes and no update was needed.

    **Step 5, the error.** The render error that this package gives today IS
    `TemplateEngineError`, and the stenciled stack of Extras throws the same
    error. Thus the map is the identity: `StencilPass.render` lets the error
    travel out of the call, and each test that catches `TemplateEngineError`
    still catches it. The corrective text of the open-delimiter case now comes
    from Extras, together with the check that raises it.

    **The seam for a pinned well-known value.** A parameter typed
    `WellKnownValues?` would put that name in `Sources/`, which the acceptance
    criteria and the source-scan test forbid. Thus the internal initializer of
    `StencilPass` takes `makeStack`, a factory of the stenciled stack of one
    render. The public initializer gives the plain factory. `StencilPassTests`
    gives a factory that pins the values, through `@testable import`, the same
    pattern that 18 other test files of this package use.

    **The tests that moved to Extras, and are deleted here.** The bridge and the
    straddling block, the trailing brace, the splice inside an open delimiter,
    the trust of a `.defaults`/`.user`/`.project` layer, the partial that the
    nearest root wins, and the two shared-budget cases. Each one now tests the
    stenciled stack, not the wiring of this package.

    **The tests that stay, and why they changed.** Three files wire the real
    pass 3 and assert that a `{{ VAR }}` of a spliced value stays as it is. The
    pass no longer reads `ProcessInfo` on its own, thus an empty environment
    would have made each of those assertions true for the wrong reason. Each of
    the three now gives the pass `ProcessInfo.processInfo.environment`, the same
    value the registry gives it. The sentinel of the shell-output case also
    carries `{% include "no-such-partial" %}` now: this pipeline gives pass 3 no
    layer, thus a pass 3 that scanned the output of pass 2 would raise a render
    error, and the case would fail loudly.

    **What the file of the scan test covers.** `StencilLivesInExtrasTests` walks
    each Swift file under `Sources/` for `TemplateEngine`, `TemplateContext`,
    `TemplateValue` and `WellKnownValues`, and each file under
    `Sources/FoundationModelsSkills/Render/` for `FileManager`. The first name
    also keeps `TemplateEngineError` out, because that name holds it. The test
    failed with 5 issues before the work, and it passes now.

    **One comment outside the render folder.** `SeamReexports.swift` named
    `TemplateEngine` in its prose. It now names `QuarantinedText`, which this
    package's public API does name.
  timestamp: 2026-09-21T14:36:28.229386+00:00
- actor: claude-code
  id: 01m326bd4a4d2qeq8xmpfm789x
  text: |
    ### implement — changed
    - evidence: 8 files — deleted `Sources/FoundationModelsSkills/Render/QuarantinedText.swift`; rewrote `Sources/FoundationModelsSkills/Render/StencilPass.swift` (445 lines to 155); `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift` (the environment read); `Sources/FoundationModelsSkills/SeamReexports.swift` (one comment); new `Tests/FoundationModelsSkillsTests/StencilLivesInExtrasTests.swift` (the source scan, RED with 5 issues before the work); `Tests/FoundationModelsSkillsTests/StencilPassTests.swift`, `RenderPipelineNoRescanTests.swift`, `RenderPipelineTests.swift`, `ShellInjectionTests.swift`. `swift build --build-tests`: 0 warnings. `swift test`: 569 tests in 56 suites, 0 failures.
    - next: `/review`
  timestamp: 2026-09-21T14:36:34.826650+00:00
- actor: claude-code
  id: 01m326gvb2bj747pgybqwxvh8q
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` (after `swift package clean`) — build complete, 0 warnings; `swift test` — 569 tests, 56 suites, 0 failed, 0 skipped.
    - checked: `Sources/FoundationModelsSkills/Render/QuarantinedText.swift` is gone. No file under `Sources/FoundationModelsSkills/` names `TemplateEngine`, `TemplateContext`, `TemplateValue`, or `WellKnownValues`. No file under `Sources/FoundationModelsSkills/Render/` names `FileManager`.
    - trust rule tests are in place and can fail: `StencilPassTests.registryConstructedFromLabeledLayersRendersTheDefaultsRootTrustedAndOthersUntrusted` and `StencilPassTests.marketplaceLayerDrawsTheUntrustedRejectionForTheNowTag` exercise the defaults-trusted / other-layers-untrusted rule through the real `SkillsRegistry` and `StencilPass` path, with a genuine assertion on each side (a value from a trusted-only tag, and a caught `TemplateEngineError` for the untrusted case).
    - new source-scan guard `Tests/FoundationModelsSkillsTests/StencilLivesInExtrasTests.swift` enforces the ban on the Stencil-machinery names and on `FileManager` in `Render/`, and passed in the same green run.
    - no commit made, per instruction.
    - next: ready for review.
  timestamp: 2026-09-21T14:39:33.218140+00:00
- actor: claude-code
  id: 01m326pmj5wddyyae3gmwqk0p3
  text: |
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit f89027a) — 0 findings, 0 confirmed, 0 refuted; 7 validators attempted, 0 failed; 9 files reviewed, 4 `.kanban/` files excluded by `.reviewignore`.
    - note: five `code-hygiene` Swift rules declined one item each, because they found no file at `Sources/FoundationModelsSkills/Render/QuarantinedText.swift`. That file is the deletion of this change, thus the decline is correct and it is not a finding.
    - no prior `## Review Findings` section on this card, and each acceptance and test item is checked.
    - next: the card moves to Done.
  timestamp: 2026-09-21T14:42:42.885849+00:00
- actor: wballard
  id: 01m326q4c9908zh26bvkad31hw
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 9 files; StencilPass 445 lines to 155, QuarantinedText deleted
    - test: green — swift test, 569 passed, 0 warnings
    - commit: f89027a
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-21T14:42:59.081827+00:00
depends_on:
- 01M2ZDRMMGTDZCMB4ZS15QQK20
position_column: done
position_ordinal: ff8d80
title: 'Render: give Stencil and the quarantine to Extras; keep the two grammar passes of the skill format'
---
## What

**Status on 2026-09-20: not blocked.** The Extras card `^ay84ekh` is done and pushed (commit `966c1d7`): `QuarantinedText` is public, `StenciledDotfolderStack.render(_:in:)` exists for a `QuarantinedText` and for a `String`, `WellKnownValues` is a public struct, `StenciledDotfolderStack.init` has the parameter `wellKnownValues: WellKnownValues? = nil`, and `dotfolder_name` takes the last `.project` layer. The build of this package is green with the shim in place and the public `DotfolderStack.init(layers:)` of Extras resolved at the same time: the compiler prefers the initializer of this module, and reports no ambiguity. Thus the shim card is a plain cleanup, and this card does not wait for it. `Package.resolved` of this package pins the Extras revision `cf4be5c`, which is `origin/main` of `FoundationModelsExtras` (checked on 2026-09-20; `swift build` of this package is green against it). The check of step 1 passes now; run it only to confirm the pin.

The render pipeline of a skill has three passes: argument substitution, shell injection, Stencil. The first two are the schema of the skill format (`$ARGUMENTS`, `$ARGUMENTS[N]`, `$N`, `$name`, `${SKILL_DIR}`, `` !`command` `` and the fenced form, "body only, never metadata"). They stay in this package. The third is Stencil work, and this package rebuilt all of it because Extras gave no entry point: `Render/StencilPass.swift` holds a mirror of the internal `WellKnownValues` of Extras (with a `FileManager.default.currentDirectoryPath` call), a copy of the precedence ladder, a copy of the partial scope rule, a copy of the trust mapping, and the bridge from quarantined spans to one template. `Render/QuarantinedText.swift` is generic too.

This card needs the Extras card `^ay84ekh` on the `FoundationModelsExtras` board ("Render text that a consumer holds ..."): a public `QuarantinedText`, and `StenciledDotfolderStack.render(_:in:)` for a `QuarantinedText` and a layer.

1. **Check the upstream first.** Run `swift package update FoundationModelsExtras`. If the resolved revision has no `StenciledDotfolderStack.render(_:in:)` or no public `WellKnownValues`, stop, write a comment on this card, and leave it in To Do.
2. **Delete `Render/QuarantinedText.swift`.** `ArgumentSubstitution` and `ShellInjection` use the `QuarantinedText` of Extras through the same seams (`mappingOriginalSpans`, the async form, the preceding character).
3. **Make `StencilPass` thin.** For each render it makes a `StenciledDotfolderStack(base: DotfolderStack(layers: layers), variables:)` and calls `render(text, in: request.winningLayer)`. The `variables` are schema work and stay here: the named arguments of the `arguments:` frontmatter list, first occurrence wins, in agreement with `$name` of pass 1. Delete from this package: `WellKnownValues` and `current(layers:)`, the ladder merge, `partialsStack(for:)`, `resolvedTrust(for:)`, `template(for:injectingQuarantinedSpansInto:)`, `endsInsideOpenDelimiter`, `movingTrailingBraces`, and each direct use of `TemplateEngine`, `TemplateContext` and `TemplateValue`.
4. **The environment rung.** The ladder of this package today is: well-known values, then the process environment, then the named arguments. The stack of Extras keeps the environment out. Keep the behavior: put the process environment into `variables` below the named arguments. Take the environment one time from `ProcessInfo` in the registry and pass it down, so a test can give its own.
5. Map `TemplateEngineError` to the render error that this package gives today, with the same corrective text.
6. `RenderPipeline`, `RenderPass`, `ShellRenderPass`, `RenderRequest`, `RenderPolicy`, `ArgumentSubstitution`, `ShellInjection` and `NamedCaptureGroup` stay. `renderMetadata` still runs passes 1 and 3 only.
7. Tests: delete the cases of `StencilPassTests.swift` and `RenderPipelineNoRescanTests.swift` that moved to Extras with that card (trust by layer, partial scope, the bridge, the open delimiter, the trailing brace, the one budget). The kept cases that fix `hostname`, `date` and `working_directory` use the public `WellKnownValues` seam of Extras (`StenciledDotfolderStack.init(... wellKnownValues:)`) in place of `StencilPass.WellKnownValues`; give `StencilPass` an internal init that passes such a value through. Keep the cases that prove the wiring of this package: the named arguments reach Stencil, the environment rung, the marketplace layer renders untrusted, a substituted `{{ x }}` comes out verbatim end to end.

## Acceptance Criteria

- [x] `Render/QuarantinedText.swift` does not exist, and no file of `Sources/FoundationModelsSkills/` names `TemplateEngine`, `TemplateContext`, `TemplateValue` or `WellKnownValues`.
- [x] No file under `Sources/FoundationModelsSkills/Render/` names `FileManager`.
- [x] The rendered text of each skill of `Examples/skill-library` is the same as before, for the body and for the metadata fields.
- [x] `{{ dotfolder_name }}` gives the name of the highest-precedence root for a `SkillsRegistry(roots:)` with more than one root.
- [x] A skill from a `.defaults` layer renders trusted; each other layer, a marketplace layer included, renders untrusted.
- [x] A marketplace skill reads a partial from its own marketplace and from the local layers only.
- [x] A substituted argument value and a shell output that hold template syntax come out verbatim.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/StencilPassTests.swift`: `{{ name }}` gives the named argument; an environment value is below a named argument of the same name; a `.marketplace` layer refuses the `now` tag.
- [x] `Tests/FoundationModelsSkillsTests/RenderPipelineNoRescanTests.swift`: `$1` with the value `{{ secret }}` and a shell output of `{% include "x" %}` come out verbatim, through the three passes.
- [x] `Tests/FoundationModelsSkillsTests/MarketplacePartialScopeTests.swift`: passes with no change of its expected values.
- [x] `Tests/FoundationModelsSkillsTests/HotReloadTests.swift` and the use skill tests: the same rendered text as before.
- [x] A source scan test: no file under `Sources/` names `TemplateEngine` or `WellKnownValues`.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills
