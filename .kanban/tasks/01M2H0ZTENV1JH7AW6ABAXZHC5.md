---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2k1txhb8wjr1km0ze64m2d8
  text: |-
    Research notes for the next agent:

    - `MarketplaceGrants` is in `Sources/FoundationModelsSkills/Marketplace/MarketplaceSource.swift`, not in a file of its own.
    - `SkillsRegistry.CatalogEntry` is `private`, thus `effectivePolicy(for:)` must be `private` too. The card also asks for a lookup by skill id, which is `internal func effectivePolicy(id: String)`. `RunScript` uses that one.
    - `MarketplaceProvenanceIndex` held one array of `MarketplaceProvenance?` by layer index. It now holds one array of a new internal `Entry` value, which carries the provenance and the grants together. One array, one lookup, no second parallel array.
    - A layer whose source is `.marketplace` but which no provider named grants for gets `MarketplaceGrants.none`, the most restrictive value. A registry built with `init(layers:)` and a `.marketplace` layer thus cannot gain shell injection or scripts.
    - An unknown skill id gets the host policy, thus `run script` on an unknown id still gives the "not currently usable" corrective, and a script-disabled host still gives the identical policy corrective for any path. The ordering test `hostPolicyGateFiresBeforeAnyIDOrPathResolution` still passes.

    Test support moved, to keep one copy of each helper:
    - `FakeMarketplaceProvider` and `makeMarketplaceLayer(root:id:sha:grants:)` moved from `MarketplaceRegistryTests` into `MarketplaceTestSupport.swift`.
    - `writeExecutableShebangScript(named:inSkillID:under:contents:)` and `scriptsDirectory(inSkillID:under:)` moved from `RunScriptTests` into `ResourceTestSupport.swift`; `makeContext(registry:)` is new there, because a marketplace-backed registry cannot come from `makeContext(roots:policy:)`.
  timestamp: 2026-09-15T17:29:03.787442+00:00
- actor: claude-code
  id: 01m2k1vh6ynzj9pnqjgvg3jxvj
  text: |-
    ### implement — changed
    - evidence: 7 files changed, 1 file added. Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Sources/FoundationModelsSkills/Resources/RunScript.swift, Tests/FoundationModelsSkillsTests/MarketplaceGrantsTests.swift (new), Tests/FoundationModelsSkillsTests/MarketplaceTestSupport.swift, Tests/FoundationModelsSkillsTests/ResourceTestSupport.swift, Tests/FoundationModelsSkillsTests/MarketplaceRegistryTests.swift, Tests/FoundationModelsSkillsTests/RunScriptTests.swift. `swift test --filter MarketplaceGrantsTests`: 9 tests, 9 passed. `swift test`: 608 tests in 44 suites, all passed. `swift build --build-tests`: zero warnings. TDD: the two default-grant tests failed first (the marketplace skill ran the shell command and ran the script), then passed after the change.
    - next: /review
  timestamp: 2026-09-15T17:29:23.934286+00:00
- actor: claude-code
  id: 01m2k24jrzgnx2bw51qs2cpp9z
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit f5e7a3b). 0 findings, 0 confirmed, 0 refuted. 7 validators ran, 0 failed. 8 files reviewed; 4 `.kanban/` files not reviewed because of an ignore rule.
    - next: no work is open. All task items and all acceptance criteria are marked. The task moves to done.
  timestamp: 2026-09-15T17:34:20.447667+00:00
- actor: claude-code
  id: 01m2k24xej4k1mmy77pzbbd5e7
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 8 files (Marketplace/MarketplaceLayerProviding.swift, Registry/SkillsRegistry.swift, Resources/RunScript.swift, Tests/.../MarketplaceGrantsTests.swift new, plus the moved test helpers)
    - test: green — swift build --build-tests 0 warnings; swift test x2, 608 passed each run, 0 failed, 0 skipped
    - commit: f5e7a3b feat(marketplace): check the marketplace grant before a skill can run
    - review: clean — 0 findings; task moved to done
    - note: a `.marketplace` layer with no named grants gets `MarketplaceGrants.none`, thus no capability comes from omission
  timestamp: 2026-09-15T17:34:31.378783+00:00
depends_on:
- 01M2H0W2TM0WRKHZP8FRAJZAYY
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: done
position_ordinal: d380
title: Apply per-marketplace grants to shell injection and run script
---
## What

marketplace.md §6.6. A marketplace skill gets no shell injection and no scripts unless the host grants them for that marketplace. Today one `RenderPolicy` applies to the full registry.

- `MarketplaceLayer` (from the registry task): add `grants: MarketplaceGrants` (from the sources task; default `.none`).
- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: add `func effectivePolicy(for entry: CatalogEntry) -> RenderPolicy`. For an entry from a `.marketplace` layer, it gives `RenderPolicy(isShellExecutionDisabled: policy.isShellExecutionDisabled || !grants.shellInjection, isScriptExecutionDisabled: policy.isScriptExecutionDisabled || !grants.scripts)`. For a local entry, it gives `policy` unchanged. Use it in `SkillsRegistry.renderRequest(text:entry:arguments:argumentNames:)` in place of `policy`. Add an internal lookup by skill id for the resource operations.
- `Sources/FoundationModelsSkills/Resources/RunScript.swift`: where `RunScript` calls `ScriptGate.evaluateHostPolicy(isScriptExecutionDisabled:)`, pass the effective value for the skill, not `context.registry.policy`. `ScriptGate.evaluateGrant(path:allowedTools:)` stays as it is.
- The host policy always wins: a grant can never turn on what the host policy turned off.

- [x] `grants` on `MarketplaceLayer`
- [x] `effectivePolicy(for:)` and its use in `renderRequest`
- [x] The effective policy in `RunScript`
- [x] Tests

## Acceptance Criteria
- [x] A marketplace skill with `` !`echo hi` `` gets the disabled marker with default grants, and the command output with `grants.shellInjection`
- [x] `run script` in a marketplace skill is refused with default grants, and allowed with `grants.scripts` and a matching `allowed-tools` grant
- [x] A host policy that turns a capability off wins over a grant
- [x] Local skills behave as they do now

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceGrantsTests.swift`: the shell matrix (default, granted, host-off with grant); the script matrix (default, granted, granted without `allowed-tools`, host-off with grant); a local skill is unchanged
- [x] Run `swift test --filter MarketplaceGrantsTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace