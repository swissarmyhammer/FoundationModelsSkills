---
assignees:
- claude-code
position_column: todo
position_ordinal: 8c80
title: Assert that the README block and its test copy stay equal
---
## What

`Tests/FoundationModelsSkillsTests/ReadmeExampleTests.swift` holds a copy of the README usage block, thus the block is known to compile. Nothing asserts that the two copies stay equal.

A later edit to `README.md` alone leaves the suite green: the test proves only that *its own* copy compiles, never that the README still matches it. The compile guard is real, and the equality guard is absent.

Found by the review of `^bewqfmf`. It was not a finding there, because that card's Tests section asks only for a test that holds the code and compiles, which is satisfied.

Write every text in this task in ASD-STE100 Simplified Technical English.

### The approach

Add a case that reads `README.md` from `FixtureLibrary.packageRoot()`, cuts the first fenced ` ```swift ` block out, and compares it with the copy the test file holds. Hold the copy in one place, thus the compiled copy and the compared copy are the same text and cannot drift from each other.

Two details make the comparison work:
- The test copy is indented, because it sits inside a function. Remove the common indent before you compare.
- The README block holds the two `import` lines. Decide whether the test copy holds them too, or whether the comparison drops them, and say which in the doc comment.

`Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift` already cuts a fenced block out of `plan.md` in `planSection(startingWith:)`. Read it first, and reuse the approach rather than write a second one.

- [ ] Add the equality case.
- [ ] Hold the block text in one place.
- [ ] Prove the case fails when the two copies differ.

## Acceptance Criteria

- [ ] An edit to the README usage block that is not made in the test copy fails `swift test`.
- [ ] An edit to the test copy that is not made in the README fails `swift test`.
- [ ] The case fails, and never skips, when `README.md` holds no fenced `swift` block.
- [ ] The compile guard `^bewqfmf` added still holds. Do not weaken it.

## Tests

- [ ] Add the case to `Tests/FoundationModelsSkillsTests/ReadmeExampleTests.swift`.
- [ ] Prove it is not vacuous: change one character in the README block, watch the case fail, then put the character back. Record the failure message in a task comment.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.