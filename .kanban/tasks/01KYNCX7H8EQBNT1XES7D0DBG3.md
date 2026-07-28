---
depends_on:
- 01KYNCWEKBW84J06EDGSNBWVQT
position_column: todo
position_ordinal: '9080'
title: Dual-use CLI via OperationCLIDriver
---
## What
The §7.2 CLI: the same operation declarations drive an `OperationCLIDriver` command tree, converging on the exact payload the model sends.

- Add the `OperationsCLI` product (from `../FoundationModelsOperationTool`) to the package manifest where needed.
- `Sources/FoundationModelsSkills/CLI/SkillsCLI.swift` — a public entry (`OperationCLIDriver(tool: skillsTool)` wiring) the demo executable and hosts reuse: `<executable> skill list|search|use …` with stock ArgumentParser help/did-you-mean/completions.
- CLI visibility = user surface (plan §7.2: the CLI is a user, not a model): `use` of a `disable-model-invocation` skill works; `user-invocable: false` skills are hidden from CLI list/search and refused on use — implement by driving the CLI path through `commandListing()` visibility, not the model filter. Read upstream's driver API to see where a visibility filter hooks in; if the driver only speaks ops, wrap the context with a user-surface variant.
- Round-trip payload test against the resolver (plan M4.5): the CLI invocation for each verb produces byte-identical op payloads to the model-path dispatch (upstream pins this pattern — mirror its round-trip test).

## Acceptance Criteria
- [ ] `skill list`, `skill search "query"`, `skill use commit --arguments "fix parser"` all work against the fixture registry
- [ ] CLI sees user-surface visibility (`deploy` listed/usable, `lint` hidden/refused)
- [ ] Round-trip: CLI payload == model payload for all three verbs

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillsCLITests.swift` — invocation table; visibility matrix; round-trip payload equality
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.