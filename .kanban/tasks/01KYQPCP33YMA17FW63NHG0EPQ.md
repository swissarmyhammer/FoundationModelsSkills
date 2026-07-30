---
position_column: doing
position_ordinal: '80'
title: 'Hot-reload §13 test integrity: preload step, selection tier, live twin'
---
## What
The named §13 hot-reload case passes but three of its mandates are vacuous or broken:

1. **Step 5's preload half never exercises preload**: no fixture in the scenario carries `preload: true` (`Tests/FoundationModelsSkillsTests/HotReloadTests.swift:432-433, 450-457`), so `preloadedBodies()` is `""` throughout and `#expect(!preloaded.contains("alpha"))` (`:209-210`) passes trivially. Fix: add/edit/remove a `preload: true` skill across a reload and assert `preloadedBodies()` reflects each change (also closes the reload-suite gap: no post-reload `preloadedBodies`/`diagnostics` assertion anywhere, `SkillsRegistryReloadTests.swift`).
2. **No `AgentSession` double — the selection tier has zero GPU-free coverage** (§13 mandates replicating `ScriptedAgentSession`): only `FakeEmbedder` exists (`HotReloadTests.swift:367-389`). Fix: add the scripted `AgentSession` double (~a dozen lines, mirror the sibling's pattern) and drive at least one search through the selection path, covering the id-grammar rebuild after reload.
3. **The gated live twin never reloads**: `HotReloadLiveTests.swift:85` builds `SkillsRegistry(roots:)` with `watch` defaulting to false, then forwards `registry.metadata()` after file writes (`:94-95, 100-101`) — a frozen catalog, so the add never reaches the searcher and the removal assertion (`:104`) tests against a catalog still containing `toolA`. Fix: construct with `watch: true` and await `onReload` (or explicitly rebuild) before forwarding.
4. Minor: step 1's "immediately searchable keyword-only" is not actually asserted at the pre-catch-up instant (`HotReloadTests.swift:84-94`) — assert the search succeeds while `.embedCatchUp` is still pending (FakeEmbedder can gate embedding on a signal to make the window deterministic).

## Acceptance Criteria
- [ ] Step 5 asserts real preloaded-body content before and after add/edit/remove of a `preload: true` skill
- [ ] A scripted `AgentSession` double exists and one selection-tier search runs GPU-free, post-reload
- [ ] The live twin (gated) drives an actual reload; its removal assertion can fail if reload breaks
- [ ] Keyword-only-at-that-instant asserted with a gated embedder

## Tests
- [ ] This task IS tests: extend `HotReloadTests.swift`, `HotReloadLiveTests.swift`, `SkillsRegistryReloadTests.swift`
- [ ] `swift test` — exit 0 (live twin still env-gated)

## Workflow
- Use `/tdd` — any product-code fix these tests force is in scope.