---
assignees:
- claude-code
position_column: done
position_ordinal: ffb580
title: Send a marketplace registry through the SkillsTool.make(registry:) factories
---
ACPAgent (foundationmodelsacpagent-30) asks for this. FoundationModelsAgents makes the skills tool with `SkillsTool.make(registry:model:embedder:...)`. That path makes a `SkillsToolContext` with no marketplaces, thus the tool and `SkillsGraph` cannot get the registry of the agent.

Do:
- Add `marketplaces: MarketplaceRegistry? = nil` to the two `SkillsTool.make(registry:...)` overloads in SkillsToolAssembly.swift.
- Send it through `assemble` and `makeContext` into `SkillsToolContext(..., marketplaces:)`.

Acceptance:
- A tool from each overload with a registry has `list marketplace`.
- With no registry, the tool has no marketplace operation (the current behavior).
- `swift test` passes. Push, then send the commit to foundationmodelsacpagent-30.