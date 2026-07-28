---
depends_on:
- 01KYNCTMRAN6DEBBJGV5GE1MNN
position_column: todo
position_ordinal: 8c80
title: 'Render pass 3: TemplateEngine wiring (trust, ladder, partials)'
---
## What
Implement §5 pass 3 via Extras' `TemplateEngine` (decisions #1/#2/#29 — #29 as amended: roots are host-supplied), replacing the identity transform.

- `Sources/FoundationModelsSkills/Render/StencilPass.swift`:
  - Build the `TemplateContext`: explicit context (skill arguments land here too) > environment variables as flat keys (`{{ HOME }}`) > well-known values (`working_directory`, `date`, `hostname`, `dotfolder_name`) — Extras' precedence ladder; read Extras' `TemplateEngine`/`TemplateContext`/`Trust` API first and use it, never raw Stencil.
  - Trust from the skill's winning root: defaults root → `.trusted`; user/project roots → `.untrusted` (whitelist + include-depth 8 + 1 MiB output + 100k-iteration budgets come from Extras). With host-supplied roots, "defaults" = the root the host designated as shipped defaults (lowest precedence); expose the trust mapping as data (root → Trust) with that default rule, so a host can override per root.
  - `{% include "header" %}` resolves through the layered `_partials/` directories of the SAME host-supplied roots, later roots winning — read Extras' `DotfolderLoader` seam and construct its include resolution over these roots (not over a stack Extras derives itself).
  - Because pass 1 ran before Stencil, `$`-tokens inside partial files are never argument-substituted (decision #16) — cover with a test, not code.
  - Add fixture `Examples/skill-library/project/.skills/env-report/SKILL.md` — `{{ HOME }}` / `{{ working_directory }}` ladder rendering; ensure `user/_partials/header.md` is exercised by a fixture body using `{% include "header" %}`.

## Acceptance Criteria
- [ ] `env-report` golden render resolves env + well-known values through the ladder (env injected explicitly in tests for determinism)
- [ ] A project-root skill using a non-whitelisted Stencil tag draws the untrusted-rejection diagnostic (§13 named case)
- [ ] `{% include "header" %}` renders the partial from the correct (nearest-winning) root; a `$0` inside the partial stays literal
- [ ] Defaults-root fixture renders trusted (same tag allowed); the root→Trust mapping is overridable per root

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/StencilPassTests.swift` — ladder precedence table; trust-mapping matrix incl. override; include + partial `$`-literal case; untrusted-rejection diagnostic — all through Extras' REAL TemplateEngine, no mocks (plan §13)
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.