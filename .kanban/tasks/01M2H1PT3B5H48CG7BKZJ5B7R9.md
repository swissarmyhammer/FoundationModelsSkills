---
assignees:
- claude-code
depends_on:
- 01M2H125CCEZMT2PZAW6DRYE1R
position_column: todo
position_ordinal: '9780'
title: 'MarketplaceStore: pins and .nextLaunch'
---
## What

marketplace.md §8.3 (pins) and §8.4 (`.nextLaunch`).

In `Sources/FoundationModelsSkills/Marketplace/MarketplaceStore.swift`, `MarketplacePolicy.swift`, and `MarketplaceState.swift`:
- `pin(_ id: String, sha: String) async throws` and `unpin(_ id: String) async throws` store `pinnedSha` in `state.json`. A `sha:` field on the source also pins it. A pinned source never updates automatically; `check()` still reports a newer head with `.updateAvailable`. `update(id, force: true)` on a pinned source fetches the pinned SHA only.
- `MarketplacePolicy.applyUpdates: ApplyUpdates` (`.immediately` default, `.nextLaunch`). With `.nextLaunch`, an update materializes the new snapshot, records it as pending in `state.json`, and swaps `current` only at the next `start()`.

- [ ] `pin` and `unpin` with `state.json`
- [ ] The `sha:` source pin, and pinned behavior in `start()` and `check()`
- [ ] `.nextLaunch` with the pending snapshot
- [ ] Tests

## Acceptance Criteria
- [ ] A pinned source never fetches a newer head automatically, and `check()` reports the newer head
- [ ] `unpin` lets the next automatic update fetch the head
- [ ] With `.nextLaunch`, `current` changes only after the next `start()`, and a pending snapshot survives a store restart

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplacePinTests.swift` with `GitFixtureRepository` and a temporary cache: pin through the source and through `pin(_:sha:)`; `check()` with a pin; `unpin`; `.nextLaunch` across two store instances on one cache
- [ ] Run `swift test --filter MarketplacePinTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace