---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2k0kr3gp88hhhyx4sax4g8m
  text: |-
    Research: the registry already had one rebuild path (`ReloadCoordinator` + `SkillWatcher` + `ReloadBroadcaster`), and `buildCatalog` took a bare `[DotfolderStack.Layer]`. `DiscoveredSkill.rootIndex` and `ShadowedCandidate.rootIndex` are both indices into that same ordered layer list, thus one lookup by layer index gives both the winner provenance and the shadow message. `DotfolderStack.Source.marketplace` is already in the pinned Extras.

    Design that came out of it:
    - `LayerPlan` pairs the ordered layers with a `MarketplaceProvenanceIndex` (one optional entry for each layer).
    - `LayerSource` holds a `@Sendable () -> LayerPlan` closure and the optional update stream. The closure asks the provider for its layers again on each rebuild, thus no second mutable box holds the plan, and the new SHA reaches the diagnostics.
    - One rebuild closure serves the watcher and the update task. Thus one update gives exactly one catalog swap and one `onReload` value.
    - `roots` and the render pipeline stay construction-time invariants (#25/#28): a marketplace layer root is the stable `current` path, thus it never moves across an update.

    What did not work and why the design avoids it: a mutable "current plan" box would need a second `@unchecked Sendable` class for state that the provider already owns.
  timestamp: 2026-09-15T17:07:40.272299+00:00
- actor: claude-code
  id: 01m2k0me2s5tym6an8nzpccyza
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift (new), Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Sources/FoundationModelsSkills/Validation/SkillValidator.swift, Sources/FoundationModelsSkills/Validation/SkillDiagnostic.swift, Tests/FoundationModelsSkillsTests/MarketplaceRegistryTests.swift (new). `swift test --filter MarketplaceRegistryTests` = 7 tests, 7 pass. `swift test` = 599 tests in 43 suites, all pass. `swift build --build-tests` = zero errors, zero warnings.
    - next: /review
  timestamp: 2026-09-15T17:08:02.777195+00:00
- actor: claude-code
  id: 01m2k0yb7815kqdnq8p469tcwx
  text: |
    ### review — findings
    - evidence: 1 finding — Tests/FoundationModelsSkillsTests/MarketplaceRegistryTests.swift:212 — code-hygiene/disallowed-constructs-swift no_unchecked_sendable
    - scope: review sha HEAD~1..HEAD (commit 9bccc05); 5 files read, 4 files not read (.reviewignore)
    - next: correct the @unchecked Sendable type in the test file, then do the review again
  timestamp: 2026-09-15T17:13:27.528602+00:00
- actor: claude-code
  id: 01m2k0yr06ntx37mftdxbdybav
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 5 files (Marketplace/MarketplaceLayerProviding.swift new, Registry/SkillsRegistry.swift, Validation/SkillValidator.swift, Validation/SkillDiagnostic.swift, Tests/FoundationModelsSkillsTests/MarketplaceRegistryTests.swift new)
    - test: green — swift build --build-tests 0 warnings; swift test x2, 599 passed each run, 0 failed, 0 skipped
    - commit: 9bccc05 feat(marketplace): put marketplace layers below the local stack in the registry
    - review: findings — 1 open, Tests/FoundationModelsSkillsTests/MarketplaceRegistryTests.swift:212, `@unchecked Sendable` on a test helper
  timestamp: 2026-09-15T17:13:40.614110+00:00
- actor: claude-code
  id: 01m2k12scs9cm6ntvy8s5s9da5
  text: |
    Corrected the review finding with the real fix, not a disable comment. `FakeMarketplaceProvider` now holds its layer list in a `Mutex<[MarketplaceLayer]>` from the `Synchronization` module. Every stored property is an immutable `let` of a `Sendable` type, thus the class takes a plain `Sendable` conformance that the compiler checks. The `NSLock` and the `var layers` property are gone.

    An `actor` was not possible: `MarketplaceLayerProviding.marketplaceLayers()` is a synchronous requirement.

    I looked at the whole file for the same cause. This was the only `@unchecked Sendable` in it.

    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsSkillsTests/MarketplaceRegistryTests.swift. `swift build --build-tests` = zero errors, zero warnings. `swift test --filter MarketplaceRegistryTests` = 7 tests, 7 pass. `swift test` = 599 tests in 43 suites, all pass, 0 fail, 0 skip.
    - next: /review
  timestamp: 2026-09-15T17:15:53.113037+00:00
depends_on:
- 01M2H0PTG2XXMYBQX8BB3E76AX
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: doing
position_ordinal: '80'
title: Put marketplace layers below the stack in SkillsRegistry, with provenance and reload on update
---
## What

marketplace.md §4.1, §4.2, §7.4, §9.1. The registry takes marketplace layers in front of the local stack. It stays a pure disk reader: the store (a later task) only gives it layers and an update signal.

- `Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift`: `public protocol MarketplaceLayerProviding: Sendable` with `func marketplaceLayers() -> [MarketplaceLayer]` (lowest precedence first) and `var layerUpdates: AsyncStream<Void> { get }`. `MarketplaceLayer` has a `DotfolderStack.Layer` (source `.marketplace`, root = the stable `current` path) and a `MarketplaceProvenance` (id, url, sha, catalogVersion).
- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: add `public convenience init(marketplaces: some MarketplaceLayerProviding, stack: DotfolderStack, policy: RenderPolicy = RenderPolicy(), watch: Bool = false)`. Layers = `marketplaces.marketplaceLayers().map(\.layer) + stack.layers`. On each `layerUpdates` value, call `marketplaceLayers()` **again** (the SHA and catalog version change), rebuild the provenance map, and run the same rebuild as `SkillsRegistry.ReloadCoordinator`, so `onReload` and the searcher update work as they do now. A provider update reloads the registry even when `watch` is `false`, and `onReload` is not `nil` for this init when `watch` is `false`.
- `Sources/FoundationModelsSkills/Validation/SkillDiagnostic.swift`: add `marketplace: MarketplaceProvenance?` to `SkillDiagnostic.Provenance` (default `nil`).
- `Sources/FoundationModelsSkills/Validation/SkillValidator.swift`: the shadow message (the "shadows N lower-precedence copy…" advisory) names the marketplace when a shadowed candidate came from a marketplace layer, for example "local `…/commit` shadows `commit` from marketplace `swissarmyhammer-skills`".

- [x] `MarketplaceLayerProviding`, `MarketplaceLayer`, `MarketplaceProvenance`
- [x] `SkillsRegistry.init(marketplaces:stack:policy:watch:)` layer order
- [x] Reload on `layerUpdates` with fresh `marketplaceLayers()`, and `onReload` available when `watch` is `false`
- [x] Marketplace provenance in `SkillDiagnostic` and in the `SkillValidator` shadow message

## Acceptance Criteria
- [x] Order is `url[0] < … < url[n] < defaults < user < project`: a local skill wins, then the last marketplace
- [x] With `watch: false`, `onReload` is not `nil`, and one provider update gives exactly one `onReload` value
- [x] After a provider update that changes the SHA, the diagnostics carry the new SHA
- [x] Every existing registry test passes unchanged

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceRegistryTests.swift`, with a `FakeMarketplaceProvider` over temporary folders: two marketplaces and a local stack all have `commit` (the local one wins); remove the local one (the last marketplace wins); reverse the provider order (the other marketplace wins); the shadow message names the marketplace; with `watch: false`, a provider update after a changed `SKILL.md` gives one `onReload` value and the new body; the provenance SHA changes after the update
- [x] Run `swift test --filter MarketplaceRegistryTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace

## Review Findings (2026-09-15 12:10)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsSkillsTests/MarketplaceRegistryTests.swift:212` `code-hygiene/disallowed-constructs-swift` — no_unchecked_sendable: Instead of @unchecked Sendable, write a plain Sendable conformance or a @preconcurrency import. If the type really must be @unchecked Sendable, write // swiftlint:disable:next no_unchecked_sendable above it with the synchronization invariant that makes the type thread-safe.
