---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2kr8hx7vja30ga95kmzsvjc
  text: |
    Research notes for the next agent.

    Shapes that the card needed, and where they are:
    - The display id of a marketplace is the `name` field of `.claude-plugin/marketplace.json`, not the alias. Two `GitFixtureRepository` fixtures both make a folder named `fixture.git`, thus both sources need an `alias` or `MarketplaceIdentity` refuses the whole list with a duplicate pre-fetch key.
    - `SnapshotWriter.copyPartials` copies the `_partials/` folder of the parent folder of each selected skill. With skills at `skills/<id>`, `skills/_partials/sah-header.md` lands at `<snapshot>/_partials/sah-header.md`.
    - `DotfolderLoader` accepts the redundant `_partials/` prefix of an include name, thus `{% include "_partials/sah-header" %}` resolves.
    - "alpha comes from A" reads best from `registry.commandListing()`: the `source` field is `<display id>@<catalog version or short commit>`, and it is `nil` for a local skill. A well-formed skill raises no diagnostic, thus provenance cannot come from `registry.diagnostics`.
    - `MarketplaceStore.update()` publishes a layer update only when a pass installs a snapshot. Marketplace B changes nothing, thus one `update()` over both marketplaces still gives exactly one reload.
    - `check()` never installs, also with the default policy.

    Two mutation probes proved that the new assertions bind, and each failed for the correct reason:
    - `alpha` asserted against the header of marketplace B: failed. Decision 9 partial scope holds.
    - The snapshot set asserted as `[second]` only: failed. The store keeps the one previous snapshot.
  timestamp: 2026-09-16T00:00:59.303103+00:00
- actor: claude-code
  id: 01m2kr8qvjpy4abm94a1zq49gn
  text: |
    ### implement — changed
    - evidence: 4 files. New `Tests/FoundationModelsSkillsTests/MarketplaceEndToEndTests.swift`. `FakeEmbedder`, `EmbedCallCounter` and `EmbedGate` moved out of `HotReloadTests` into `HotReloadTestSupport.swift` as internal types. `ReloadTestSupport` gained `forward(_:to:recordingInto:)`, the two shared wait durations, and a one-argument `expectExactlyOneEvent(_:since:)`; `HotReloadTests.subscribe` now calls the shared forwarder instead of its own copy. `swift build --build-tests`: zero warnings. `swift test`: 678 tests in 52 suites passed.
    - next: `/review`
  timestamp: 2026-09-16T00:01:05.394681+00:00
- actor: claude-code
  id: 01m2krdhyvkfgs52qvffd5tfpc
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` clean, 0 warnings. `swift test` run 3 times in a row: 678 tests, 52 suites, 0 failed, 0 skipped, each time (durations ~7.0s, 7.0s, 7.1s test-run time). `MarketplaceEndToEndTests` suite (test `theMarketplaceCycleFetchesOverridesUpdatesOnceAndKeepsTheLastGoodSnapshot`) passed all 3 runs, showing it is not flaky.
    - next: ready for review
  timestamp: 2026-09-16T00:03:43.195273+00:00
depends_on:
- 01M2H125CCEZMT2PZAW6DRYE1R
- 01M2H0ZGHTB3M84QY776YSQYVJ
- 01M2H0ZTENV1JH7AW6ABAXZHC5
position_column: doing
position_ordinal: '80'
title: 'End-to-end marketplace test: fetch, local override, scoped partials, update, one reload'
---
## What

marketplace.md §13 (the update cycle). One test proves that the parts work together, in the same shape as the hot-reload test in plan.md §13. It is hermetic: libgit2 over `file://`, with no network and no `git` binary. If the test finds a defect, fix it in this task.

1. Move the counting embedder (`FakeEmbedder`, now `private` in `Tests/FoundationModelsSkillsTests/HotReloadTests.swift`) to `Tests/FoundationModelsSkillsTests/HotReloadTestSupport.swift` as an internal type, and use it from both files.
2. With `GitFixtureRepository`, make marketplace A in our own format (marketplace.md §3.2–3.3): `.claude-plugin/marketplace.json` with one plugin, `skills/alpha/SKILL.md` and `skills/beta/SKILL.md`, both with `{% include "_partials/sah-header" %}`, and `skills/_partials/sah-header.md`. Make marketplace B with its own `skills/_partials/sah-header.md` (different text) and a skill `gamma` that includes it. Make a local `user` layer with its own `beta`.
3. Build `MarketplaceStore(sources: [A, B])` with a temporary cache, `SkillsRegistry(marketplaces:stack:)`, and a `SkillsTool` over the registry with the counting embedder.
4. `await store.start()`. Assert: `alpha` comes from A and renders A's header; `gamma` renders B's header; `beta` is the local one, and the shadow message names marketplace A; all marketplace skills render untrusted.
5. Commit a change to `alpha` in A. `check()` reports `.updateAvailable` for A. Then `update()`. Assert: exactly one `onReload` value; exactly one searcher `update(items:)`; `use skill alpha` shows the new body; the old snapshot is kept as the one previous snapshot.
6. Make A unreachable (move the fixture folder). `update()` publishes `.failed` with `keptVersion`, and `alpha` still renders.

- [x] Move `FakeEmbedder` to `HotReloadTestSupport.swift`
- [x] The two fixture marketplaces and the local layer
- [x] Assertions after the first sync
- [x] The check, the update cycle, and the failure case

## Acceptance Criteria
- [x] The test passes in the unit CI job with no network
- [x] Every assertion in steps 4–6 holds, and `HotReloadTests` still passes with the moved embedder

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceEndToEndTests.swift` as described
- [x] Run `swift test --filter "MarketplaceEndToEndTests|HotReloadTests"`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace