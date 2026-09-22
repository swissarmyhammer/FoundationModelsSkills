---
comments:
- actor: claude-code
  id: 01m34z3amr8fhxc8ep0mdknbjp
  text: |-
    Picked up. The code and the two test files were in the working tree. I did the doc items: the two test doc comments, `docs/operations.md`, `plan.md` §6.1 and §7, and `CHANGELOG.md`.

    Discovery: the acceptance grep for `bare-token rule`, `optionality`, and `missing-argument corrective` also found four files that the card does not list: `Sources/FoundationModelsSkills/Listing/ParameterInference.swift`, `Sources/FoundationModelsSkills/Listing/SkillParameter.swift`, `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`, and `Tests/FoundationModelsSkillsTests/ParameterInferenceTests.swift`. Their comments gave the corrective as the reason for the `required: false` reading of a bare token, and that reason is gone. I rewrote those comments so that they describe the `required` flag as the code sets it today, with no reference to the corrective or to a plan rule that no longer exists. The `required` flag itself stays until ^2wma974 removes it.

    The sentence in plan.md §6.1 reads "Every argument is optional: a reference with no value renders as an empty string (§5)." The word "required" is not in it, because the acceptance grep for `required` between §6.1 and §7 must find no line.

    All three acceptance greps give no line, and `rg -n "corrective" CHANGELOG.md` finds the new entry under Unreleased.
  timestamp: 2026-09-22T16:27:33.400515+00:00
- actor: claude-code
  id: 01m34z525m1g3j3xgyytw0h35p
  text: |-
    ### implement — changed
    - evidence: 12 files — Sources/FoundationModelsSkills/Operations/UseSkill.swift, Sources/FoundationModelsSkills/Listing/ParameterInference.swift, Sources/FoundationModelsSkills/Listing/SkillParameter.swift, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Tests/FoundationModelsSkillsTests/SkillOperationsTests.swift, Tests/FoundationModelsSkillsTests/UseSkillPlainTextTests.swift, Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift, Tests/FoundationModelsSkillsTests/SearchListPlainTextTests.swift, Tests/FoundationModelsSkillsTests/ParameterInferenceTests.swift, docs/operations.md, plan.md, CHANGELOG.md. The five touched suites pass: 85 tests, no failure, no warning.
    - next: /test, then /commit, then /review
  timestamp: 2026-09-22T16:28:30.260747+00:00
- actor: claude-code
  id: 01m34z651f786600v4f3w9kw0p
  text: |-
    ### test — green
    - evidence: swift test — 562 tests in 53 suites passed, 0 failed, 0 skipped, 0 warnings
    - next: /commit
  timestamp: 2026-09-22T16:29:05.967166+00:00
- actor: claude-code
  id: 01m34z6hkt5mtkkyffbarvh9pd
  text: |-
    ### commit — changed
    - evidence: c054cc5 feat(use-skill): remove the missing-argument corrective
    - next: /review 01M34XXTWAM72JQ59NAMZW32K2 HEAD~1..HEAD
  timestamp: 2026-09-22T16:29:18.842572+00:00
- actor: claude-code
  id: 01m34zc8wbbzh2cccvhh26e26b
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (c054cc5) — 0 findings, 0 confirmed, 0 refuted, 7 validator runs; 9 files reviewed, CHANGELOG.md, docs/operations.md and plan.md matched no validator, .kanban/ excluded by .reviewignore
    - next: none; the card is in done
  timestamp: 2026-09-22T16:32:26.507406+00:00
- actor: claude-code
  id: 01m34zccynzbj1rbnh66w8s1br
  text: |-
    ### finish iteration 1 — review clean, card moved to done
    - implement: changed — Sources/FoundationModelsSkills/Operations/UseSkill.swift, Sources/FoundationModelsSkills/Listing/ParameterInference.swift, Sources/FoundationModelsSkills/Listing/SkillParameter.swift, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Tests/FoundationModelsSkillsTests/SkillOperationsTests.swift, Tests/FoundationModelsSkillsTests/UseSkillPlainTextTests.swift, Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift, Tests/FoundationModelsSkillsTests/SearchListPlainTextTests.swift, Tests/FoundationModelsSkillsTests/ParameterInferenceTests.swift, docs/operations.md, plan.md, CHANGELOG.md
    - test: green — swift test, 562 tests in 53 suites passed, 0 failed, 0 skipped, 0 warnings
    - commit: c054cc5
    - review: clean — no finding
  timestamp: 2026-09-22T16:32:30.677911+00:00
position_column: done
position_ordinal: ff9080
title: Remove the missing-argument corrective from use skill
---
## What

`use skill` returns "Missing required argument `x` for this skill." when the count of supplied arguments is below the position of a required parameter. No argument is required. A reference with no value renders as an empty string, as pass 1 already does. This card removes the corrective and the text of the plan and the docs that describe required arguments.

Files (8; five of them hold doc edits only):

- `Sources/FoundationModelsSkills/Operations/UseSkill.swift`: remove `firstMissingRequiredParameterName(parameters:suppliedCount:)`, `missingArgumentMessage(name:)`, and the check in `execute(in:)`. `execute(in:)` calls `context.registry.call(id:arguments:)` with `arguments ?? []`. Update the doc comments of `UseSkillOutput`, `UseSkill`, and `execute(in:)`.
- `Tests/FoundationModelsSkillsTests/SkillOperationsTests.swift` and `Tests/FoundationModelsSkillsTests/UseSkillPlainTextTests.swift`: the missing-argument tests become success tests.
- `Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift` (the doc comment near line 308, "A fixture skill with no required argument...") and `Tests/FoundationModelsSkillsTests/SearchListPlainTextTests.swift` (the doc comment near line 35, "The fixture skill with no required argument..."): rewrite the two doc comments; the reason they give has no meaning now.
- `docs/operations.md`: remove the example "A missing required argument of the skill gives:" under "The `use skill` answer".
- `plan.md` §7, the `use skill` row: remove "a missing required argument (§6.1) → corrective message naming it".
- `plan.md` §6.1, four places: the `SkillParameter` sketch (remove the `required` line); the `argument-hint:` bullet head "display + optionality (`<x>` required, `[x]` optional, trailing `...` variadic)" becomes "display text only: each token keeps its raw text, and a trailing `...` marks a variadic tail"; the bare-token rule paragraph (remove it); the sentence "The missing-argument corrective names..." (remove it). Add one sentence: no argument is required; a reference with no value renders as an empty string.
- `CHANGELOG.md`: one "Changed" entry under Unreleased for the removed corrective.

The code and the tests of this task are in the working tree, uncommitted. The two test doc comments, docs/operations.md, plan.md, and CHANGELOG.md items are not done.

## Acceptance Criteria

- [x] `UseSkill(id: "commit", arguments: [])` gives `.success` with the body of `registry.call(id: "commit", arguments: [])`, where `$0` is an empty string.
- [x] `rg -in "missing required argument|missing-argument corrective|no required argument|bare-token rule|optionality" Sources/ Tests/ docs/ plan.md` finds no line.
- [x] `rg -n "required" plan.md` finds no line between the `### 6.1` heading and the `## 7.` heading.
- [x] An unknown or hidden id still gives the unusable-id corrective.
- [x] `rg -n "corrective" CHANGELOG.md` finds a line under Unreleased.

## Tests

- [x] `SkillOperationsTests.useSkillWithNoArgumentForADeclaredNameRendersThatNameEmpty` and the parameterized `useSkillWithNoArgumentsRendersTheBodyWithTheReferenceEmpty` (4 cases: no source, `arguments:`, `argument-hint: "<env>"`, both).
- [x] `UseSkillPlainTextTests.aCallWithNoArgumentsGivesTheRenderedBodyWithTheArgumentEmpty` for each op alias.
- [x] `swift test` passes with no failure and no warning.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass. #skills