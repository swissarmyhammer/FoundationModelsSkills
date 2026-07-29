---
position_column: todo
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