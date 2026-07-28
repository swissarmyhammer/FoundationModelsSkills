---
depends_on:
- 01KYNCTMRAN6DEBBJGV5GE1MNN
position_column: todo
position_ordinal: 8c80
title: 'Render pass 3: TemplateEngine wiring (trust, ladder, partials)'
---
## What
Implement §5 pass 3 via Extras' `TemplateEngine` (decisions #1/#2/#29), replacing the identity transform.

- `Sources/FoundationModelsSkills/Render/StencilPass.swift`:
  - Build the `TemplateContext`: explicit context (skill arguments land here too) > environment variables as flat keys (`{{ HOME }}`) > well-known values (`working_directory`, `date`, `hostname`, `dotfolder_name`) — Extras' precedence ladder; read Extras' `TemplateEngine`/`TemplateContext`/`Trust` API first and use it, never raw Stencil.
  - Trust from the skill's winning layer: defaults → `.trusted`; user/project → `.untrusted` (whitelist + include-depth 8 + 1 MiB output + 100k-iteration budgets come from Extras).
  - `{% include "header" %}` resolves through the stack's layered `_partials/` dirs (Extras' `DotfolderLoader` path — nearest layer wins).
  - Because pass 1 ran before Stencil, `$`-tokens inside partial files are never argument-substituted (decision #16) — cover with a test, not code.
  - Add fixture `Examples/skill-library/project/.skills/env-report/SKILL.md` — `{{ HOME }}` / `{{ working_directory }}` ladder rendering; ensure `user/_partials/header.md` is exercised by a fixture body using `{% include "header" %}`.

## Acceptance Criteria
- [ ] `env-report` golden render resolves env + well-known values through the ladder (env injected explicitly in tests for determinism)
- [ ] A project-layer skill using a non-whitelisted Stencil tag draws the untrusted-rejection diagnostic (§13 named case)
- [ ] `{% include "header" %}` renders the partial; a `$0` inside the partial stays literal
- [ ] Defaults-layer fixture renders trusted (same tag allowed)

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/StencilPassTests.swift` — ladder precedence table; trust-mapping matrix; include + partial `$`-literal case; untrusted-rejection diagnostic — all through Extras' REAL TemplateEngine, no mocks (plan §13)
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.