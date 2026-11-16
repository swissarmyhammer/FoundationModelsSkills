---
assignees:
- claude-code
position_column: done
position_ordinal: ffb780
title: resetMarketplaces mutation and reset marketplace tool operation
---
testudoapp-75 asks for this (D190, command "Skills: Use the Default Skill Marketplace"). Today TestudoApp clears the settings key `tools.skills.marketplaces`, thus no change event goes to the other sessions.

Blocked on Extras: `MarketplaceSourceStorage.resetSources()` and `MarketplaceRegistry.reset()` (asked of foundationmodelsextras-0a). Only the host storage knows the default list.

Do:
- Mutation `resetMarketplaces(input: ResetMarketplacesInput!): [Marketplace!]!` on the `skills` endpoint. It calls `MarketplaceRegistry.reset()`. The change log gets the events of the registry, as for the other mutations.
- Tool op `reset marketplace`. The noun `marketplaces` also resolves.
- Docs: operations.md, marketplaces.md.

Acceptance:
- After the mutation, the list is the default list of the storage.
- `marketplaceChanges` gives the removed and added ids.
- `swift test` passes. Push, then send the name and the commit to testudoapp-75.