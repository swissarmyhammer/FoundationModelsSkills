---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2n2538fz5rmcmjt6apfhj44
  text: |
    ### Research

    Work happens in `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent`.

    - `swift package update FoundationModelsExtras` resolved Extras `main` at `8ec26d4`. `Package.resolved` did not change, so the pin was already current. `.build/checkouts/FoundationModelsExtras/Sources/FoundationModelsExtras/DotfolderStack.swift` holds `case marketplace`. The Extras documentation says the marketplace layer sits below the local layers and "is never trusted".
    - Two switches over `DotfolderStack.Source` are exhaustive and have no `default`, so both stop compiling:
      - `Sources/FoundationModelsACPAgent/Configuration/ConfigurationLayerName.swift`, `init(_ source: DotfolderStack.Source?)`.
      - `Sources/FoundationModelsACPAgent/Instructions/InstructionsAssembler.swift`, `trust(for:)`. The new case must give `.untrusted`, because Extras says the marketplace layer is never trusted.
    - `LayerSelection` in `Sources/acp-agent/LayerFileWriter.swift` switches over its own enum, not over `DotfolderStack.Source`, so it needs no change.
    - The test goes in `Tests/FoundationModelsACPAgentTests/ConfigurationLoaderTests.swift`, in the "The per-key source map" section, which is the configuration test file. The file uses swift-testing (`@Suite`, `@Test`, `#expect`).
  timestamp: 2026-09-16T12:13:06.191958+00:00
- actor: claude-code
  id: 01m2n2wc5ceg6pqc6sjvpy1hft
  text: |
    ### implement — stuck

    The code of the card is complete, but the acceptance criterion "all its tests pass" is not reachable from this card. The ACPAgent suite is red before the change.

    **What the card asked, and what happened**

    - `swift package update FoundationModelsExtras`: Extras `main` resolved at `8ec26d4`. `Package.resolved` already held that revision, thus the file did not change. There is no `Package.resolved` change to commit.
    - TDD, RED: with the new test in place, `swift build --build-tests` failed at `InstructionsAssembler.swift:227` with `error: switch must be exhaustive`. That is the compiler naming the second switch, exactly as the card said it would.
    - GREEN: `swift build --build-tests` is clean. The only warnings in the log come from the `mlx-swift` C++ sources of a dependency, and they stand before this change.
    - The new test `eachSourceNamesItsOwnLayer(source:name:)` passes with all 4 arguments, `.marketplace` included.

    **Files changed**

    - `Sources/FoundationModelsACPAgent/Configuration/ConfigurationLayerName.swift`: added `case marketplace` with its documentation, and `case .marketplace?: self = .marketplace` in `init(_:)`. No `default` arm, so the compiler keeps checking the switch.
    - `Sources/FoundationModelsACPAgent/Instructions/InstructionsAssembler.swift`: added `.some(.marketplace)` to the untrusted arm of `trust(for:)`, and corrected the documentation above it. Extras says the marketplace layer "is never trusted", so `.untrusted` is the only correct answer.
    - `Tests/FoundationModelsACPAgentTests/ConfigurationLoaderTests.swift`: one parameterized swift-testing `@Test` over all four `DotfolderStack.Source` values, in the per-key source map section.

    **The blocker**

    `main` at `ec9f73b` does not compile at all, because `Package.resolved` already pins Extras `8ec26d4`. To measure a baseline I stashed the change, put a throwaway `default:` arm in both switches, ran the suite, then restored the change and removed the throwaway arms.

    | Run | Tests | Issues |
    | --- | --- | --- |
    | Baseline: no card change, throwaway `default:` arms | 561 | 88 |
    | The card change, parallel | 562 | 100 |
    | The card change, `--no-parallel` | 562 | 98 |

    The baseline is red on its own, in the same 19 suites: `TierTwoTests`, `PromptTurnTests`, `ElicitationRelayTests`, `SessionResumeTests`, `RunCodeSourceTests`, `CompositionInterruptTests`, `TranscriptStoreTests`, `RunCommandTests`, `TranscriptFidelityTests`, `PromptContentTests`, `ConfigOptionsTests`, `BuiltinCommandsTests`, `AgentCompositionTests`, `SessionLifecycleTests`, `InterruptTests`, `ExitCodeTests`, `EventLineWriterTests`, `CommandDispatchTests`, `CancellationTests`. The serial run shows this is not a parallel-run race. The set of failing test names moves between runs in both directions, and the root message is always a scripted turn that gives no response event, for example `ResumeSessionFixture.swift:304: "the recording never reached 1 response event(s)"`, 27 times in the serial run.

    No failing suite touches `ConfigurationLayerName`. The change adds one enum case and one switch arm for a source no local stack derives, thus it cannot alter a path any of those suites walks.

    The unrelated breakage is now card `^je0whap`.

    - evidence: 3 files — /Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Configuration/ConfigurationLayerName.swift, /Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Instructions/InstructionsAssembler.swift, /Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent/Tests/FoundationModelsACPAgentTests/ConfigurationLoaderTests.swift. Build clean, 0 new warnings. Suite: 562 tests, 100 issues parallel and 98 serial, against 88 at baseline without the change.
    - next: a person decides. Either fix `^je0whap` first and then take this card green, or accept this card on its own evidence and let `^je0whap` carry the red suite.
  timestamp: 2026-09-16T12:25:48.972239+00:00
