---
assignees:
- claude-code
depends_on:
- 01M5F230NX5CY90TNJP53Y1QD6
position_column: todo
position_ordinal: '8180'
title: 'SK-5: SkillsCatalogTool conforms to GraphQLEndpointTool'
---
## What
`SkillsCatalogTool` (Sources/FoundationModelsSkills/Operations/SkillsCatalogTool.swift) conforms to `GraphQLEndpointTool` (EXTRAS-7, D75). `graphQLEndpoints` is a list of one: the `SkillsGraph` over the same `SkillsRegistry` the tool's `SkillsToolContext` holds. The tool stays an `OperationTool<SkillsToolContext>` op tool for the model (list/search/use); the model never sends GraphQL text to it (EXTRAS-9 rule 1).

## Notes
- `SkillsCatalogTool` is a value type and is copied (ForkableTool). The endpoint, and later its `ChangeLog`, must be one instance per registry: build it once in `SkillsTool.make`/`SkillsToolAssembly` and store it, so every copy and every child session of the folder hands out the same endpoint (same `cursor`/seq).
- The host (FoundationModelsACPAgent) finds it with `tool as? any GraphQLEndpointTool`; check nothing else there needs a change for a `sessionFolder` endpoint (host checks the folder, ACPA-13).

## Acceptance criteria (EXTRAS-9 rule 11)
- [ ] Test: the tool gives the endpoint in `graphQLEndpoints` with name `skills`, version `"1"`, scope `.sessionFolder`
- [ ] Test: two copies / a forked tool give the same endpoint instance
- [ ] The model-facing tool description and ops are unchanged (existing tests stay green)
- [ ] `swift build` and `swift test` green #sk-5 #graphql