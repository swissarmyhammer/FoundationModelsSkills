---
position_column: doing
position_ordinal: '80'
title: 'Resolver vocabulary vs #21: run-skill alias, plural nouns, CLI positional ids'
---
## What
Three places where shipped behavior contradicts the plan's resolver/CLI vocabulary, all rooted in `../FoundationModelsOperationTool`; resolve each by upstream change or an explicit plan amendment — not by leaving the contradiction silent:

1. **`run skill` does not dispatch** (decision #21 mandates `run → use`): the alias was deliberately dropped because upstream's verb rewrite is unconditional per-verb, not per-(verb,noun) (`Operations/SkillsTool.swift:95-102`; upstream `OperationResolver.swift:100-105`), and `run` must stay reserved for `run script`. Preferred fix: upstream noun-scoped aliases (`(verb: "run", noun: "skill") → use`). Fallback: amend plan #21 to carve out `run` and update the pinning test's rationale comment (`SkillOperationsTests.swift:271-286`).
2. **Plural nouns do not resolve** (#21: "plural/reversed/`_`-`-` tolerated"): `skills list` → Unknown operation (upstream `OperationResolver.swift:100-106` does no singularization; pinned at `SkillOperationsTests.swift:223-237`). Preferred fix: upstream trailing-`s` singularization in `matchOpString`. Fallback: plan amendment.
3. **§7.2's documented CLI syntax does not parse**: `skills skill use deploy --arguments production` (positional id) fails — the fallback CLI leaf accepts only `--name value` flags (upstream `OperationsCLI/FallbackOperationCommand.swift:34-35, 96-104`); working form is `--id deploy`. Preferred fix: upstream positional-first-required-param support. Fallback: amend plan §7.2's examples to flag form.

## Acceptance Criteria
- [ ] Each of the three deltas is resolved: behavior matches the plan, or plan.md is amended with the recorded rationale — no silent contradiction remains
- [ ] If upstream changes land: `run skill` dispatches to use, `run script` still dispatches to run script, `skills list` resolves, and the §7.2 positional example round-trips — each pinned by a test
- [ ] Pinning tests updated to assert the RESOLVED contract, not the workaround

## Tests
- [ ] Updated resolver-alias matrix in `SkillOperationsTests.swift`; CLI syntax cases in `SkillsCLITests.swift`
- [ ] `swift test` — exit 0 (this repo and upstream if changed)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.