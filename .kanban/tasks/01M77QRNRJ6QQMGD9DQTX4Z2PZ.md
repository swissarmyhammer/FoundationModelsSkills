---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m77qxp5m6jw0a80kacz9yvdv
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — SkillsRegistry.swift, StopWatchingTests.swift
    - test: green — swift test, 825 passed
    - commit: e07d9b0
    - review: clean — review sha HEAD~1..HEAD, 0 findings
  timestamp: 2026-11-12T11:22:39.156328+00:00
position_column: done
position_ordinal: ffb180
title: 'SK-8: SkillsRegistry.stopWatching()'
---
## What
Request from FoundationModelsACPAgent (^enh25yn, agreed with testudoapp-75). A closed ACP session keeps its skills registry, and the registry keeps its watcher. Add a public, idempotent `SkillsRegistry.stopWatching() async`, with the same shape as `AgentRegistry.stopWatching()` of FoundationModelsAgents.

File: `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift` (`ReloadCoordinator`). The call stops the `DotfolderWatcher` and cancels the task that follows the marketplace updates. Then it waits until a rebuild that a change started is complete.

## Acceptance Criteria
- [x] After `stopWatching()` returns, a change on disk gives no rebuild and no `onReload` value.
- [x] The current skills stay readable.
- [x] A second call does nothing. A registry with `watch: false` and no provider: the call does nothing.
- [x] An explicit `reload()` after the stop still works, and does not start the watcher again.

## Tests
- [x] `Tests/FoundationModelsSkillsTests/StopWatchingTests.swift`: two watched registries on one folder. Stop one. Write a new skill. Wait on the control registry for the new skill (a condition, not a clock). The stopped registry did not change and has no watcher.
- [x] `swift test` passes.

## Workflow
- Use `/tdd`.