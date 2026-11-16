---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
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