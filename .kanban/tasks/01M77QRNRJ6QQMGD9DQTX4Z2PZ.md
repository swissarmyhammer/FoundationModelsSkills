---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'SK-8: SkillsRegistry.stopWatching()'
---
## What
Request from FoundationModelsACPAgent (^enh25yn, agreed with testudoapp-75). A closed ACP session keeps its skills registry, and the registry keeps its watcher. Add a public, idempotent `SkillsRegistry.stopWatching() async`, with the same shape as `AgentRegistry.stopWatching()` of FoundationModelsAgents.

File: `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift` (`ReloadCoordinator`). The call stops the `DotfolderWatcher` and cancels the task that follows the marketplace updates. Then it waits until a rebuild that a change started is complete.

## Acceptance Criteria
- [ ] After `stopWatching()` returns, a change on disk gives no rebuild and no `onReload` value.
- [ ] The current skills stay readable.
- [ ] A second call does nothing. A registry with `watch: false` and no provider: the call does nothing.
- [ ] An explicit `reload()` after the stop still works, and does not start the watcher again.

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/StopWatchingTests.swift`: two watched registries on one folder. Stop one. Write a new skill. Wait on the control registry for the new skill (a condition, not a clock). The stopped registry did not change and has no watcher.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd`. #step1