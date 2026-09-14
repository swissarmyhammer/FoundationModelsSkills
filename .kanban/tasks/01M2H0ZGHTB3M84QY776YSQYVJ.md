---
assignees:
- claude-code
depends_on:
- 01M2H0PTG2XXMYBQX8BB3E76AX
position_column: todo
position_ordinal: 8c80
title: Scope Stencil partials to the winning marketplace plus the local layers
---
## What

marketplace.md §6.5 and decision 9. Today `StencilPass` builds one partials stack from all layers (`StencilPass.partialsStack(layers:)`, used where `StencilPass` builds its `TemplateEngine`). A skill from marketplace A can then include a partial from marketplace B.

Change `StencilPass` (`Sources/FoundationModelsSkills/Render/StencilPass.swift`) so the partials stack depends on the winning layer of the render (`RenderRequest.winningLayer`):
- A skill from a `.marketplace` layer: `[that marketplace layer] + every non-marketplace layer`, in the existing order. A local `_partials/` file with the same name still wins.
- A skill from a local layer (`.defaults`, `.user`, `.project`): only the non-marketplace layers. Local skills never include marketplace partials.
- Replace `partialsStack(layers:)` with `partialsStack(for winningLayer: DotfolderStack.Layer)`, and build the `TemplateEngine` with that stack for each render.

The tests build `SkillsRegistry(layers:)` directly with `.marketplace` layers over temporary folders. They do not need the store.

- [ ] `partialsStack(for:)` with the two rules
- [ ] Use it where the `TemplateEngine` is built
- [ ] Tests

## Acceptance Criteria
- [ ] A marketplace skill never resolves a partial from another marketplace
- [ ] A local partial with the same name overrides a marketplace partial
- [ ] A local skill that includes a name that only a marketplace has gets a render error, not the marketplace text
- [ ] Every existing `StencilPassTests` case passes unchanged

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplacePartialScopeTests.swift`: marketplaces A and B both ship `_partials/header.md` with different text, and a skill in A renders A's text; a local `_partials/header.md` overrides both; a local skill cannot include a marketplace-only partial
- [ ] Run `swift test --filter "MarketplacePartialScopeTests|StencilPassTests"`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace