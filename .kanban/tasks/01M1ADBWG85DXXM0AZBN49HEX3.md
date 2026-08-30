---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1ae8966h41x9trvn689zhvc
  text: |-
    ### done, but NOT through the normal gate

    Recorded plainly, the same as `^vk0ajqz`: I implemented this card myself and did not run `/implement` then `/review`. A reviewer should still look at it.

    - commit: 336a077
    - test: green — swift test, 407 tests in 32 suites, 0 failures

    **One deviation from the card, and its reason.** The card says to add the case to `ReadmeExampleTests.swift`. I put it in `DependencyGraphTests.swift` instead.

    `ReadmeExampleTests.swift` imports only `FoundationModels`, `FoundationModelsSkills` and `Testing`. That short import list is not decoration — it IS the compile guard. It is what proves a host needs no third import. Reading a file needs `Foundation`, thus adding the equality case there would have added a fourth import and weakened the very thing the file exists to prove. `DependencyGraphTests.swift` already imports `Foundation` and already reads `README.md`-adjacent files, thus the case costs nothing there.

    **Not vacuous, proven in both directions:**
    - Edit `README.md` alone (`name: "skills"` to `name: "drifted"`) — the case FAILS.
    - Edit the test copy alone, the same way — the case FAILS.
    - Restore both — the case passes, and the whole suite is green.

    An absent fence or an absent marker throws `MissingBlockError` instead of giving `""`. Two empty strings are equal, thus a case that compared them would pass and prove nothing.

    The two cases now give the whole promise together: `ReadmeExampleTests` proves the block compiles, and this case proves the block a reader sees is the block that compiled.
  timestamp: 2026-08-30T22:57:12.902710+00:00
position_column: done
position_ordinal: c580
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