---
assignees:
- claude-code
depends_on:
- 01M2H10AWYB2KQ6P0N4B43PG6M
position_column: todo
position_ordinal: '9080'
title: Add update checks and automatic update to MarketplaceStore (no built-in times)
---
## What

marketplace.md §8.1–§8.3 and decisions 13 and 15. The package has no built-in time value. A check runs at `start()` and on request. A periodic check runs only when the host gives an interval. Pins and `.nextLaunch` are a separate task.

In `Sources/FoundationModelsSkills/Marketplace/MarketplaceStore.swift` and `MarketplacePolicy.swift`:
- `MarketplacePolicy` gets `checkInterval: Duration?` (default `nil`), `autoUpdate: Bool` (default `true`), `checkOnly: Bool` (default `false`), and `fetchTimeout: Duration?` (default `nil`). `SKILLS_MARKETPLACE_AUTOUPDATE=0` in the environment has the same effect as `autoUpdate: false`.
- `func check() async -> [MarketplaceStatus]`: one `remoteHead` for each git source. It publishes `.checked`, and `.updateAvailable` when the head differs. It never fetches.
- **Coalescing:** while a check or update of a marketplace is in progress, another request for it waits for the same `Task`. No second remote connection.
- `start()`: check each source. Update it when `autoUpdate` is on and `checkOnly` is off; otherwise publish `.updateAvailable`.
- Interval: only when `checkInterval` is not `nil`, a loop checks at that interval until `stop()`. The internal init takes a clock (`any Clock<Duration>`), so tests use a manual clock.
- `stop()` cancels the loop and any fetch in progress; `current` does not change. When `fetchTimeout` is set, a fetch that takes longer is cancelled and publishes `.failed` with `keptVersion`.

- [ ] Policy fields and the environment switch
- [ ] `check()` with coalescing
- [ ] Update rules at `start()`: auto, off, `checkOnly`
- [ ] The optional interval loop and `stop()`
- [ ] `fetchTimeout` and cancellation

## Acceptance Criteria
- [ ] With the default policy, `start()` makes one remote-head call for each source, and no later call happens until a request comes
- [ ] Two concurrent `check()` calls make one remote-head call
- [ ] `autoUpdate: false`, the environment switch, and `checkOnly` publish `.updateAvailable` and never fetch
- [ ] `stop()` during a fetch ends the fetch, and `current` does not change
- [ ] A fetch longer than `fetchTimeout` fails with `keptVersion`

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceUpdateTests.swift` with the counting `GitTransport` double, a blocking transport double, and a manual clock: default policy (no later calls); coalesced checks; auto-update fetch; `autoUpdate: false`; `checkOnly`; the environment switch; the interval loop advances only when the manual clock advances; `stop()` ends the loop; `stop()` during a blocked fetch (`current` unchanged); `fetchTimeout` with the manual clock
- [ ] Run `swift test --filter MarketplaceUpdateTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace