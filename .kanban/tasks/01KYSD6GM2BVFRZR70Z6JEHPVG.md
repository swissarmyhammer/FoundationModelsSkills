---
position_column: todo
position_ordinal: '8580'
title: 'Sweep residual stale docs: positional CLI examples, scaffold-era comments'
---
## What
Documentation residue the M7 sweep and the #21 plan amendment missed — each a silent contradiction of shipped behavior:

1. `plan.md` §11 (~line 753) still documents `skills-demo skill use commit --arguments "fix parser"` — the positional-id form the #21 amendment itself declares never worked. Change to `--id commit`.
2. `Examples/skills-demo/SkillsDemoMain.swift:10-11` — the executable's doc comment advertises the same non-dispatching positional invocation (its test correctly uses `--id`).
3. `plan.md` §7.3 (~line 419) still says the resource ops see the "model-visible" catalog; the shipped (and documented-in-README) behavior is the context surface predicate. Amend the sentence with the recorded resolution.
4. Scaffold-era comments that survived the sweep: `Sources/FoundationModelsSkills/FoundationModelsSkills.swift:1-9` ("placeholder root … scaffolding only … land in subsequent tasks" — README points HERE for the iOS posture, so it is user-visible); `Registry/SkillsRegistry.swift:93` ("a model-facing operation layer, a later task" — it shipped); `Render/RenderPipeline.swift:4-21` stray `// Review fix (^8jqwxc5, round 4/5)` review-log comments.

## Acceptance Criteria
- [ ] No positional-id CLI example remains anywhere (`grep -rn "skill use [a-z]" plan.md Examples/ README.md` shows only `--id` forms)
- [ ] plan.md §7.3 wording matches the shipped surface-predicate behavior
- [ ] No "placeholder"/"scaffolding only"/"later task"/review-log comments remain in Sources/ (greppable)

## Tests
- [ ] Documentation-only change; verification is the greps above + `swift build` clean
- [ ] `swift test` — exit 0 (no behavior change)

## Workflow
- Doc-only task; TDD not applicable — verify via the grep criteria.