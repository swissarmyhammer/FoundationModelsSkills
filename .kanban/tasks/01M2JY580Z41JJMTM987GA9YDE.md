---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2jyjv2t51349s47z2d12h9g
  text: |-
    Research done. The ref check is only in Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift. `validated(ref:)` calls `validated(pathValue:kind:)`, which refuses `/`. Two callers use the result: `sha(forRef:)` and `install(snapshotAt:sha:ref:)` through `write(sha:toValidatedRef:)`. No other file calls these, so the change stays in one file plus the test suite.

    Plan: keep the safe-component rule in one place, split a ref on `/`, check each component, and build the ref path one component at a time. `write(sha:toValidatedRef:)` must make the parent folders. The sha rule does not change: one component, hexadecimal, no separator.

    Note: the test list `unsafePathValues` in MarketplaceCacheTests serves both the sha tests and the ref tests. It holds `a/b` and `/etc/passwd`. The ref tests need their own list, because `a/b` is now good for a ref.
  timestamp: 2026-09-15T16:32:13.402074+00:00
- actor: claude-code
  id: 01m2jysrn90fq6e6r1b2rsajxc
  text: |-
    Implementation landed, with the tests first.

    RED: two new parameterized tests failed with 4 cases, because `feature/login` and `refs/heads/main` were refused.

    GREEN: in MarketplaceCache.swift
    - `isSafe(component:)` holds the one rule for one name: not empty, no leading dot (which refuses `.` and `..`), no `/` and no `\`, no control character. The old `!value.contains("..")` test is gone, because the leading-dot rule already refuses the two names that walk out of a folder.
    - `validated(pathValue:kind:)` keeps its shape and now calls that rule. The sha path does not change: one name, hexadecimal, no separator.
    - `validated(ref:)` gives `[String]` now. It splits the ref on `/` with `omittingEmptySubsequences: false`, so a leading `/`, a trailing `/`, and `//` each make an empty component, which the rule refuses.
    - `refFile(forValidatedRef:)` builds the path with one `appendingPathComponent` for each component.
    - `write(sha:toValidatedRef:)` makes the parent folders before the write, so `refs/heads/main` gets its two folders.

    Tests: `feature/login` and `refs/heads/main` install, round-trip through `sha(forRef:)`, and write a file one folder deep for each component. The refused list for a ref is now its own list: "", "..", "../x", "a/../b", "/abs", "a//b", "a/", ".hidden", ".hidden/x", "a\b". Each refused install still writes no folder. The sha list keeps `a/b` and `/etc/passwd`, which stay refused for a sha.

    Evidence: swift build --build-tests gives no warning; swift test gives 579 tests in 41 suites, 0 failures.
  timestamp: 2026-09-15T16:36:00.297174+00:00
- actor: claude-code
  id: 01m2jytgjb0vmk8t3g3rejqfh2
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift, Tests/FoundationModelsSkillsTests/MarketplaceCacheTests.swift; `swift build --build-tests` 0 warnings; `swift test` 579 tests in 41 suites, 0 failures
    - next: /review
  timestamp: 2026-09-15T16:36:24.779619+00:00
position_column: doing
position_ordinal: '80'
title: 'MarketplaceCache: let a ref name hold a slash again, one safe component at a time'
---
## Why

`MarketplaceCache.validated(ref:)` now refuses every ref that holds a `/`, because the path-traversal findings on card ^rnerbsj asked for one validator that refuses a path separator. Git permits a branch name with a `/` in it, for example `feature/login`. A user who writes `ref: feature/login` in `marketplaces.yaml` now gets an error.

## What

- Split the ref on `/` and check each part with the same rules, in place of a refusal of the whole value.
- Keep the refusal of an empty part, of `..`, of a part that starts with a dot, and of a control character.
- `write(sha:toValidatedRef:)` must make the folders of the file again.

## Tests
- A ref `feature/login` writes `refs/feature/login` and reads back.
- `../x`, `a/../b`, `/etc/passwd`, and `.hidden/x` stay refused.

#marketplace