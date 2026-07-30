---
position_column: todo
position_ordinal: '8280'
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