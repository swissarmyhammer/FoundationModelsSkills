---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2qv5r797c3xkv8b5jfns17g
  text: |-
    ### Research — the root cause is found, with evidence

    The three named commits (`ec9f73b`, `3e692c1`, `f9c8637`) are NOT the cause. They change
    prompt text and the bench only. The cause is in a dependency.

    `Package.resolved` is in `.gitignore`, so every family package floats to its `main`.
    FoundationModelsRouter moved from `d469aa0` to `da2a67a`, which merges the `pool` branch:
    the new `ModelPool` (`Sources/FoundationModelsRouter/Resolution/ModelPool.swift`).

    Bisection, each run `swift test --no-parallel --filter PromptTurnTests`, the Router pin set
    by hand in `Package.resolved`:

    | Router pin | Result |
    | --- | --- |
    | `d469aa0` (before the pool merge) | 28 tests passed |
    | `c80dc68` (the main side of the merge) | 28 tests passed |
    | `da2a67a` (current main) | 28 tests, 7 issues |

    `ModelPool` is process-wide. Its own documentation states the rule:

    > Every test router names a pool: pass a fresh `init()` result as the `pool:` argument of
    > `Router`. Suites run in parallel, and a stub one suite makes resident in `shared` would
    > satisfy another suite's key.

    `EchoModel.makeRouter` (`Sources/FoundationModelsACPAgent/Configuration/EchoModel.swift`)
    names no pool, so every stub router in the test process resolves into `ModelPool.shared`.
    The first scripted container made resident under the stub key then answers EVERY later
    test, whatever script that later test injected.

    That one cause explains each message:

    - A `.hold` script never holds, so the cancel never lands: stop reason `end_turn`, not
      `cancelled`.
    - A `.fail` script never throws: stop reason `end_turn`, not `refusal` or `max_tokens`.
    - A `[.endTurn]` script shows another test's output, so `generatedNothing` is false and the
      turn does not report `_no_output`.
    - The first turn is over before the second prompt arrives, so `PromptTurnTests.swift:144`
      sees no busy refusal, and two `user_message` updates instead of one.
    - `ToolCatalogTests.swift:137` asks for guided JSON and gets another suite's plain text:
      "Encountered content that cannot be completed into valid JSON".
    - A turn that plays a foreign script writes no response entry the recording waits for:
      `ResumeSessionFixture.swift:304`.

    It also explains why the failing set moves between runs while the suites stay the same: the
    winner of the shared key is whichever test resolves first.

    Note the proof that a leftover container answers: in `PromptTurnTests` the delta test
    `aScriptedTurnStreamsTheAcknowledgeThenNotifyOrder` runs first and PASSES, and every later
    test in the suite that needs its own script fails with the delta test's shape.
  timestamp: 2026-09-17T14:08:50.921196+00:00
- actor: claude-code
  id: 01m2qvjt6gxjc436ca2evgexm3
  text: |-
    ### The repair, by TDD

    **RED.** A new suite, `Tests/FoundationModelsACPAgentTests/ScriptedModelIsolationTests.swift`,
    makes two agents in one process, gives each one its own script, prompts each one, and
    reads the agent text of each turn. It failed with the defect word for word:

        ScriptedTurnFixture.agentText(in: secondUpdates) → "the first agent answers"
        Self.secondAnswer → "the second agent answers"

    **GREEN.** `EchoModel.makeRouter` now names a pool of its own,
    `pool: ModelPool()`, and its doc comment states why. The doc names the pool rule:
    the FIRST loader wins a key, and a later router over one shared pool gets the
    container the first loader made.

    `Tests/FoundationModelsACPAgentTests/Support/ScriptedTurnFixture.swift` gained the
    reader `agentText(in:)`, beside the other sequence readers.

    **Measured, whole suite, after the repair.**

    | Run | Tests | Issues |
    | --- | --- | --- |
    | `swift test` (parallel) | 563 | 16, one of them a known issue |
    | `swift test --no-parallel`, run 1 | 563 | 16, one of them a known issue |
    | `swift test --no-parallel`, run 2 | 563 | 16, one of them a known issue |

    The two runs give the same result, so the result is stable. Before the repair the
    serial run gave 98 issues. `swift build --build-tests` gives no compiler warning; the
    one warning in the log, "missing creator for mutated node" on the mlx bundle, comes
    from SwiftPM and was there before this change.

    ### The gap: a SECOND cause, which needs a person

    The 15 remaining issues are all in `TierTwoTests`, and they are NOT the cause this
    card names. `FoundationModelsMultitool` commit `b6a3f97` changed the `runCode` answer:
    a short snippet now answers with its own result inside
    `MultiToolConfiguration.inlineSettleGrace` — stock two seconds — and makes no `wait`
    call. Four `TierTwoTests` proofs read the snippet result from the `wait` answer, which
    is now empty.

    Measured, the Multitool pin set by hand:

    | Multitool pin | `swift test --no-parallel --filter TierTwoTests` |
    | --- | --- |
    | `579730c` (before `b6a3f97`) | 8 tests passed |
    | `652a65d` (current main) | 8 tests, 15 issues |

    Those four tests are no longer valid as written, and the reason is that the upstream
    default changed under the agent. I did NOT weaken them, and I did not choose for the
    agent: either the agent takes `inlineSettleGrace: 0` and keeps the two-step lifecycle
    plan.md §8.4 and §11.6 document — which is also what the "no hard-coded times" rule
    asks, because two seconds is a built-in interval the agent did not choose — or the
    agent takes the inline answer, plan.md says so, and the four proofs read the result
    from the `runCode` answer. A person must choose. Card `^fry23gm` holds the choice and
    the evidence.

    Card `^321e315` holds the other small item found on the way: `ConfigOptionsTests` still
    keeps a private copy of the `agentText` reader.
  timestamp: 2026-09-17T14:15:58.928483+00:00
