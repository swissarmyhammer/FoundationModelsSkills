---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19ba8aj1sv4bzwbbgz516eg
  text: |-
    Research and discoveries.

    `swift package update` moved the graph to:
    - `foundationmodelsranker` main `35447e4c77bc825dec26d4879678359bc291b23d`
    - `foundationmodelsmetadataregistry` main `aa7aa789ee456cba8274fa5a21f53e9276261b80`
    - `foundationmodelsrouter` main `b26ee0fd65223409ea147090099768a4e7cbedb0` (still in the graph, as the card requires)

    The bump exposed exactly one compile error, in `HotReloadLiveTests.swift`:
    `contextual closure type '@Sendable (String) -> any AgentSession' expects 1 argument, but 2 were used in closure body`.
    `HotReloadTests.swift` used `{ _, _ in ... }`, which Swift accepts for a one-argument closure, so it did not fail the build. The card names both sites, and both are repaired.

    Two stale doc sentences named the removed second argument, not one:
    1. The suite doc comment of `HotReloadLiveTests` -- the sentence the card names.
    2. The doc comment of `SelectionSessionFactory.makeSession()` in `HotReloadTests.swift`, which said "with `instructions` and `grammar` both ignored". The card says to repair the cause, so this second sentence is corrected too.

    BLOCKER THAT WAS SOLVED, for the next agent: after `swift package update`, `swift build` stopped with
    `error: 'mlx-swift-lm': ... couldn't be removed because you don't have permission to access it` (`EPERM`).
    This is not a permission problem. `sourcekit-lsp` runs a background index build
    (`swift-build --package-path .../checkouts/mlx-swift-lm ... --experimental-prepare-for-indexing`)
    that writes into the checkout while SwiftPM removes it. `rm -rf` failed the same way, and the checkout came back each time.

    The fix that worked: `pkill -STOP -x sourcekit-lsp`, delete `.build/checkouts/mlx-swift-lm` in a retry loop, run `swift build`, then `pkill -CONT -x sourcekit-lsp`. Two `swift build` runs in a row are stable after that.

    The root cause is out of this repository: `FoundationModelsRouter` declares `mlx-swift-lm` as `https://github.com/swissarmyhammer/mlx-swift-lm` and `FoundationModelsMetadataRegistry` declares it as `git@github.com:swissarmyhammer/mlx-swift-lm.git`. One identity, two URLs, so SwiftPM keeps two mirrors and can re-clone the checkout. Recorded as new task ^s7az6dc.

    What did NOT work: `rm -rf` alone (`sourcekit-lsp` re-creates the checkout), and killing only the `swift-build` index process (`sourcekit-lsp` starts it again).
  timestamp: 2026-08-30T12:46:37.394126+00:00
- actor: claude-code
  id: 01m19bafq7yyjk6rdkbjx7qzk5
  text: |
    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift, Tests/FoundationModelsSkillsTests/HotReloadTests.swift. Commands: `swift package update`, `swift build` (exit 0), `swift build --build-tests` (exit 0), `swift test` (377 tests in 26 suites, 0 failures), `swift test --filter HotReloadLiveTests` (1 test, skipped with its documented gate message). `.gitignore` and `Package.resolved` untouched; `Package.resolved` stays ignored at `.gitignore:4`. `rg -n "[Gg]rammar" Tests/ Sources/` gives no sentence that says a selection closure takes a `Grammar` argument. The Router stays in the graph.
    - warnings: the only build warnings come from the third-party `mlx-swift` checkout (4 `constexpr if is a C++17 extension` in Metal kernels) and the SwiftPM `missing creator for mutated node` line for the `mlx-swift_Cmlx` bundle. That second one is the warning ^vwthc4s already accepted. This package's own sources build clean.
    - next: /review
  timestamp: 2026-08-30T12:46:44.967812+00:00
- actor: claude-code
  id: 01m19bgy4jka7zkvx9y1k9xt1s
  text: |
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (5d7db29) — 0 findings, 0 confirmed, 0 refuted, 7 validator attempts, 0 failed. 2 files reviewed; 4 `.kanban/` files excluded by `.reviewignore`.
    - acceptance: both `SelectionConfig(model:)` call sites take one argument (HotReloadLiveTests.swift:83, HotReloadTests.swift:122). No prose says a selection closure takes a `Grammar` argument. The Router stays in the graph through the Registry dependency in Package.swift.
    - next: task moved to done.
  timestamp: 2026-08-30T12:50:16.338023+00:00
- actor: claude-code
  id: 01m19bhewwzjr26kg2x9v7424h
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files (HotReloadLiveTests.swift, HotReloadTests.swift)
    - test: green — swift test, 377 tests in 26 suites, 0 failures
    - commit: 5d7db29
    - review: clean — review sha HEAD~1..HEAD, 0 findings, 7 validators attempted, 0 failed
    - next: task is in done; loop moves to the next ready task in scope
  timestamp: 2026-08-30T12:50:33.500980+00:00
position_column: done
position_ordinal: ba80
title: Bump the sibling packages to current main and repair the API drift
---
## What

`Package.resolved` pins `FoundationModelsRanker` and `FoundationModelsMetadataRegistry` to revisions that are older than the `main` of each. The pinned Ranker has a two-argument `SelectionConfig.init(model:)`. The `main` of Ranker has a one-argument form.

This bump is independent of the Router work. Ranker `main` is clean and pushed. Do this task first, thus every later task is written against one API.

### Steps

1. Run `swift package update`. This moves `FoundationModelsRanker` and `FoundationModelsMetadataRegistry` to the current `main` of each.
2. Repair each `SelectionConfig(model:)` call site. The current signature is `@Sendable (String) -> any AgentSession`, one argument (`../FoundationModelsRanker/Sources/FoundationModelsRanker/Selection/SelectionConfig.swift:90`). There are two sites:
   - `Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift:83` — `SelectionConfig(model: { instructions, _ in ... })`
   - `Tests/FoundationModelsSkillsTests/HotReloadTests.swift:122` — `SelectionConfig(model: { _, _ in sessionFactory.makeSession() })`
3. Correct the stale sentence at `Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift:29-33`. It says the closure "ignores the `Grammar` argument". There is no second argument any more.
4. Repair any other compile error the bump exposes.

Do not touch `.gitignore`. `Package.resolved` is ignored at `.gitignore:4` and stays ignored.

- [x] Run `swift package update`.
- [x] Repair the two `SelectionConfig` call sites.
- [x] Correct the stale doc sentence.
- [x] Run the full test suite.

## Acceptance Criteria

- [x] `swift build` and `swift test` both pass against the bumped graph.
- [x] No `SelectionConfig(model:)` call site passes a two-argument closure.
- [x] `grep -rn "Grammar" Tests/ Sources/` gives no sentence that says a selection closure takes a `Grammar` argument.
- [x] The Router is still in the graph after this task. Removing it is a separate task.

## Tests

- [x] `HotReloadTests` passes with no change to its assertions. Only the closure shape changes.
- [x] `HotReloadLiveTests` compiles. It skips on a host with no on-device model.
- [x] `swift test` passes with zero failures and zero warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.