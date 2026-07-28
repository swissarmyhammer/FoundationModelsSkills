---
depends_on:
- 01KYNCYH7J947ZW8W7PSPE0VVS
- 01KYNCY323EQ7RDC8X1HQJNFSJ
- 01KYNCT6G9K9RYE4PYZKVXSZMZ
position_column: todo
position_ordinal: '9480'
title: Diagnostics polish, README, and API docs (M7)
---
## What
The M7 close-out: make the diagnostic surface and documentation match the plan's promises.

- Diagnostics polish: every diagnostic carries winning-layer provenance (plan §8 — hosts show WHERE a skill came from); consistent one-line rendering; a `registry.diagnostics` snapshot API is stable and documented.
- `README.md` — follow the sibling READMEs' shape (`../FoundationModelsOperationTool/README.md` as the model): what it is, the §10 assembly example (kept compiling — lift from the demo), the op vocabulary table (§7 + §7.3), visibility table (§6), the security posture section stating plainly: shell/scripts run with host privileges, no OS sandbox in v1 (decision #28), trust-gate untrusted project layers, server-side-provider transcript exposure (§8), and the context-compaction host note.
- Platform posture section (plan §8): macOS primary with the full feature set; iOS = the outcome the scaffold task recorded (graceful stub, or the documented deviation naming the macOS-only dependency) — no shell/script attempted on iOS either way.
- Doc comments on every public type/member; document the §7.1 four-consumer diagram and the tier-1 divergence (decision #27) on `SkillsRegistry`.
- Sweep: all `swift build`/`swift test` warnings fixed; `Package.swift` comments name each dependency's role.

## Acceptance Criteria
- [ ] README's example code compiles (extract-and-build check in a test or the demo IS the example)
- [ ] Every public symbol has a doc comment (`swift build -Xswiftc -warnings-as-errors` clean, or a documentation-coverage grep script in the test target)
- [ ] Security posture section covers all four §8 documented consequences
- [ ] Platform posture documented: macOS full feature set; iOS unavailable/stubbed, no shell/script attempted

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/DiagnosticsRenderingTests.swift` — provenance presence + rendering snapshot for each diagnostic kind
- [ ] `swift test` — exit 0, zero warnings in build output

## Workflow
- Use `/tdd` — write failing tests first where testable (diagnostics rendering), then implement.