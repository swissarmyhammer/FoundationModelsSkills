---
assignees:
- claude-code
depends_on:
- 01M2H0W2TM0WRKHZP8FRAJZAYY
position_column: todo
position_ordinal: '9880'
title: Show marketplace provenance in list skill rows and the / command listing
---
## What

marketplace.md §9.1. A user must see where a skill comes from. This is display only: the operations and their parameters do not change (§9.2).

- `Sources/FoundationModelsSkills/Operations/SkillRow.swift`: add an optional `source` text to the row that `list skill` returns, for example `swissarmyhammer-skills@1.2.0` for a marketplace skill and `nil` for a local skill.
- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift` (`commandListing()`) and `Sources/FoundationModelsSkills/Listing/SkillListing.swift`: carry the same text, so the `/` menu can show `commit (swissarmyhammer-skills@1.2.0)`.
- The text comes from the `MarketplaceProvenance` of the winning layer (id and catalog version; the short SHA when there is no version).

- [ ] `source` on `SkillRow`
- [ ] `source` on `SkillListing` and in `commandListing()`
- [ ] Tests

## Acceptance Criteria
- [ ] A marketplace skill shows `<id>@<version>` in `list skill` and in `commandListing()`; a local skill shows no source
- [ ] The operation names and parameters of the fused tool do not change

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceProvenanceDisplayTests.swift` with a `FakeMarketplaceProvider`: the `list skill` row and the `commandListing()` entry for a marketplace skill, a local skill, and a marketplace skill with no catalog version (short SHA)
- [ ] `Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift`: the operation names did not change
- [ ] Run `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace