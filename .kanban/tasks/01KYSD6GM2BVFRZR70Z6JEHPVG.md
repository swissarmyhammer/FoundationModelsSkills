---
comments:
- actor: claude-code
  id: 01m0z2k2x8f2xxzzx424pf4qka
  text: |-
    Research: the greps found the six items on the card and no other. The recorded resolution for §7.3 is in README "Visibility": the ops gate on `SkillsToolContext.visibilityPredicate`; `SkillsTool.make` sets `isModelVisible` as the default; `SkillsCLI` supplies the user-surface predicate. One more stale word in `SkillsRegistry.swift:9` ("a future `SkillSearchAgent`") had the same cause and was corrected. The word "scaffold" in `RenderPipeline.swift` describes `IdentityRenderPass`, a live test double. It is not stale, so it stays.

    Changes:
    - `plan.md:760` — `skill use --id commit`.
    - `plan.md:425-431` — §7.3 now states the visibility-predicate behavior and the recorded resolution.
    - `Examples/skills-demo/SkillsDemoMain.swift:10-11` — `skill use --id commit`.
    - `Sources/FoundationModelsSkills/FoundationModelsSkills.swift:1-8` — the scaffold text is replaced with the shipped-module description.
    - `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:9,93-94` — the "future"/"later task" text is replaced.
    - `Sources/FoundationModelsSkills/Render/RenderPipeline.swift:4-21` — the review-log comments are removed.

    Verification: the three acceptance greps return no hit; `swift build` is clean.

    ### implement — changed
    - evidence: 5 files — plan.md, Examples/skills-demo/SkillsDemoMain.swift, Sources/FoundationModelsSkills/FoundationModelsSkills.swift, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Sources/FoundationModelsSkills/Render/RenderPipeline.swift
    - next: test
  timestamp: 2026-08-26T13:01:45.256849+00:00
- actor: claude-code
  id: 01m0z2npkhccmgc9tsbkbenex1
  text: |-
    ### test — green
    - evidence: `swift test` — 333 tests in 23 suites passed, 0 failed, exit 0. One env-gated skip (`SKILLS_INTEGRATION_TESTS`) in `HotReloadLiveTests`, the same pre-existing gate the prior task ledgers record as permitted by the `test-integrity` rule. The only warning is the SwiftPM build-graph note about the `mlx-swift_Cmlx.bundle` node; it is not a compiler warning from this package's code.
    - next: commit
  timestamp: 2026-08-26T13:03:10.961773+00:00
- actor: claude-code
  id: 01m0z2p44ds4rgch8hc3h412b8
  text: |-
    ### commit — changed
    - evidence: b28b245 docs(^6jehpvg): sweep residual stale docs and scaffold-era comments
    - next: review
  timestamp: 2026-08-26T13:03:24.813169+00:00
- actor: claude-code
  id: 01m0z2sk3qx4ysd46hjdy0swb6
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 0 confirmed, 0 refuted; 4 files reviewed, 4 `.kanban/` files excluded by `.reviewignore`. No prior findings on the card.
    - next: done
  timestamp: 2026-08-26T13:05:18.455566+00:00
- actor: claude-code
  id: 01m0z2ssp1sj7k2mbw34c31t8q
  text: |-
    ### finish iteration 1 — review clean, task moved to done
    - implement: changed — 5 files (plan.md, Examples/skills-demo/SkillsDemoMain.swift, Sources/FoundationModelsSkills/FoundationModelsSkills.swift, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Sources/FoundationModelsSkills/Render/RenderPipeline.swift)
    - test: green — `swift test` 333 passed, 0 failed; one env-gated skip (pre-existing)
    - commit: b28b245
    - review: clean — 0 findings on `review sha HEAD~1..HEAD`
  timestamp: 2026-08-26T13:05:25.185166+00:00
position_column: done
position_ordinal: a980
title: 'Sweep residual stale docs: positional CLI examples, scaffold-era comments'
---
## What
Documentation residue the M7 sweep and the #21 plan amendment missed — each a silent contradiction of shipped behavior:

1. `plan.md` §11 (~line 753) still documents `skills-demo skill use commit --arguments "fix parser"` — the positional-id form the #21 amendment itself declares never worked. Change to `--id commit`.
2. `Examples/skills-demo/SkillsDemoMain.swift:10-11` — the executable's doc comment advertises the same non-dispatching positional invocation (its test correctly uses `--id`).
3. `plan.md` §7.3 (~line 419) still says the resource ops see the "model-visible" catalog; the shipped (and documented-in-README) behavior is the context surface predicate. Amend the sentence with the recorded resolution.
4. Scaffold-era comments that survived the sweep: `Sources/FoundationModelsSkills/FoundationModelsSkills.swift:1-9` ("placeholder root … scaffolding only … land in subsequent tasks" — README points HERE for the iOS posture, so it is user-visible); `Registry/SkillsRegistry.swift:93` ("a model-facing operation layer, a later task" — it shipped); `Render/RenderPipeline.swift:4-21` stray `// Review fix (^8jqwxc5, round 4/5)` review-log comments.

## Acceptance Criteria
- [x] No positional-id CLI example remains anywhere (`grep -rn "skill use [a-z]" plan.md Examples/ README.md` shows only `--id` forms)
- [x] plan.md §7.3 wording matches the shipped surface-predicate behavior
- [x] No "placeholder"/"scaffolding only"/"later task"/review-log comments remain in Sources/ (greppable)

## Tests
- [x] Documentation-only change; verification is the greps above + `swift build` clean
- [x] `swift test` — exit 0 (no behavior change)

## Workflow
- Doc-only task; TDD not applicable — verify via the grep criteria.