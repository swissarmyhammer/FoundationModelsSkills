---
assignees:
- claude-code
depends_on:
- 01M2H0W2TM0WRKHZP8FRAJZAYY
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: todo
position_ordinal: 8d80
title: Apply per-marketplace grants to shell injection and run script
---
## What

marketplace.md §6.6. A marketplace skill gets no shell injection and no scripts unless the host grants them for that marketplace. Today one `RenderPolicy` applies to the full registry.

- `MarketplaceLayer` (from the registry task): add `grants: MarketplaceGrants` (from the sources task; default `.none`).
- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: add `func effectivePolicy(for entry: CatalogEntry) -> RenderPolicy`. For an entry from a `.marketplace` layer, it gives `RenderPolicy(isShellExecutionDisabled: policy.isShellExecutionDisabled || !grants.shellInjection, isScriptExecutionDisabled: policy.isScriptExecutionDisabled || !grants.scripts)`. For a local entry, it gives `policy` unchanged. Use it in `SkillsRegistry.renderRequest(text:entry:arguments:argumentNames:)` in place of `policy`. Add an internal lookup by skill id for the resource operations.
- `Sources/FoundationModelsSkills/Resources/RunScript.swift`: where `RunScript` calls `ScriptGate.evaluateHostPolicy(isScriptExecutionDisabled:)`, pass the effective value for the skill, not `context.registry.policy`. `ScriptGate.evaluateGrant(path:allowedTools:)` stays as it is.
- The host policy always wins: a grant can never turn on what the host policy turned off.

- [ ] `grants` on `MarketplaceLayer`
- [ ] `effectivePolicy(for:)` and its use in `renderRequest`
- [ ] The effective policy in `RunScript`
- [ ] Tests

## Acceptance Criteria
- [ ] A marketplace skill with `` !`echo hi` `` gets the disabled marker with default grants, and the command output with `grants.shellInjection`
- [ ] `run script` in a marketplace skill is refused with default grants, and allowed with `grants.scripts` and a matching `allowed-tools` grant
- [ ] A host policy that turns a capability off wins over a grant
- [ ] Local skills behave as they do now

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceGrantsTests.swift`: the shell matrix (default, granted, host-off with grant); the script matrix (default, granted, granted without `allowed-tools`, host-off with grant); a local skill is unchanged
- [ ] Run `swift test --filter MarketplaceGrantsTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace