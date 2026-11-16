---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7jraxmv0cm95mdxmgfw9x7b
  text: |-
    ### Extras names (from foundationmodelsextras-0a, Extras local commit a35d5ea, not yet pushed)
    Module `Marketplace`:
    - `public actor MarketplaceRegistry`: `init(storage: any MarketplaceSourceStorage)`, `marketplaces() async throws -> [MarketplaceEntry]`, `marketplace(id:) async throws -> MarketplaceEntry?`, `add(_ source: MarketplaceSource) async throws -> MarketplaceEntry`, `update(id:to:) async throws -> MarketplaceEntry` (the id can change), `remove(id:) async throws -> MarketplaceEntry`, `nonisolated changes() -> AsyncStream<MarketplaceRegistryChange>`.
    - `protocol MarketplaceSourceStorage` (`loadSources`, `saveSources`); `InMemoryMarketplaceSourceStorage(sources:)` for tests.
    - `MarketplaceEntry { id: String, source: MarketplaceSource }`; source fields: url, ref, sha, path, alias, select, autoUpdate.
    - `MarketplaceRegistryChange`: `.added(entry)`, `.updated(previousID:, entry)`, `.removed(entry)`.
    - `MarketplaceRegistryError`: `.duplicateMarketplace(id:)`, `.unknownMarketplace(id:)`, `.invalidSource(MarketplaceSourceError)`; give `errorDescription` to the client.
    - The registry does not refresh `MarketplaceStore`; the host makes a new store from `marketplaces()` on each change.
    - Docs: Extras docs/REFERENCE.md "One marketplace at a time: MarketplaceRegistry".

    Next: start when a35d5ea is on Extras main.
  timestamp: 2026-11-16T18:01:31.547815+00:00
- actor: claude-code
  id: 01m7js35vaxwg8t9h6nkbtx16r
  text: |-
    ### implement — changed (not committed)
    - evidence: `swift test` with a local override of Extras at a35d5ea (`swift package edit FoundationModelsExtras --path ../FoundationModelsExtras`): 890 tests in 73 suites pass.
    - Files: `GraphQL/SkillsGraphMarketplaces.swift`, `Registry/MarketplaceSourceFields.swift`, `Operations/MarketplaceOperations.swift`, changes to `SkillsGraph.swift`, `SkillsGraphSchema.swift`, `SkillsTool.swift`, `SkillsToolContext.swift`, `PlainTextOperations.swift`, docs, golden schema; tests `SkillsGraphMarketplaceTests.swift`, `MarketplaceOperationsTests.swift`.
    - next: when a35d5ea is on Extras main: `swift package unedit FoundationModelsExtras`, `swift package update FoundationModelsExtras`, `swift test`, commit (do not commit `Packages/`), push, send the names to testudoapp-75.
  timestamp: 2026-11-16T18:14:46.378612+00:00
position_column: done
position_ordinal: ffb480
title: Marketplace queries, mutations and skills tool operations (D190)
---
Request from testudoapp-75 (D190, D100). Blocked: wait for the names of the marketplace item API of Extras (foundationmodelsextras-0a, `Sources/Marketplace/MarketplaceRegistry.swift`).

## Work
- Queries `marketplaces`, `marketplace(id)` on `SkillsGraph`.
- Mutations `addMarketplace`, `updateMarketplace`, `removeMarketplace` (rule 7 form).
- A change subscription for the marketplaces.
- Model operations `add marketplace`, `edit marketplace`, `remove marketplace`, `list marketplace`, `show marketplace` on the `skills` tool.
- Send the API and schema names to testudoapp-75.

## Acceptance
- Tests for each query, mutation, operation and the change event pass.
- `swift test` passes.