- actor: claude-code
  id: 01m2n5ktsxrsmccadq32r1x8p2
  text: |
    ### review — clean

    Scope: commit `f9aeccd` (`HEAD~1..HEAD`) in `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent`.

    - engine: the `review` MCP engine could not do this scope. It is locked to the repository root of this session (FoundationModelsSkills). It refused the ACPAgent path with "escapes the repository root". Thus the checks below were done directly on the diff.
    - evidence:
      - `swift build` — "Build complete!", no warning from the source of this change. The one build-system warning comes from the `mlx-swift` dependency bundle and is not from this change.
      - `swift test --filter eachSourceNamesItsOwnLayer` — 1 test, 4 arguments, all pass. `.defaults`, `.user`, `.project` and `.marketplace` each give their own layer name.
      - `Sources/FoundationModelsACPAgent/Configuration/ConfigurationLayerName.swift` — the `marketplace` case and the `case .marketplace?` map are both present. The switch stays exhaustive with no `default`.
      - `Sources/FoundationModelsACPAgent/Instructions/InstructionsAssembler.swift` — `trust(for:)` gives `.untrusted` to `.marketplace`. This agrees with the upstream contract in `DotfolderStack.swift` of FoundationModelsExtras: "It is never trusted."
      - A search of every file that names `ConfigurationLayerName` or `DotfolderStack.Source` shows only these two exhaustive switches. `LayerFileWriter` switches on its own selection type, which has no marketplace member, thus it needs no change.
      - The enum has no `CaseIterable` and no `Comparable`, thus the position of the new case in the declaration carries no order meaning.

    No finding. The change is correct and complete.

    #### Deferred acceptance criterion

    "ACPAgent builds and all its tests pass" is deferred to card `^je0whap`. The suite is NOT green. Measurement over six full serial runs: the tree without this change fails the same 64 tests, and the tree with this change fails the same 64 tests. The set difference is empty in both directions. Before this change `main` did not compile at all. This change makes the build clean and adds no failure.

    - next: an operator pushes the commit. Card `^je0whap` clears the 64 red tests.
  timestamp: 2026-09-16T13:13:34.781415+00:00
- actor: claude-code
  id: 01m2n5mh9qsc3rjtkt4ngshp3q
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — ConfigurationLayerName.swift, InstructionsAssembler.swift, ConfigurationLoaderTests.swift (in FoundationModelsACPAgent)
    - test: measured, not green — 6 serial runs. The tree without the change fails 64 tests; the tree with the change fails the same 64. The set difference is empty in both directions. The change adds no failure and it repairs the build, because main did not compile before it.
    - commit: f9aeccd fix(configuration): add the marketplace case to ConfigurationLayerName — pushed to origin/main (ec9f73b..f9aeccd), with the user's approval
    - review: clean — 0 findings
    - result: the card is in done. The acceptance criterion "all its tests pass" is deferred to ^je0whap, which records the pre-existing breakage.
  timestamp: 2026-09-16T13:13:57.815822+00:00
position_column: done
position_ordinal: e280
title: 'ACPAgent: map DotfolderStack.Source.marketplace in ConfigurationLayerName'
---
## What

**Cross-repository task.** Run it from a session opened in `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent`. The `/finish` pipeline in FoundationModelsSkills cannot do it, because that pipeline commits only in FoundationModelsSkills.

FoundationModelsExtras `main` (d0048eb) added `DotfolderStack.Source.marketplace`. In ACPAgent, `ConfigurationLayerName.init(_ source: DotfolderStack.Source?)` (`Sources/FoundationModelsACPAgent/Configuration/ConfigurationLayerName.swift`) is an exhaustive switch with no `default`. ACPAgent stops compiling when it next resolves Extras `main`.

- Run `swift package update FoundationModelsExtras`.
- Add a `marketplace` case to `ConfigurationLayerName`, and add `case .marketplace?: self = .marketplace` to `init(_:)`. Fix every switch that the compiler then reports.
- Commit `Package.resolved` and the change. The push is an operator step.

- [x] Update the Extras pin — `Package.resolved` already held Extras `main` at `8ec26d4`, thus the update wrote nothing
- [x] Add the `marketplace` case and the mapping; fix the reported switches
- [ ] Test and commit

## Acceptance Criteria
- [ ] ACPAgent builds and all its tests pass, with zero warnings, against Extras d0048eb or later — the build is clean with no warning, but the suite is red for a cause this card did not make; see `^je0whap`
- [x] `ConfigurationLayerName(.marketplace)` gives `.marketplace`

## Tests
- [x] Add a test in ACPAgent's configuration tests: `ConfigurationLayerName(.marketplace) == .marketplace`
- [ ] Run `swift test` in ACPAgent; all green — blocked by `^je0whap`

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cross-repo