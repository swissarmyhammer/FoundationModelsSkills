---
comments:
- actor: claude-code
  id: 01kyqzfmxa0vmv8s0j8verreqq
  text: |-
    Implemented span-based quarantine to close the §5 no-re-scan hole: new Sources/FoundationModelsSkills/Render/QuarantinedText.swift (QuarantinedText/Span/SpanBuilder). RenderPass protocol changed from `render(_ text: String, request:) -> String` to `render(_ text: QuarantinedText, request:) -> QuarantinedText`; RenderPipeline.run wraps request.text once as a single .original span and flattens only after all passes finish. ArgumentSubstitution and ShellInjection now emit substituted/executed values as `.quarantined` spans (never rescanned by later passes); StencilPass renders only `.original` spans through TemplateEngine, leaving `.quarantined` spans as literal passthrough.

    Verified: model-supplied argument containing `` !`touch pwned.txt` `` renders literal with no process spawned; argument/shell-output values containing `{{ HOME }}`/`{% include %}` stay literal and never reach the Stencil engine.

    Updated existing pass-level unit tests (ArgumentSubstitutionTests, ShellInjectionTests, StencilPassTests) to wrap/unwrap via QuarantinedText — mechanical, no behavior change to what they assert. Per the task's explicit ask, replaced the old mock-based (ConstantOutputPass/SubstitutingPass) "no re-scan" tests in RenderPipelineTests.swift and ShellInjectionTests.swift with versions using the REAL ArgumentSubstitution/ShellInjection/StencilPass passes together — the mocks couldn't actually exercise the cross-pass re-scan bug since ConstantOutputPass ignored its input entirely. Added new Tests/FoundationModelsSkillsTests/RenderPipelineNoRescanTests.swift with the full acceptance-criteria composition matrix (4 tests): shell-injection-in-argument no-exec, stencil-syntax-in-argument stays literal, shell-output-containing-$0/`` !`cmd` ``/`{{ }}` stays literal end-to-end, and all three combined in one render.

    Known, deliberate limitation (documented in StencilPass's doc comment): a Stencil control-flow construct (e.g. `{% if %}...{% endif %}`) can no longer legitimately span across a quarantined splice, since each `.original` span renders as its own independent template. This was never a supported/intended pattern per plan.md §5's "not re-scanned" requirement, and no existing fixture or test relied on it.

    All 262 tests passing (258 prior + 4 new).
  timestamp: 2026-07-29T22:21:22.218473+00:00
- actor: claude-code
  id: 01kyqzwg2d21dw1sx8mbd4edma
  text: Clean review (task k5tp8u2ye, sha 96169ed..0d2e736) — 0 findings on first pass. Moved to done. All 262 tests passing.
  timestamp: 2026-07-29T22:28:23.245272+00:00
position_column: done
position_ordinal: '9580'
title: 'Enforce §5 no-re-scan: quarantine substituted args and shell output'
---
## What
CRITICAL variance from plan §5 ("each pass single-shot and **not re-scanned** by later passes"; shell "output inlined as plain text, **not** re-scanned"). Today each pass only avoids re-scanning its own output: `RenderPipeline.run` threads pass N's whole output into pass N+1 (`Sources/FoundationModelsSkills/Render/RenderPipeline.swift:288-293`), so:
- A `use skill` argument containing `` !`cmd` `` at line start is EXECUTED by pass 2 (`ArgumentSubstitution.swift:73-82` inserts verbatim → `ShellInjection.swift:62-83` scans it). Arguments are model-supplied (`Operations/UseSkill.swift:136`) — this is model-controlled command execution.
- Shell stdout containing `{{ HOME }}` / `{% include %}` is expanded by pass 3 (`StencilPass.swift:108-112`), reachable via `registry.call` and `preloadedBodies`.

Fix: track spliced ranges through the pipeline (mask/placeholder map or span bookkeeping): text inserted by pass 1 (argument values) must be invisible to passes 2 and 3; text inserted by pass 2 (shell output) must be invisible to pass 3. Restore the spliced text after each later pass runs. Only original body text may trigger substitution, shell execution, or templating.

Also fix the tests that hid this (they substitute `IdentityRenderPass` for Stencil): `Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift:194-207`, `RenderPipelineTests.swift:112-125`.

## Acceptance Criteria
- [ ] An argument value containing `` !`echo pwned` `` renders as literal text; no process is spawned (side-effect file probe stays absent)
- [ ] An argument value containing `{{ HOME }}` / `{% include "header" %}` stays literal after a full body render
- [ ] Shell output containing `{{ HOME }}`, `$0`, and `` !`cmd` `` stays literal end-to-end
- [ ] A composition test runs REAL pass 1 + REAL pass 2 + REAL pass 3 together (no identity mocks) over a fixture body and passes the three assertions above

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/RenderPipelineNoRescanTests.swift` — the full-real-pipeline composition matrix above
- [ ] Update `ShellInjectionTests` / `RenderPipelineTests` mock-based no-re-scan cases to use the real passes
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write the failing composition tests first (they fail today), then implement span quarantine to make them pass.