- actor: claude-code
  id: 01m2qvk00qc5zw55xdj5t2v122
  text: |-
    ### implement — stuck
    - evidence: 3 files — /Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Configuration/EchoModel.swift, /Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent/Tests/FoundationModelsACPAgentTests/Support/ScriptedTurnFixture.swift, /Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent/Tests/FoundationModelsACPAgentTests/ScriptedModelIsolationTests.swift. `swift test`: 563 tests, 98 issues before, 16 after (one of them a known issue), the same in two serial runs and in a parallel run. `swift build --build-tests`: no compiler warning.
    - next: a person chooses the answer on card ^fry23gm. The 15 remaining issues, all in TierTwoTests, come from the Multitool `inlineSettleGrace` change, not from the cause this card names. No test was weakened.
  timestamp: 2026-09-17T14:16:04.887605+00:00
- actor: claude-code
  id: 01m2qvn7srhgpzh2q85g35rndz
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — 3 files in FoundationModelsACPAgent: Configuration/EchoModel.swift, Tests/Support/ScriptedTurnFixture.swift, Tests/ScriptedModelIsolationTests.swift
    - test: red, but much better — 563 tests, 98 issues before, 16 after (1 of them a known issue). Stable over two serial runs and one parallel run.
    - commit: b414515 fix(echo-model): give each test router its own model pool — local only, not pushed
    - review: not run. The card cannot reach done in this iteration.

    **Cause one, repaired.** The three commits the card names are not the cause. `Package.resolved` is in `.gitignore`, thus the family packages float to their `main`, and two of them moved. FoundationModelsRouter merged a `pool` branch that adds a process-wide `ModelPool`. `EchoModel.makeRouter` named no pool, thus every stub router in the test process shared one container, and the test that resolved first answered every other test. Bisection over the Router pin: d469aa0 28 passed, c80dc68 28 passed, da2a67a 7 issues. A new test showed the defect before the repair: the second agent answered "the first agent answers".

    **Cause two, open, and it needs a person.** FoundationModelsMultitool b6a3f97 changed the `runCode` answer: a short snippet now answers inline inside `MultiToolConfiguration.inlineSettleGrace` (stock two seconds) and makes no `wait` call. Four `TierTwoTests` proofs read the result from the `wait` answer, which is now empty. With the Multitool pin at 579730c `TierTwoTests` passes; at 652a65d it gives 15 issues. All 15 remaining issues have this one cause.

    The choice, recorded on ^fry23gm: give the agent `inlineSettleGrace: 0`, which keeps the two-step lifecycle that plan.md 8.4 and 11.6 document and adds no built-in time; or take the inline answer, amend plan.md, and write the four proofs again. This is a product decision. The implementer did not weaken a test and did not choose.

    - guardrail: 1 stuck entry. The guardrail needs 3 and is not reached.
  timestamp: 2026-09-17T14:17:18.392108+00:00
position_column: doing
position_ordinal: '80'
title: 'ACPAgent: the scripted-turn and recording test suites are red on main'
---
## What

**Cross-repository task.** The code is in `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent`.

`swift test` in ACPAgent fails on `main` (`ec9f73b`) with 88 to 100 issues in about 19 suites. The failures are there before any change of the `^p22jjs2` card, and the card did not cause them.

Measured runs, each one written to a log file:

| Run | Tests | Issues |
| --- | --- | --- |
| `main` with a throwaway `default:` arm, so it compiles | 561 | 88 |
| The `^p22jjs2` change, parallel | 562 | 100 |
| The `^p22jjs2` change, `--no-parallel` | 562 | 98 |

The serial run shows that this is not a parallel-run race. The set of failing tests moves between runs, but the same suites fail every time: `TierTwoTests`, `PromptTurnTests`, `ElicitationRelayTests`, `SessionResumeTests`, `RunCodeSourceTests`, `CompositionInterruptTests`, `TranscriptStoreTests`, `RunCommandTests`, `TranscriptFidelityTests`, `PromptContentTests`, `ConfigOptionsTests`, `BuiltinCommandsTests`, `AgentCompositionTests`, `SessionLifecycleTests`, `InterruptTests`, `ExitCodeTests`, `EventLineWriterTests`, `CommandDispatchTests`, `CancellationTests`.

The messages point at one root: a scripted turn gives no response event.

- `ResumeSessionFixture.swift:304`: `"the recording never reached 1 response event(s)"` — 27 times in the serial run.
- `ScriptedTurnFixture.swift:230`: `"the collector never reached: the terminal exit report"`.
- `ToolCatalogTests.swift:137`: `Encountered content that cannot be completed into valid JSON`.
- `PromptTurnTests.swift:144`: `"expected the busy refusal"`.

The three commits before this state touch the builtin instructions text and the bench: `ec9f73b`, `3e692c1`, `f9c8637`. Read them first.

Note: `main` at `ec9f73b` does not compile at all, because `Package.resolved` pins Extras `8ec26d4`, which holds `DotfolderStack.Source.marketplace`, and two switches are exhaustive. Card `^p22jjs2` supplies that fix. Build that card first, or add the arms yourself, before you can run the suite.

- [ ] Find the one cause of the missing response event in the scripted turn
- [ ] Repair it, and keep each suite above green
- [ ] Run `swift test` twice, to show that the result is stable

## Acceptance Criteria
- [ ] `swift test` in ACPAgent gives zero failures and zero warnings
- [ ] Two runs in a row give the same result

## Tests
- [ ] The whole ACPAgent suite, parallel and `--no-parallel`

## Workflow
- Use `/tdd`. #cross-repo