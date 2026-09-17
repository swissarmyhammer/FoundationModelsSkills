---
assignees:
- claude-code
position_column: todo
position_ordinal: '9380'
title: 'ACPAgent: decide what the agent does with MultiTool inlineSettleGrace, and repair TierTwoTests'
---
## What

**Cross-repository task.** The code is in `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent`.

A decision is necessary. A person must make it, because it changes what the agent
does, not only what a test reads.

`FoundationModelsMultitool` commit `b6a3f97` — "feat(runcode): answer a short
snippet with its own result" — changed the `runCode` answer. A `runCode` call now
waits `MultiToolConfiguration.inlineSettleGrace` for its own snippet before it
answers. The stock value is **two seconds**. A snippet that finishes inside the
wait answers with `pending: false` and carries its own outcome and result, and
the model makes no `wait` call. A snippet still running when the wait elapses
answers with the pending envelope, as before. The commit states: "A host that
sets the value to zero gets exactly the behavior of before."

`Package.resolved` is in `.gitignore`, so ACPAgent floats to Multitool `main` and
took the new stock value without a decision.

ACPAgent builds its registry with `MultiTool.Builder()` in
`Sources/FoundationModelsACPAgent/Tools/ToolCatalog.swift` and names no
`MultiToolConfiguration`, so it carries the stock two seconds today.

## Evidence

`swift test --no-parallel` gives 563 tests and 15 issues, every one of them in
`Tests/FoundationModelsACPAgentTests/Integration/TierTwoTests.swift`, in four
tests: `theCatalogComposesTheSurfaceFromTheLoadedConfiguration`,
`anOutOfRootReadRefusesInBandThroughTheCorrectionField`,
`aRealToolCallProjectsAStableUpsertLifecycle` and
`aClientDeclaredMCPServerMountsUnderItsOwnNoun`.

Each of the four scripts a `runCode` play, then a `wait` play, and reads the
snippet result from the `wait` answer. With the inline answer the `runCode` call
already carries the result, so the `wait` answer is empty and each read fails.
`aRealToolCallProjectsAStableUpsertLifecycle` states the old contract in its own
words: "The `runCode` call answers the pending envelope, because the run mounts
in the background."

Measured, with the Multitool pin set by hand in `Package.resolved`:

| Multitool pin | `swift test --no-parallel --filter TierTwoTests` |
| --- | --- |
| `579730c` (before `b6a3f97`) | 8 tests passed |
| `652a65d` (current main) | 8 tests, 15 issues |

Card `^je0whap` found and repaired the other cause of the red suite, the shared
`ModelPool`. These 15 are all that is left.

## The two answers

1. **Give the agent `inlineSettleGrace: 0`.** The agent keeps the two-step
   lifecycle plan.md §8.4 and §11.6 document, `TierTwoTests` stays correct as it
   is written, and the agent carries no built-in time. This is the answer the
   project rule "no hard-coded times" asks for: two seconds is a built-in
   interval the agent did not choose.
2. **Take the inline answer.** The agent gains the token saving of a short
   snippet that needs no `wait` call. Then plan.md §8.4 and §11.6 must say so,
   and the four `TierTwoTests` proofs must read the result from the `runCode`
   answer.

Do NOT weaken a test to close this card. Make the decision first.

- [ ] A person chooses answer 1 or answer 2
- [ ] Apply the chosen answer, with the plan.md amendment answer 2 needs
- [ ] `swift test` gives zero failures, parallel and `--no-parallel`

## Acceptance Criteria
- [ ] `swift test` in ACPAgent gives zero failures and zero warnings
- [ ] `TierTwoTests` proves the lifecycle the plan documents

## Tests
- [ ] `swift test --filter TierTwoTests`, and the whole suite

## Workflow
- Use `/tdd`. #cross-repo