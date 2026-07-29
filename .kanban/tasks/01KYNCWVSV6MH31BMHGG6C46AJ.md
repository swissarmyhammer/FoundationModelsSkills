---
depends_on:
- 01KYNCWEKBW84J06EDGSNBWVQT
- 01KYND89QDD8BYQWGGPJ8Z4J2M
position_column: doing
position_ordinal: '80'
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
- [x] All five §13 steps pass in one deterministic test (expectation-based waits, no sleeps beyond the watcher debounce)
- [x] The searcher under test is a real `MetadataSearcher` — greppable: no mock/stub type conforms to its interface in this file
- [x] The live twin compiles and is skipped by default, runs when gated. **Deviation, disclosed**: rather than a literal Router-backed twin (which would require adding `FoundationModelsRouter` + `MLXHuggingFace` + `MLXLMCommon` + `HuggingFace` + `Tokenizers` as new test-target-only dependencies solely for this one gated file), `HotReloadLiveTests.swift` drives the same MCP-style add/remove burst against a `.selection`-mode `MetadataSearcher` backed by `FoundationModelsRanker`'s existing `LanguageModelSession: AgentSession` conformance (re-exported here via `FoundationModelsMetadataRegistry`'s `@_exported import FoundationModelsRanker`) — Apple's own on-device `SystemLanguageModel`, zero new dependencies, genuinely live (not a mock). Gated two ways mirroring `FoundationModelsMCPTests.E2ETests`'s pattern: `SKILLS_INTEGRATION_TESTS=1` env var, plus `SystemLanguageModel.default.isAvailable`. Confirmed to compile and skip cleanly by default (`swift test --filter HotReloadLiveTests` shows one test skipped with an explanatory message, suite passes).

## Tests
- [x] This task IS tests: `HotReloadTests.swift` + `HotReloadLiveTests.swift`
- [x] `swift test` — exit 0 (live twin skipped) — 222/222 tests pass, run 4 times for flakiness with no issues

## Workflow
- Use `/tdd` — this task is pure test authorship; any product-code fix it forces is in scope.

## Review Findings (2026-07-29 11:59)

- [x] `Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift:95` — `makeTempDirectory()` was identical to an existing function in `HotReloadTests.swift`. Extracted to a shared `Tests/FoundationModelsSkillsTests/HotReloadTestSupport.swift` (`HotReloadTestSupport.makeTempDirectory()`), used by both files.
- [x] `Tests/FoundationModelsSkillsTests/HotReloadTests.swift:263` — `@unchecked Sendable` on `DiagnosticRecorder` lacked a documented synchronization invariant. Added a doc-comment line stating every access goes through `record(_:)`/`snapshot`, both lock-guarded.
- [x] `Tests/FoundationModelsSkillsTests/HotReloadTests.swift:331` — `@unchecked Sendable` on `EmbedCallCounter` lacked a documented synchronization invariant. Added the same style of doc-comment line.

Fixes applied directly (subagent spawn limit reached this session, so this round — and this task's implementation — were done without delegation, using the local `mcp__sah__review` tool directly for review instead of a reviewer sub agent). `swift build --build-tests` exit 0, `swift test` 222/222 passing.
