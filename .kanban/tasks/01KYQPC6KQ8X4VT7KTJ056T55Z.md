---
comments:
- actor: claude-code
  id: 01kyrdmzarc8357b4zghgyzw7c
  text: |-
    All three deltas resolved via plan.md amendment (the "OR plan.md is amended with the recorded rationale" fallback) — each preferred fix requires a change to the sibling `../FoundationModelsOperationTool` package, out of scope to land unilaterally here:

    1. **`run skill` never aliases to `use skill`.** The code side (`SkillsTool.verbAliasOverrides`) already carried the full rationale from an earlier task — `run` is reserved for `run script` since upstream's verb rewrite is unconditional per-verb, not per-noun, and a `run → use` entry would collide with the M6 `run script` operation. plan.md's decision #21 still listed `run` among the `use` aliases; amended to match shipped behavior.
    2. **Plural nouns (`skills list`) never resolve.** Upstream's `OperationResolver.matchOpString` compares the noun token literally with no singularization. plan.md's `## 7` vocabulary bullet and decision #21 both overstated this as "plural...tolerated"; amended to say explicitly that plurals do not resolve.
    3. **§7.2's documented CLI example never actually dispatched.** `skills skill use deploy --arguments production` (bare positional id) silently drops the `deploy` token — `FallbackOperationCommand`/`FallbackPayloadBuilder` in the sibling package only recognizes `--name value`/`-short` flags. Amended the §7.2 example (and its code-comment mirror) to the working `--id deploy` form, with an inline rationale note.

    Updated the two existing resolver pinning tests' rationale comments (`resolverDoesNotAcceptThePluralReversedSpellingSkillsList`, `resolverDoesNotAcceptRunSkillNowThatRunIsClaimedByRunScript`) from "documented as a discrepancy, pending resolution" to "this is the RESOLVED contract" — per the acceptance criteria's "assert the RESOLVED contract, not the workaround." Added two new `SkillsCLITests` pinning the positional-vs-`--id` CLI syntax (`useVerbWithABarePositionalIDIsSilentlyDroppedNotDispatched`, `useVerbWithTheIDFlagDispatchesCorrectly`).

    Checkpoint: 88ba1c4. Review (HEAD~1..HEAD) came back clean: 0 findings, 14/14 validator tasks attempted with 0 failures. 306/306 tests green.
  timestamp: 2026-07-30T02:28:56.792183+00:00
position_column: done
position_ordinal: a080
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