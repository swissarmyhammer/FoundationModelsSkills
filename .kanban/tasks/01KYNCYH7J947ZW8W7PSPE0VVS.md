---
depends_on:
- 01KYNCX7H8EQBNT1XES7D0DBG3
- 01KYNCV471YM5S7MVZMHXM25QJ
- 01KYNCVGQNCFM67RHYYC88BZ6F
- 01KYNCWVSV6MH31BMHGG6C46AJ
position_column: todo
position_ordinal: '9380'
title: 'skills-demo executable: CLI, --chat, --watch modes'
---
## What
The §11 dual-use demo: one executable target in the root `Package.swift` (the NotesTool shape — compare `../FoundationModelsOperationTool/Examples/NotesTool`), driving the complete `Examples/skill-library/`.

- `Examples/skills-demo/main.swift` (executable target `skills-demo` in the root manifest):
  - **Default — CLI mode** (§7.2): `skills-demo skill list`, `skills-demo skill search "commit my changes"`, `skills-demo skill use commit --arguments "fix parser"` over the fixture library (explicit `defaultsDirectory`/`userDirectory` — never the real home dir).
  - **`--chat`** — a root `LanguageModelSession` with the fused tool + `registry.preloadedBodies()` in `Instructions` (the §10 assembly sketch), gated on model availability (`SystemLanguageModel` availability check → clean message when unavailable); scripted prompts drive the `search skill` → `use skill` round trip. Add a `SKILLS_DEMO_FORCE_UNAVAILABLE` env seam that forces the unavailable branch so the degradation path is testable deterministically on any machine.
  - **`--watch`** — run, print reload events as they land: searcher `update(items:)` forwarding, refreshed preloads, updated `/` listing — the human-driven twin of the hot-reload test.
- Wire `registry.onReload → context.searchAgent.update(items:)` + preload refresh exactly as plan §10 shows — this demo is the only place the full assembly appears end to end; keep it copy-pasteable as documentation.

## Acceptance Criteria
- [ ] `swift build` builds library + demo in one pass
- [ ] All three CLI-mode commands produce correct output against the fixture library
- [ ] `--chat` degrades cleanly when the model is unavailable — discharged by the spawn test below using the force-unavailable env seam
- [ ] `--watch` reflects a fixture edit live (manually verified once; automated coverage is the hot-reload test — the demo test only asserts mode startup/teardown)

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillsDemoTests.swift` — spawn the built binary for the three CLI-mode commands and snapshot stdout; spawn `--chat` with `SKILLS_DEMO_FORCE_UNAVAILABLE=1` and assert the clean unavailable message + zero exit; `--watch` starts and exits cleanly on SIGTERM
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.