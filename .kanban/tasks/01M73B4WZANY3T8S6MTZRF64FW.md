---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m73ba7s7jp5afmzhv9k1e6bs
  text: |-
    Research: `SkillsToolContext.init` already takes `sandboxProbe: SandboxProbe = .live` and calls `mode.validate(probe:)` before the mode-mismatch check. The internal `SkillsTool.makeContext` has two test callers (`SkillsReloadFollowerTests.makeContext`, `SkillsCatalogNoticeTests.makeContext`). The parameters of `makeContext` and `assemble` have no defaults, so the new `sandboxProbe` parameter has no default there either. The two test helpers now give `.fixed(false)`, so the result does not depend on the sandbox state of the test process.

    Implementation: both public `SkillsTool.make(registry:...)` overloads now take `sandboxProbe: SandboxProbe = .live` as the last parameter. The probe goes through `assemble` and `makeContext` to `SkillsToolContext.init`. The doc comments say that `make` throws `ToolModeError.openModeInSandbox` when the mode of the registry is `.open` and the probe says sandboxed. I did not change the temporary `mode: .open` default on `SkillsToolContext.init` (task ^na244z4 removes it).

    Handoff for foundationmodelsagents-d7: the new signature is `SkillsTool.make(registry:model:embedder:followReloads:catalogCharacterLimit:visibilityPredicate:sandboxProbe:)` and `SkillsTool.make(registry:embedder:followReloads:catalogCharacterLimit:visibilityPredicate:sandboxProbe:)`. `sandboxProbe` defaults to `.live`. `AgentEnvironment.make` can take a `SandboxProbe` and give it to the `sandboxProbe:` argument. This agent cannot send a message to foundationmodelsagents-d7 directly, so the orchestrator must relay this note.
  timestamp: 2026-11-10T18:25:21.191424+00:00
- actor: claude-code
  id: 01m73bab1ntb77fbw0jc49przs
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsSkills/Operations/SkillsToolAssembly.swift, Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift (6 new tests: open + .fixed(false) composes, open + .fixed(true) throws openModeInSandbox, sandboxed + .fixed(true) composes, for each overload), Tests/FoundationModelsSkillsTests/SkillsReloadFollowerTests.swift, Tests/FoundationModelsSkillsTests/SkillsCatalogNoticeTests.swift. RED: build failed with "extra argument 'sandboxProbe' in call". GREEN: SkillsToolAssemblyTests 22/22 passed. Full `swift test`: 807 tests in 68 suites passed, no compiler warnings.
    - next: /review. The orchestrator relays the new signature to foundationmodelsagents-d7.
  timestamp: 2026-11-10T18:25:24.533922+00:00
position_column: doing
position_ordinal: '80'
title: 'SK-7d: SkillsTool.make(registry:) takes a sandboxProbe, so a host probe reaches the skills tool'
---
## What
Found by foundationmodelsacpagent-ec. FoundationModelsAgents makes the `SkillsToolContext` through `SkillsTool.make(registry:...)` (`Sources/FoundationModelsSkills/Operations/SkillsToolAssembly.swift`, the two `public static func make` overloads). `make` calls `SkillsToolContext.init` with the default `sandboxProbe: .live`. Thus a host probe (for example `SandboxProbe.fixed(true)` in a test) cannot reach the skills tool. `.live` is correct in production, thus this is not a defect in production, but a test cannot check the refusal of `open` in a sandboxed process through `make`.

Change:
- Add the parameter `sandboxProbe: SandboxProbe = .live` to both public `SkillsTool.make(registry:...)` overloads, and give it to `SkillsToolContext.init` through the internal `makeContext`.
- Update the doc comments: `make` throws `ToolModeError.openModeInSandbox` when the mode of the registry is `.open` and the probe says sandboxed.
- Tell foundationmodelsagents-d7 the new parameter, so that `AgentEnvironment.make` can take a probe and give it through.

## Acceptance Criteria
- [ ] Both public `SkillsTool.make(registry:...)` overloads take `sandboxProbe:` with the default `.live`.
- [ ] `SkillsTool.make(registry:, sandboxProbe: .fixed(true))` with an `.open` registry throws `ToolModeError.openModeInSandbox`.
- [ ] With `.sandboxed` registry and `.fixed(true)`, `make` succeeds.

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift`: one test for each criterion above, for each overload.
- [ ] `swift test` passes with no warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1