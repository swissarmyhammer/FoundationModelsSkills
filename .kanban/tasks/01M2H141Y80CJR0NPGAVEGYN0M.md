---
assignees:
- claude-code
depends_on:
- 01M2H125CCEZMT2PZAW6DRYE1R
- 01M2H0ZGHTB3M84QY776YSQYVJ
- 01M2H0ZTENV1JH7AW6ABAXZHC5
position_column: todo
position_ordinal: '9380'
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

- [ ] Move `FakeEmbedder` to `HotReloadTestSupport.swift`
- [ ] The two fixture marketplaces and the local layer
- [ ] Assertions after the first sync
- [ ] The check, the update cycle, and the failure case

## Acceptance Criteria
- [ ] The test passes in the unit CI job with no network
- [ ] Every assertion in steps 4–6 holds, and `HotReloadTests` still passes with the moved embedder

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceEndToEndTests.swift` as described
- [ ] Run `swift test --filter "MarketplaceEndToEndTests|HotReloadTests"`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace