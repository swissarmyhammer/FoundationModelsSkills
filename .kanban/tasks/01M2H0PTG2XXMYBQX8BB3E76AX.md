---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2h15jj1xrwr2bcg13k94f9s
  text: |-
    ### Step 1 (Extras) — done by the Extras session
    - evidence: `DotfolderStack.Source.marketplace` is on FoundationModelsExtras `main` at d0048eb3f5c629554811c4bdaa68d00650cae63d (push 76b773b..d0048eb). New test `DotfolderStackTests.defaultInitNeverDerivesAMarketplaceLayer`. Extras `swift test`: 265 tests, 24 suites, 0 warnings. Extras had no exhaustive switch on `Source`; three doc comments in `LayeredYAMLDocument.swift` were updated.
    - next: ACPAgent is not changed yet. Its `ConfigurationLayerName.swift:29` switch breaks when it next resolves Extras `main`. Do step 2 (ACPAgent) first, then step 3 (this package).
  timestamp: 2026-09-14T22:38:55.553508+00:00
position_column: todo
position_ordinal: '80'
title: Pin Extras with DotfolderStack.Source.marketplace and prove it renders untrusted
---
## What

marketplace.md §4.3 and decision 8. The Extras session already added `DotfolderStack.Source.marketplace` on FoundationModelsExtras `main` at d0048eb3f5c629554811c4bdaa68d00650cae63d. The ACPAgent switch fix is a separate `cross-repo` task. This task is the in-repo part only.

- Run `swift package update FoundationModelsExtras` in this repository, and commit `Package.resolved`.
- `StencilPass.resolvedTrust(for:)` (`Sources/FoundationModelsSkills/Render/StencilPass.swift`) needs no change: every source except `.defaults` is untrusted. Add a test that proves this for `.marketplace`.

- [x] Extras: `Source.marketplace` is on `main` at d0048eb (done by the Extras session)
- [ ] Update the Extras pin in `Package.resolved`
- [ ] Add the `.marketplace` trust test

## Acceptance Criteria
- [ ] `Package.resolved` pins FoundationModelsExtras at d0048eb or later
- [ ] `swift build` and `swift test` pass with zero warnings
- [ ] A `.marketplace` layer renders through `TemplateEngine.Trust.untrusted` in `StencilPass`

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/StencilPassTests.swift`: a body with `{% now %}` in a `.marketplace` layer draws the untrusted-rejection error, and the same body in a `.defaults` layer renders
- [ ] Run `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace