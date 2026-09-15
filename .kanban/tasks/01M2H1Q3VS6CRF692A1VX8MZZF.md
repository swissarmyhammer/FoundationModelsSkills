---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2k299fzgvdfv0zk4btjjjjs
  text: |-
    Picked up the card. Research notes:

    - `MarketplaceProvenance` (Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift) holds `id`, `url`, `sha`, `catalogVersion`. It is the one place that can make the display text, thus the text becomes a computed property there. The text never holds the URL, thus it never holds a credential.
    - `SkillsRegistry.CatalogEntry` already holds `grants` from `MarketplaceProvenanceIndex`, but not the provenance. The plan is to add `marketplace: MarketplaceProvenance?` beside `grants`, filled from `plan.marketplaces.provenance(atLayerIndex:)`.
    - `list skill` builds its rows as `registry.metadata().map(SkillRow.init(metadata:))`, thus the text must first reach `SkillMetadata`, then `SkillRow`.
    - `commandListing()` builds each row with `listing(for:)`, thus `SkillListing` gets the same text there.
    - `SkillRow` is `Encodable`. A `String?` field with the value `nil` writes no key, thus a local row keeps its shape and no test breaks.
    - `MarketplaceTestSupport.makeMarketplaceLayer` hard-codes `catalogVersion: "1.0.0"`. It gets a `catalogVersion` parameter with that same default, thus the new test can ask for a layer with no catalog version and the helper is not copied.
    - `SkillsToolAssemblyTests` can read the operation names from `tool.operations` (`opString`, `parameters`).
  timestamp: 2026-09-15T17:36:54.783941+00:00
- actor: claude-code
  id: 01m2k2jyd8ze5ez9bz2zrvtj3h
  text: |-
    Implementation landed, TDD order.

    RED first: the new suite and the new assembly case were written before any source change. The build failed with "value of type 'SkillListing' has no member 'source'".

    GREEN:
    - `MarketplaceProvenance.displayText` makes the text: `<id>@<catalogVersion>`, else `<id>@<short sha>` (7 characters, a named constant), else the id alone. The URL is never part of the text.
    - `SkillsRegistry.CatalogEntry` got `marketplace: MarketplaceProvenance?`, filled from `plan.marketplaces.provenance(atLayerIndex:)` beside the grants that were already there.
    - `SkillMetadata.source`, `SkillRow.source`, and `SkillListing.source` all carry that text. `metadata()` and `listing(for:)` fill them.
    - `SkillMetadata.renderBlock()` stays as it was, thus a marketplace name can never change how a search ranks a skill.

    What did not need a change:
    - `SkillRow` is `Encodable` with a synthesized `encode`, which writes an optional with `encodeIfPresent`. A local row thus writes no `source` key at all and keeps its old JSON shape. No old test broke.

    One wrong guess, corrected: the first version of the parameter table in `SkillsToolAssemblyTests` named `offset`/`limit` for `read resource` and left out `timeout` for `run script`. The real names are `start`/`end` and `id`/`path`/`arguments`/`timeout`. The case found the error, which is what it is for.

    `swift build --build-tests`: no error and no warning. `swift test`: 616 tests in 45 suites passed.
  timestamp: 2026-09-15T17:42:11.112656+00:00
- actor: claude-code
  id: 01m2k2k30bmnatsx242mhnffyw
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift, Sources/FoundationModelsSkills/Operations/SkillRow.swift, Sources/FoundationModelsSkills/Listing/SkillListing.swift, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Tests/FoundationModelsSkillsTests/MarketplaceProvenanceDisplayTests.swift (new), Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift, Tests/FoundationModelsSkillsTests/MarketplaceTestSupport.swift; `swift test` 616 tests in 45 suites passed, 0 failures, 0 warnings
    - next: /review
  timestamp: 2026-09-15T17:42:15.819647+00:00
depends_on:
- 01M2H0W2TM0WRKHZP8FRAJZAYY
position_column: doing
position_ordinal: '80'
title: Show marketplace provenance in list skill rows and the / command listing
---
## What

marketplace.md §9.1. A user must see where a skill comes from. This is display only: the operations and their parameters do not change (§9.2).

- `Sources/FoundationModelsSkills/Operations/SkillRow.swift`: add an optional `source` text to the row that `list skill` returns, for example `swissarmyhammer-skills@1.2.0` for a marketplace skill and `nil` for a local skill.
- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift` (`commandListing()`) and `Sources/FoundationModelsSkills/Listing/SkillListing.swift`: carry the same text, so the `/` menu can show `commit (swissarmyhammer-skills@1.2.0)`.
- The text comes from the `MarketplaceProvenance` of the winning layer (id and catalog version; the short SHA when there is no version).

- [x] `source` on `SkillRow`
- [x] `source` on `SkillListing` and in `commandListing()`
- [x] Tests

## Acceptance Criteria
- [x] A marketplace skill shows `<id>@<version>` in `list skill` and in `commandListing()`; a local skill shows no source
- [x] The operation names and parameters of the fused tool do not change

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceProvenanceDisplayTests.swift` with a `FakeMarketplaceProvider`: the `list skill` row and the `commandListing()` entry for a marketplace skill, a local skill, and a marketplace skill with no catalog version (short SHA)
- [x] `Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift`: the operation names did not change
- [x] Run `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace