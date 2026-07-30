---
comments:
- actor: claude-code
  id: 01kyrgk0mk2sdxjkbsqtat8crf
  text: |-
    All four §13 test-integrity gaps closed:

    1. **Step 5's preload assertion was vacuous.** No fixture in the scenario carried `preload: true`. Added a `charlie` skill (`preload: true`, `disable-model-invocation: true` — the latter keeps it out of the search agent entirely, so it never perturbs the existing embed-count/diagnostic assertions) that rides alongside `alpha`/`bravo` across steps 1-3; `preloadedBodies()` snapshots captured right after each step's own reload settles are asserted in step 5, proving add/edit/remove were all actually tracked. Also closed the parallel gap in `SkillsRegistryReloadTests.swift`: no test there had ever asserted `preloadedBodies()`/`diagnostics` after a reload — new `reloadRefreshesPreloadedBodiesAndDiagnostics` covers both, including a deliberately broken sibling skill to prove diagnostics reflect the new generation without disturbing an unrelated preloaded skill's own body.

    2. **Step 1's "immediately searchable keyword-only" claim was never actually asserted at the pre-catch-up instant** — the search previously ran after the async embed catch-up had, in practice, already finished. A gated `FakeEmbedder` (`EmbedGate`) now makes the pending window deterministic: closed before the write, so `update(items:)`'s catalog-item re-embed blocks; the concurrent search runs while genuinely still pending, relying on `MetadataSearcher`'s own actor-reentrancy design. Required disabling the searcher's cosine weight (`Weights(cosine: 0)`) — a concurrent search's own cosine scoring would otherwise call the same gated embedder a second time for the query text and self-deadlock against the test's own await (found via an actual ~90s hang during implementation, root-caused and fixed rather than worked around).

    3. **`HotReloadLiveTests`' gated live twin never actually reloaded.** `SkillsRegistry(roots:)` defaults to `watch: false`, so `metadata()` stayed frozen at construction-time content regardless of the file writes in between — `toolA`'s "removal" assertion silently passed against a catalog that still contained it the whole time. Now constructs with `watch: true` and awaits a real `onReload` publication per write instead of reading `metadata()` immediately after.

    4. **No scripted `AgentSession` double existed for the selection tier** — only `FakeEmbedder` (retrieval tier) had GPU-free coverage. Added `ScriptedAgentSession` (mirrors `FoundationModelsMetadataRegistryTests.TestSupport.ScriptedAgentSession`) and `SelectionSessionFactory`, then a new test drives one `.selection`-mode search before a reload and one after: the second search only succeeds against its own scripted response if `MetadataSearcher.update(items:)` genuinely rebuilt the whole `SelectionTier` (fresh cached root session, fresh id-enum grammar) on the content change — proving the id-grammar rebuild, not merely that a stale tier happens to still respond.

    Review round 1 (checkpoint a7df7f1 + cced62e) found 7 confirmed duplication findings: `HotReloadTests.swift` and `SkillsRegistryReloadTests.swift` each reimplemented the same count-only event-tallying actor, the same generic polling loop, the same "exactly one event, then settles" assertion, and overlapping `SKILL.md` fixture-writing helpers. Extracted all of it into a new shared `ReloadTestSupport.swift`. Re-review came back clean (0 findings, 14/14 validators attempted, 0 failed).

    Checkpoints: a7df7f1 (preload lifecycle + selection-tier gate fix + live-twin reload), cced62e (scripted AgentSession double), a4dafc9 (review-driven consolidation into ReloadTestSupport.swift). 308/308 tests green, confirmed stable across multiple consecutive full-suite runs (some transient flakes observed in *pre-existing*, unrelated watcher tests under background system load — not a regression from this work).
  timestamp: 2026-07-30T03:20:18.323122+00:00
position_column: done
position_ordinal: a180
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