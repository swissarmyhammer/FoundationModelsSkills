---
comments:
- actor: claude-code
  id: 01kyr1ww7dfn36f7q963vn6ctv
  text: |-
    Implemented and checkpointed at 2b8d55b:
    - Made `SkillsRegistry.init(layers:policy:watch:)` public (was private) — the sanctioned way for a host to trust-label a bare root `.defaults`, since `init(roots:)` tags every root `.project` and the defaults-trusted mapping was otherwise unreachable.
    - Removed `StencilPass.trustOverrides` entirely (field, init param, doc comments) — redundant with the above and unauthorized by plan.md #29. Verified via grep it was only referenced in `StencilPass.swift` and its own two tests.
    - Fixed `WellKnownValues.projectDotfolderName(in:)` to use `.last(where:)` instead of `.first(where:)` so the highest-precedence `.project` layer wins (matters for `init(roots:)`, which tags every root `.project`).
    - Replaced the two broken `trustOverrideForces...` tests in `StencilPassTests.swift` with: a `SkillsRegistry.init(layers:)` end-to-end trust-matrix test (defaults root renders trusted, others don't), an `init(roots:)` all-untrusted regression test, a `WellKnownValues.current(layers:)` unit test proving highest-precedence derivation, and an end-to-end `{{ dotfolder_name }}` derivation test over real layers.
    - Full suite green: 270/270 tests passing.
    - Scoped review (`review sha HEAD~1..HEAD`) is running in the background (task kidnscjzm) — awaiting result before moving to done.
  timestamp: 2026-07-29T23:03:32.845111+00:00
- actor: claude-code
  id: 01kyr27deamv041zs13gw3gkjx
  text: 'Review clean after one round of findings (dedup temp-directory helper). Checkpoints: 2b8d55b (implementation), dc86173 (dedup fix). Full suite green at 270/270. Moved to done.'
  timestamp: 2026-07-29T23:09:18.154286+00:00
position_column: done
position_ordinal: '9880'
title: Fix trust mapping and dotfolder_name for roots-constructed registries
---
## What
Variance from §5/#29: trust must map from the winning layer (defaults → `.trusted`, user/project → `.untrusted`), and #29 makes `init(roots:)` the canonical interface — but `SkillsRegistry.init(roots:)` tags EVERY root `.project` (`Registry/SkillsRegistry.swift:315-317`), so:
- The defaults-trusted mapping is unreachable on the canonical path (only `init(stack:)` gets it).
- `{{ dotfolder_name }}` resolves via `layers.first(where: { $0.source == .project })` (`Render/StencilPass.swift:289-293`), which under `init(roots:)` is the LOWEST-precedence root — the wrong layer.

Fix:
- Extend `init(roots:)` so the host can label roots (e.g. accept `[(URL, DotfolderStack.Source)]` or a parallel `trust:`/`sources:` parameter; default remains all-untrusted — the safe direction).
- Fix `WellKnownValues.projectDotfolderName` to resolve from the HIGHEST-precedence project-source layer (last matching, not first), and add a real-layer derivation test (today the only test injects the value directly, `StencilPassTests.swift:269`).
- Decide `StencilPass.trustOverrides` (`StencilPass.swift:52, 121-123`): it can invert the mandated mapping and nothing in §5/#29 authorizes it. Either remove it or document it as deliberate host API and route the labeled-roots trust through it consistently.

## Acceptance Criteria
- [ ] A roots-constructed registry with a designated defaults root renders that root's skills `.trusted` and the rest `.untrusted`
- [ ] Unlabeled `init(roots:)` keeps today's all-untrusted behavior
- [ ] `{{ dotfolder_name }}` renders the winning project root's directory name for both `init(stack:)` and labeled `init(roots:)`
- [ ] `trustOverrides` is removed or documented + consistently used (no unspecified escape hatch)

## Tests
- [ ] Extend `StencilPassTests` — trust matrix over labeled roots; dotfolder_name derivation from real layers (both constructors)
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.