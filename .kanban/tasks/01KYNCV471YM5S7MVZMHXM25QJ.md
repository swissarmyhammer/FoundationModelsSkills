---
depends_on:
- 01KYNCTMRAN6DEBBJGV5GE1MNN
position_column: todo
position_ordinal: 8b80
title: 'Render pass 2: shell injection (macOS, body-only)'
---
## What
Implement §5 pass 2 (decision #25), replacing the identity transform.

- `Sources/FoundationModelsSkills/Render/ShellInjection.swift`:
  - `` !`command` `` recognized only at line start or after whitespace; fenced ```` ```! ```` blocks run their contents.
  - Run via `/bin/sh -c` with cwd = the skill directory and inherited env; capture merged stdout+stderr; inline output as plain text at the injection site.
  - Output is NOT re-scanned by this or any later pass invocation of pass 2 (single-shot); it flows into pass 3 as literal text only if the pipeline order says so — follow the skeleton's no-re-scan contract: injected output is never re-scanned, so mark injected ranges and have the pipeline pass them through Stencil untouched.
  - Commands re-execute on EVERY render (each `use skill`, `/command`, CLI `use`); no caching.
  - `RenderPolicy.disableShellExecution` → the pass replaces each injection with a clear inert marker (e.g. `[shell execution disabled]`) instead of running.
  - Body-only: the pipeline already routes metadata renders around pass 2 — assert that here too (precondition or test).
  - Add the fixture `Examples/skill-library/project/.skills/git-context/SKILL.md` — `preload: true` + a `!`echo`-style deterministic injection (avoid `git status` in unit tests; keep output stable).

## Acceptance Criteria
- [ ] Inline and fenced forms execute; mid-word `!`cmd`` does not
- [ ] Injected output is never re-scanned (an injected `$0` / `` !`echo hi` `` / `{{ HOME }}` stays literal end-to-end through a full body render)
- [ ] `disableShellExecution` renders inert markers, runs nothing (proven with a side-effect file probe)
- [ ] Re-render re-executes (a counter file increments per render)

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift` — recognition grammar table; execution; merged output; policy-off; re-execution; end-to-end no-re-scan through the full pipeline
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.