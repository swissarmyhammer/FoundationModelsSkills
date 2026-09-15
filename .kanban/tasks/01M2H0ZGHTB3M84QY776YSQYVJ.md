---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2jw7nye16rhq0r2cy4ayh8n
  text: |-
    Research: `StencilPass.render(_:request:)` made the engine with `Self.partialsStack(layers: layers)`, which gave every layer to `DotfolderLoader`. `SkillsRegistry.init(layers:)` gives all layers to the pass, and the render request carries the layer that won, so the scope rule needs no new plumbing.

    marketplace.md §6.5 fixes the order as `url[k]._partials < defaults < user < project`. Thus the marketplace layer that won goes first (lowest precedence), and the local layers keep their order after it. A local skill gets the local layers only.

    TDD: the new suite failed first for the correct cause. The skill of marketplace A rendered "header from marketplace B", and the local skill rendered B's text in place of an error.
  timestamp: 2026-09-15T15:51:10.542936+00:00
- actor: claude-code
  id: 01m2jwc6e3f07az5v6vtv7c8kz
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsSkills/Render/StencilPass.swift (replaced `partialsStack(layers:)` with the instance method `partialsStack(for winningLayer:)`, and the render makes the engine with it), Tests/FoundationModelsSkillsTests/MarketplacePartialScopeTests.swift (new, 3 cases). `swift build --build-tests`: no warning, no error. `swift test --filter "MarketplacePartialScopeTests|StencilPassTests"`: 26 tests, 2 suites, all pass. `swift test`: 553 tests, 40 suites, all pass.
    - next: /review
  timestamp: 2026-09-15T15:53:38.499694+00:00
- actor: claude-code
  id: 01m2jwkys0k7kvxyb7s2hcf2n2
  text: |
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (1d834c4), 0 findings, 0 confirmed, 0 refuted, 7 validator runs, 0 failed. 2 files reviewed; 4 `.kanban/` files excluded by `.reviewignore`.
    - next: task moved to done. Every checklist item and every acceptance criterion is checked.
  timestamp: 2026-09-15T15:57:52.800609+00:00
- actor: claude-code
  id: 01m2jwmb1jjtx2n725hk9yfet3
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files (Render/StencilPass.swift, Tests/FoundationModelsSkillsTests/MarketplacePartialScopeTests.swift)
    - test: green — swift build --build-tests 0 warnings; swift test x2, 553 passed each run, 0 failed, 0 skipped
    - commit: 1d834c4 feat(render): scope partials to the winning marketplace
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-15T15:58:05.362490+00:00
depends_on:
- 01M2H0PTG2XXMYBQX8BB3E76AX
position_column: done
position_ordinal: ce80
title: Scope Stencil partials to the winning marketplace plus the local layers
---
## What

marketplace.md §6.5 and decision 9. Today `StencilPass` builds one partials stack from all layers (`StencilPass.partialsStack(layers:)`, used where `StencilPass` builds its `TemplateEngine`). A skill from marketplace A can then include a partial from marketplace B.

Change `StencilPass` (`Sources/FoundationModelsSkills/Render/StencilPass.swift`) so the partials stack depends on the winning layer of the render (`RenderRequest.winningLayer`):
- A skill from a `.marketplace` layer: `[that marketplace layer] + every non-marketplace layer`, in the existing order. A local `_partials/` file with the same name still wins.
- A skill from a local layer (`.defaults`, `.user`, `.project`): only the non-marketplace layers. Local skills never include marketplace partials.
- Replace `partialsStack(layers:)` with `partialsStack(for winningLayer: DotfolderStack.Layer)`, and build the `TemplateEngine` with that stack for each render.

The tests build `SkillsRegistry(layers:)` directly with `.marketplace` layers over temporary folders. They do not need the store.

- [x] `partialsStack(for:)` with the two rules
- [x] Use it where the `TemplateEngine` is built
- [x] Tests

## Acceptance Criteria
- [x] A marketplace skill never resolves a partial from another marketplace
- [x] A local partial with the same name overrides a marketplace partial
- [x] A local skill that includes a name that only a marketplace has gets a render error, not the marketplace text
- [x] Every existing `StencilPassTests` case passes unchanged

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplacePartialScopeTests.swift`: marketplaces A and B both ship `_partials/header.md` with different text, and a skill in A renders A's text; a local `_partials/header.md` overrides both; a local skill cannot include a marketplace-only partial
- [x] Run `swift test --filter "MarketplacePartialScopeTests|StencilPassTests"`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace