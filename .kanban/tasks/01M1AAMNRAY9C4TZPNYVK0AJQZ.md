---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1adh8x1bf2hrjshbs36rm5h
  text: |-
    Picked up. Research notes.

    - The line numbers in the card are still correct. `docs/development.md:23` and `docs/development.md:35` are the only two lines under `docs/` that name `FoundationModelsOperationTool`. `docs/security.md` and `docs/operations.md` do not name it.
    - Other references to the name are outside the scope of this card: `plan.md:8`, `plan.md:420`, `plan.md:902` (the decision record, which keeps history), `Tests/.../SkillOperationsTests.swift:46`, `Tests/.../SkillsCLITests.swift:63`, and `Package.swift:36` (the retirement note itself).
    - `Package.swift:34-41` is the agreement target: "The Operations capability moved into the Extras package on 2026-08-29 (the FoundationModelsOperationTool repository is retired), so these two products resolve from `FoundationModelsExtras` now."
    - `DependencyGraphTests.swift` already has `linesNaming(_:under:in:)`, `files(under:)`, and `path(of:in:)`. `prosePaths` already holds the literal `"docs"`. The new case will read the same directory, thus the literal becomes one constant that both use.
    - Plan for the guard: call `linesNaming` two times over `docs/`. The first call reads the lines that name the package. The second call reads the lines that hold the retired-repository phrase. The case reports the difference. Thus a line that says the repository was retired stays, and every other line that names the package fails. The phrase must stay on one line, because the walk reads one line at a time.
  timestamp: 2026-08-30T22:44:38.945757+00:00
position_column: doing
position_ordinal: '80'
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