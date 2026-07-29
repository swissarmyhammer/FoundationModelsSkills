---
position_column: todo
position_ordinal: '9780'
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