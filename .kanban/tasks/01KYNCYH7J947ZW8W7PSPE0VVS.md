---
comments:
- actor: claude-code
  id: 01kyqx64476173p89c6zthfny4
  text: |-
    Implemented: `skills-demo` executable target added to root Package.swift (`Examples/skills-demo/`), depending on the library + commonDependencies. Files: FixtureStack.swift (#filePath-relative DotfolderStack over Examples/skill-library, hermetic), SkillsDemoAssembly.swift (shared registry+context builder), SkillsDemoMain.swift (@main entry, dispatches --chat/--watch/default CLI), ChatMode.swift (scripted search→use round trip, SKILLS_DEMO_FORCE_UNAVAILABLE env seam), WatchMode.swift (@MainActor, registry.onReload → searchAgent.update(items:) wiring, SIGTERM handled via DispatchSource + SIG_IGN, exits 0 cleanly).

    Default CLI verified manually: `skill list`, `skill search --query`, `skill use --id <id> --arguments <text>` all work against the fixture library (note: plan.md's prose example `skill use commit --arguments ...` is illustrative — the real fallback-CLI grammar requires `--id commit`, matching every other op's named-flag convention in this family, e.g. NotesTool's `note get --id`).

    Tests: Tests/FoundationModelsSkillsTests/SkillsDemoTests.swift spawns the built binary (mirrors FoundationModelsExtras' ExtrasDemoIntegrationTests pattern) — 3 CLI-mode tests, 1 forced-unavailable --chat test, 1 --watch start/SIGTERM/clean-exit test. Full suite: 258/258 passing.

    Discovered along the way: WatchMode's SIGTERM handler must be @MainActor (Swift 6 strict concurrency flags a plain nonisolated static var DispatchSourceSignal as unsafe global mutable state) — fixed by isolating the whole enum to @MainActor.
  timestamp: 2026-07-29T21:41:12.967171+00:00
depends_on:
- 01KYNCX7H8EQBNT1XES7D0DBG3
- 01KYNCV471YM5S7MVZMHXM25QJ
- 01KYNCVGQNCFM67RHYYC88BZ6F
- 01KYNCWVSV6MH31BMHGG6C46AJ
position_column: doing
position_ordinal: '80'
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