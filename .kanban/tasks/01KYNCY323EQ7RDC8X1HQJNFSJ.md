---
depends_on:
- 01KYNCXN2E5CJY5XTMAKWN93H0
position_column: todo
position_ordinal: '9280'
title: 'run script op: triple gates + direct-exec runner (§7.3.1)'
---
## What
The gated tier-3 executor from plan §7.3/§7.3.1 (decision #28) — the sixth op in the fused tool.

- `Sources/FoundationModelsSkills/Resources/ScriptGate.swift` — the triple gate, every check at dispatch:
  1. Host policy `RenderPolicy.disableScriptExecution` (set at registry construction).
  2. Per-skill grant: parse `Script(<glob>)` tokens out of `allowed-tools` (bare `Script` = everything under `scripts/`); glob-match the requested path; no grant → corrective saying the skill has not pre-approved script execution.
  3. Trust posture is documentation (§8) — no code gate; document on the type.
- `Sources/FoundationModelsSkills/Resources/RunScript.swift` — op `"run script"`, `id`+`path` (req, under `scripts/`), `arguments?`, `timeout?` secs (default 60):
  - Sees only the model-visible catalog (§7.3): unknown or model-hidden `id` → corrective carrying the current id list (decision #22), same as list/read.
  - Path confinement (shared invariant) + must be under `scripts/`.
  - Direct exec only: file must have the executable bit AND a shebang; neither → corrective naming the fix (no interpreter guessing).
  - `Process` in its OWN process group; cwd = skill directory; env inherited; merged stdout+stderr captured; SIGKILL the group on timeout.
  - Output `RunScriptResult` exactly as §7.3: `status` (`completed`/`timed_out`/`failed`), `exitCode?`, `durationMs`, `lines` (total captured), `output` = `"{n}: {text}"` tail ≤32 entries (the Shelltool shape — compare `../FoundationModelsShelltool` for the exact tail format).
- Register the op (six ops total, within upstream's 5–15 guidance).
- Add an executable shebang script fixture under `Examples/skill-library/project/.skills/release-notes/scripts/` (deterministic output for the golden tail).

## Acceptance Criteria
- [ ] Three-gate matrix passes: policy off / no grant / non-matching glob / granted (plan §13)
- [ ] Unknown and model-hidden `id` each draw the corrective carrying the current id list
- [ ] Non-executable and shebang-less files draw the fix-naming corrective
- [ ] A sleeping script times out → process GROUP killed (child of child dies too) → `timed_out` status
- [ ] Golden `RunScriptResult` tail against the `release-notes` fixture matches

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/RunScriptTests.swift` — gate matrix; unknown/model-hidden id correctives; exec-bit/shebang refusals; timeout + group-kill (spawn `sh -c 'sleep 100 & wait'` style probe); golden result
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.