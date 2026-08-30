---
assignees:
- claude-code
position_column: todo
position_ordinal: 8b80
title: Correct the stale FoundationModelsOperationTool prose in docs/development.md
---
## What

`docs/development.md:23` and `:35` describe `FoundationModelsOperationTool` in the present tense, as "a separate package that other consumers also depend on". That repository was retired on 2026-08-29, and `Package.swift:36` says so. The two statements disagree.

Found by the review of `^k8109g9`. It was not a finding there, because those lines are outside that card's scope and outside its diff.

The `Operations` and `OperationsCLI` products now resolve from `FoundationModelsExtras`. Correct both passages to say that, in the past tense where they describe history.

Write every text in this task in ASD-STE100 Simplified Technical English.

- [ ] Correct `docs/development.md:23`.
- [ ] Correct `docs/development.md:35`.
- [ ] Add the guard test case.

## Acceptance Criteria

- [ ] No sentence in `docs/` says, in the present tense, that `FoundationModelsOperationTool` is a package this repository or another consumer depends on.
- [ ] `docs/development.md` and `Package.swift:36` agree: the repository is retired, and `Operations` / `OperationsCLI` come from `FoundationModelsExtras`.
- [ ] A reader who follows `docs/development.md` alone reaches no wrong conclusion about where the operation-tool products come from.

## Tests

- [ ] Add a test case to `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift`, beside `namesNoRemovedRouterPackage()`. It walks `docs/` and asserts no line names `FoundationModelsOperationTool` as a current dependency. Match the retired-repository sentence, which is history and stays, but fail on a present-tense dependency claim. State in the doc comment how the case tells the two apart.
- [ ] Prove the case is not vacuous: make it fail first against the current text, and record the offending `file:line` pairs.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.