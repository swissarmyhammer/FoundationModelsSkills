---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f4x54v4xtg6mhneh424xk7
  text: 'Research: `GraphQLEndpointTool` (Extras) is `Tool` + `var graphQLEndpoints: [any GraphQLEndpoint]`. `SkillsGraph` (commit 3bf828d) is a `struct`, so "same instance" cannot be observed on it; it becomes a `final class` (reference identity is the point: one endpoint, and later one ChangeLog, per registry). `SkillsTool.make(context:)` builds `SkillsGraph(registry: context.registry)` once and hands it to `SkillsCatalogTool.init`, which stores it; copies and `forked()` (default, returns self) share it. FoundationModelsACPAgent has no endpoint collection code yet (only `SettingsTool` conforms), so nothing there changes for this task.'
  timestamp: 2026-10-21T11:52:50.587021+00:00
- actor: claude-code
  id: 01m5f51t1ef2ag2yc01f6kg78y
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsSkills/GraphQL/SkillsGraph.swift (struct -> `public final class`, identity documented), Sources/FoundationModelsSkills/Operations/SkillsCatalogTool.swift (stores `private let skillsGraph`, new `extension SkillsCatalogTool: GraphQLEndpointTool` giving `[skillsGraph]`), Sources/FoundationModelsSkills/Operations/SkillsTool.swift (`make(context:)` builds `SkillsGraph(registry: context.registry)` once and passes it in; docs updated), Tests/FoundationModelsSkillsTests/SkillsCatalogToolEndpointTests.swift (4 tests: name/version/scope, copy `===`, `forked()` `===`, endpoint reads the tool registry). RED was the compile failure of `===` on the struct; GREEN 4/4. Full `swift test`: 675 tests in 62 suites passed; `swift build` complete. The only warning in either run is SwiftPM's "missing creator for mutated node" on the mlx-swift_Cmlx.bundle dependency resource, not from this package's sources.
    - notes: changes subscription not touched (out of scope). FoundationModelsACPAgent needs no change for this task: it has no endpoint collection code yet (ACPA-13).
    - next: /review
  timestamp: 2026-10-21T11:55:23.054394+00:00
- actor: claude-code
  id: 01m5f545wh1011r0atpmm46vj2
  text: |-
    ### test — green
    - evidence: swift build && swift test — 675 tests in 62 suites passed, 0 failed, 0 skipped; only warning is the known mlx-swift Cmlx "missing creator for mutated node" (out of scope)
    - next: review
  timestamp: 2026-10-21T11:56:40.721675+00:00
depends_on:
- 01M5F230NX5CY90TNJP53Y1QD6
position_column: doing
position_ordinal: '80'
title: 'SK-5: SkillsCatalogTool conforms to GraphQLEndpointTool'
---
## What
`SkillsCatalogTool` (Sources/FoundationModelsSkills/Operations/SkillsCatalogTool.swift) conforms to `GraphQLEndpointTool` (EXTRAS-7, D75). `graphQLEndpoints` is a list of one: the `SkillsGraph` over the same `SkillsRegistry` the tool's `SkillsToolContext` holds. The tool stays an `OperationTool<SkillsToolContext>` op tool for the model (list/search/use); the model never sends GraphQL text to it (EXTRAS-9 rule 1).

## Notes
- `SkillsCatalogTool` is a value type and is copied (ForkableTool). The endpoint, and later its `ChangeLog`, must be one instance per registry: build it once in `SkillsTool.make`/`SkillsToolAssembly` and store it, so every copy and every child session of the folder hands out the same endpoint (same `cursor`/seq).
- The host (FoundationModelsACPAgent) finds it with `tool as? any GraphQLEndpointTool`; check nothing else there needs a change for a `sessionFolder` endpoint (host checks the folder, ACPA-13).

## Acceptance criteria (EXTRAS-9 rule 11)
- [x] Test: the tool gives the endpoint in `graphQLEndpoints` with name `skills`, version `"1"`, scope `.sessionFolder`
- [x] Test: two copies / a forked tool give the same endpoint instance
- [x] The model-facing tool description and ops are unchanged (existing tests stay green)
- [x] `swift build` and `swift test` green #sk-5 #graphql