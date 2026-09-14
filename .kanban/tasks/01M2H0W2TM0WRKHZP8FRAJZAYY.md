---
assignees:
- claude-code
depends_on:
- 01M2H0PTG2XXMYBQX8BB3E76AX
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: todo
position_ordinal: '8880'
title: Put marketplace layers below the stack in SkillsRegistry, with provenance and reload on update
---
## What

marketplace.md §4.1, §4.2, §7.4, §9.1. The registry takes marketplace layers in front of the local stack. It stays a pure disk reader: the store (a later task) only gives it layers and an update signal.

- `Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift`: `public protocol MarketplaceLayerProviding: Sendable` with `func marketplaceLayers() -> [MarketplaceLayer]` (lowest precedence first) and `var layerUpdates: AsyncStream<Void> { get }`. `MarketplaceLayer` has a `DotfolderStack.Layer` (source `.marketplace`, root = the stable `current` path) and a `MarketplaceProvenance` (id, url, sha, catalogVersion).
- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: add `public convenience init(marketplaces: some MarketplaceLayerProviding, stack: DotfolderStack, policy: RenderPolicy = RenderPolicy(), watch: Bool = false)`. Layers = `marketplaces.marketplaceLayers().map(\.layer) + stack.layers`. On each `layerUpdates` value, call `marketplaceLayers()` **again** (the SHA and catalog version change), rebuild the provenance map, and run the same rebuild as `SkillsRegistry.ReloadCoordinator`, so `onReload` and the searcher update work as they do now. A provider update reloads the registry even when `watch` is `false`, and `onReload` is not `nil` for this init when `watch` is `false`.
- `Sources/FoundationModelsSkills/Validation/SkillDiagnostic.swift`: add `marketplace: MarketplaceProvenance?` to `SkillDiagnostic.Provenance` (default `nil`).
- `Sources/FoundationModelsSkills/Validation/SkillValidator.swift`: the shadow message (the "shadows N lower-precedence copy…" advisory) names the marketplace when a shadowed candidate came from a marketplace layer, for example "local `…/commit` shadows `commit` from marketplace `swissarmyhammer-skills`".

- [ ] `MarketplaceLayerProviding`, `MarketplaceLayer`, `MarketplaceProvenance`
- [ ] `SkillsRegistry.init(marketplaces:stack:policy:watch:)` layer order
- [ ] Reload on `layerUpdates` with fresh `marketplaceLayers()`, and `onReload` available when `watch` is `false`
- [ ] Marketplace provenance in `SkillDiagnostic` and in the `SkillValidator` shadow message

## Acceptance Criteria
- [ ] Order is `url[0] < … < url[n] < defaults < user < project`: a local skill wins, then the last marketplace
- [ ] With `watch: false`, `onReload` is not `nil`, and one provider update gives exactly one `onReload` value
- [ ] After a provider update that changes the SHA, the diagnostics carry the new SHA
- [ ] Every existing registry test passes unchanged

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceRegistryTests.swift`, with a `FakeMarketplaceProvider` over temporary folders: two marketplaces and a local stack all have `commit` (the local one wins); remove the local one (the last marketplace wins); reverse the provider order (the other marketplace wins); the shadow message names the marketplace; with `watch: false`, a provider update after a changed `SKILL.md` gives one `onReload` value and the new body; the provenance SHA changes after the update
- [ ] Run `swift test --filter MarketplaceRegistryTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace