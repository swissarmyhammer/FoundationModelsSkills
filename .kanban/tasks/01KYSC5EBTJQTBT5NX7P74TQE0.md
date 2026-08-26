---
comments:
- actor: claude-code
  id: 01m0z1j04rnn1ztby9at6fr5s2
  text: |-
    Research and decision:
    - Decision: a bare token -> optional. The hint is display text. Only `<x>` marks a token required. A display-only word must not block dispatch.
    - A position with no hint token (`arguments:` past the hint arity, or body inference) stays required. The source is silent there.
    - A malformed token (`[env`) falls through to the bare-token rule -> optional. The raw text stays as placeholder and name.
    - The corrective names `SkillParameter.name` (from `arguments:` when present), not the hint inner text.

    Changes:
    - `Sources/FoundationModelsSkills/Listing/ParameterInference.swift`: `parseHintToken` bare branch now `required = false`; `parseHint` doc comment states the rule.
    - `Sources/FoundationModelsSkills/Listing/SkillParameter.swift`, `Registry/SkillsRegistry.swift`, `Operations/UseSkill.swift`: doc comments aligned.
    - `plan.md` §6.1: bare-token rule recorded.
    - `Tests/.../ParameterInferenceTests.swift`: 3 new tests (bare token, malformed `[env`/`<target`, bare token merged with `arguments:`); 2 existing expectations updated (`c...`, `<`).
    - `Tests/.../SkillOperationsTests.swift`: bare `env` missing -> success; new malformed `[env` -> success; new corrective-name test (`arguments: message` + `<msg>` -> names `message`, not `msg`).

    `swift test`: 330 tests, 23 suites, 0 failures.
  timestamp: 2026-08-26T12:43:41.080597+00:00
- actor: claude-code
  id: 01m0z1j2h819eg163sttwc9z6n
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsSkills/Listing/ParameterInference.swift, Sources/FoundationModelsSkills/Listing/SkillParameter.swift, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Sources/FoundationModelsSkills/Operations/UseSkill.swift, plan.md, Tests/FoundationModelsSkillsTests/ParameterInferenceTests.swift, Tests/FoundationModelsSkillsTests/SkillOperationsTests.swift
    - next: test, commit, review
  timestamp: 2026-08-26T12:43:43.528261+00:00
position_column: doing
position_ordinal: '80'
title: Decide and pin bare-token argument-hint optionality (§6.1)
---
## What
The UseSkill required-arg task was closed by redefining its headline criterion. The mechanism is right (structured `SkillParameter.required` consulted at `Operations/UseSkill.swift:97-101`), but the observable behavior for unbracketed hints is IDENTICAL to the old placeholder check: `ParameterInference` defaults a bare token to `required: true` (`Listing/ParameterInference.swift:126, 164-176`), and the shipped test now asserts a corrective for `argument-hint: env` with no args (`SkillOperationsTests.swift:295-311`) — the opposite of the original criterion ("dispatches without a bogus missing-argument corrective").

§6.1's grammar defines only `<x>` (required) and `[x]` (optional); a bare token is unspecified. Resolve deliberately, not by accident:
- Decide: bare token → optional (Claude's hints are display text; a display-only word should not block dispatch — the original variance's position) or → required (the shipped behavior). Record the decision in plan.md §6.1 and in `ParameterInference`'s doc comment.
- Whichever way: also pin the two untested behavioral deltas the refactor introduced — a malformed placeholder like `[env` (unclosed bracket) now reads required (was optional), and the corrective names the structured `arguments:` name rather than the hint token's inner text.

## Acceptance Criteria
- [ ] plan.md §6.1 states the bare-token rule; `ParameterInference` doc comment matches; tests assert it (in whichever direction was chosen)
- [ ] Malformed-placeholder (`[env`) classification pinned by a test with a comment stating it is deliberate
- [ ] Corrective-name source (structured name, not hint text) pinned by a test

## Tests
- [ ] Extend `ParameterInferenceTests` + `SkillOperationsTests` per above
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write the deciding tests first, then align code/docs.