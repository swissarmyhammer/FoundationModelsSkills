---
depends_on:
- 01KYNCWEKBW84J06EDGSNBWVQT
- 01KYND89QDD8BYQWGGPJ8Z4J2M
position_column: todo
position_ordinal: 8f80
title: Hot-reload end-to-end test case (§13, named)
---
## What
The explicit, named hot-reload case from plan §13 — an acceptance criterion of M4, not incidental coverage. Drives a REAL `MetadataSearcher` through `SkillSearchAgent` (never a searcher mock), GPU-free via the `FakeEmbedder`/`ScriptedAgentSession` doubles.

- `Tests/FoundationModelsSkillsTests/HotReloadTests.swift` — end to end over a temp `.skills` root, the five steps verbatim:
  1. **Add** a `SKILL.md` → watcher fires → registry rebuilds → exactly one `update(items:)` reaches the searcher; the new id is immediately searchable keyword-only; observe `.embedCatchUp(pending:total:)` on the searcher's `onDiagnostic` channel for the async cosine catch-up.
  2. **Edit** a body → only the changed item re-embeds (counting `FakeEmbedder` asserts call counts); a no-op touch (same content) produces zero re-embeds.
  3. **Remove** a skill → its id is gone from `search skill` / `list skill` dispatch results; a stale `use skill` draws the corrective carrying the current id list.
  4. **Visibility flip on reload** — add `disable-model-invocation: true` to a skill file → the model-visible subset forwarded to `update(items:)` shrinks.
  5. **Preload + listing refresh** — `preloadedBodies()` and `commandListing()` both reflect the change; assert the fused tool's schema is byte-identical before/after (id-free, §7).
- Also add the gated integration twin (plan §13 last paragraph): the same add/remove burst against a live Router selection session, guarded by the sibling's tiny-model gating convention (`Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift`, skipped unless the gate env var is set — copy the exact gating pattern from `../FoundationModelsMetadataRegistry`'s live tests).

## Acceptance Criteria
- [ ] All five §13 steps pass in one deterministic test (expectation-based waits, no sleeps beyond the watcher debounce)
- [ ] The searcher under test is a real `MetadataSearcher` — greppable: no mock/stub type conforms to its interface in this file
- [ ] The live twin compiles and is skipped by default, runs when gated

## Tests
- [ ] This task IS tests: `HotReloadTests.swift` + `HotReloadLiveTests.swift`
- [ ] `swift test` — exit 0 (live twin skipped)

## Workflow
- Use `/tdd` — this task is pure test authorship; any product-code fix it forces is in scope.