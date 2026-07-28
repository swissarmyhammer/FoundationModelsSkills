---
depends_on:
- 01KYNCR37A3M7MYKAH7T0QREYS
position_column: todo
position_ordinal: '8680'
title: Render pipeline skeleton (ordered passes, identity transforms)
---
## What
The M2 render scaffold (plan §5): wire the three-pass pipeline shape with identity transforms so ordering, single-shot semantics, and the body/metadata split are fixed before real pass logic lands.

- `Sources/FoundationModelsSkills/Render/RenderPipeline.swift`:
  - `RenderRequest` (skill body or metadata value, arguments, skill directory, winning layer, policy).
  - Ordered passes: (1) argument/variable substitution, (2) shell injection, (3) Stencil — each a `RenderPass` protocol value; passes run once, output of pass N is NEVER re-scanned by pass N or earlier (plan: single-shot, no re-scanning).
  - Two pass-sets: body render = passes 1+2+3; `description`/`metadata` render = passes 1+3 only (shell never runs at metadata-build time, decision #25).
  - `RenderPolicy` struct holding `disableShellExecution` and `disableScriptExecution` (consumed later; lives here so the registry can own it at construction, decisions #25/#28).
- Passes are identity functions in this task; each later render task replaces one.

## Acceptance Criteria
- [ ] Pipeline runs passes in fixed order 1→2→3 (observable via a recording fake pass)
- [ ] Metadata render path never invokes pass 2
- [ ] A pass output containing pass-1 syntax (e.g. `$0`) is not re-substituted
- [ ] `RenderPolicy` is plumbed to every pass invocation

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/RenderPipelineTests.swift` — order recording; metadata-path pass-set; no-re-scan invariant with identity+marker fakes
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.