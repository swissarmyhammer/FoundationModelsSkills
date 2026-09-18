---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2qxycjy85wehewbxvfffpas
  text: |-
    Research, before the edits.

    The survey on the card counts 14 blocks. A second survey, made with a script that classifies each `guard` by its enclosing function, counts **37**. The card survey missed two groups:

    1. Tests written as `@Test func name()` on ONE line. A survey that keys on a separate `@Test` attribute line skips the whole body. This hides `CancellationTests` (2 more), `PromptTurnTests` (3 more), `EventProjectionTests` (7), `PromptContentTests` (8), `TerminalStreamTests` (2).
    2. `EventProjectionTests` was read as closure-only. Six of its seven blocks sit directly in a test body.

    The full count, per file: CancellationTests 3, CommandRegistryTests 2, EventProjectionTests 7, InitializationTests 2, PromptContentTests 8, PromptTurnTests 7, SessionLifecycleTests 1, TerminalStreamTests 2, Integration/TierTwoTests 5.

    The acceptance criterion on the card reads "No `guard` that ends a test body with a bare `return` in the ACPAgent test target". That criterion covers all 37, and the 14 named blocks are a subset of them. The work therefore corrects all 37. The script is kept in the scratchpad and is run again at the end to prove the count is zero.

    Some blocks are more dangerous than others, and the count does not say which. `CancellationTests` line 103 and line 124, for one example, each carry an `#expect(idle.stopReason == ...)` AFTER the guard. A wrong terminator skips that check today.

    Design, after the pattern of card ^9kbzt9k:
    - Readers shared by more than one suite go in `Support/ProjectionTestSupport.swift`, beside the `toolCallUpdates` and `texts` readers already there. They cover the state updates (`idle`, `running`, `requires_action`), the message updates, and a generic `PatchField` value reader.
    - Readers used by one suite stay `private static` in that suite, as `EventProjectionTests.objectFields` already does.
    - Each reader RETURNS an optional. A `guard` inside it gives a value to its caller and does not end a test. Each call site unwraps with `try #require` or checks with `#expect`.
  timestamp: 2026-09-17T14:57:15.358235+00:00
- actor: claude-code
  id: 01m2qypgcy4wg00phm8jd1kq5h
  text: |-
    The work is done. Two findings change what the card says, and both come from measurement.

    ## Finding 1: the count is 37, not 14

    A script that classifies each `guard` by its enclosing function found 37 blocks, not 14. The card survey missed every test written as `@Test func name()` on ONE line, and it read `EventProjectionTests` as closure-only. The acceptance criterion on the card — "No `guard` that ends a test body with a bare `return` in the ACPAgent test target" — covers all 37, so all 37 are corrected. The script now reports `total 0`.

    Per file: CancellationTests 3, CommandRegistryTests 2, EventProjectionTests 7, InitializationTests 2, PromptContentTests 8, PromptTurnTests 7, SessionLifecycleTests 1, TerminalStreamTests 2, Integration/TierTwoTests 5.

    ## Finding 2: the old form did NOT read as a pass

    The card says a broken program reads as a pass. **For these 37 blocks that is not true, and the measurement says so.** Every one of the 37 `else` bodies calls `Issue.record` before its `return`, and `Issue.record` fails the test. A script counted them: "records an issue: 37; records nothing: 0".

    So the defect these blocks carry is not a silent pass. It is this: the bare `return` ENDS THE TEST at the first mismatch, so every assertion after the block never runs. The test then reports one issue and hides what else is wrong, and it skips the cleanup that follows — `SessionLifecycleTests` skipped an `#expect` on the transcript and its `await fixture.close()`, and `TierTwoTests` had to repeat `await fixture.close()` inside the `else` body to make up for it.

    The change is still required, and for two reasons that hold:
    1. The `swift`/`optionals` validator rule states it word for word: "Never `guard` in a test. Unwrap with an assertion instead." The swiftformat rule `noGuardInTests` reports each of these blocks.
    2. The new form keeps checking. That is measurable, and it is measured below.

    The card asked for a proof that a rewritten site "can now fail where the old form would have passed". No such proof exists for these 37 sites, because the old form already failed. The honest proof of the real gain follows.

    ## The failure proof, measured on two rewritten sites

    The production file `Sources/FoundationModelsACPAgent/Agent/TurnState.swift` was perturbed: `awaitingUser` no longer sends `requires_action`, so the gate sends one update in place of two. The two rewritten sites read that sequence.

    | test | old form | new form |
    |---|---|---|
    | `awaitingUserPairsRequiresActionWithTheRouterGate` | 1 issue | 3 issues |
    | `awaitingUserReturnsToRunningWhenTheBodyThrows` | 1 issue | 3 issues |

    The old form stopped at the count mismatch and said nothing about the two state values. The new form reported the count, the wrong first state, and the missing second state. The perturbation is reverted: `git diff -- Sources/` is empty.

    A first proof attempt perturbed `EventProjection.diffChange(for:)` to map a move as a copy. Both forms failed with 1 issue, which is what led to Finding 2. That perturbation is reverted as well.

    ## The design

    Ten readers went into `Tests/FoundationModelsACPAgentTests/Support/ProjectionTestSupport.swift`, beside the readers already there: a generic `patchValue`, the state readers (`idleState`, `isIdleState`, `isRunningState`, `isRequiresActionState`), the message readers (`userMessageEcho`, `agentMessageChunk`, `agentMessageReplace`), `usageReport`, and `terminalUpdate`. Readers used by one suite stay `private static` in that suite. Each reader returns an optional, so the `guard` inside it gives a value to its caller and never ends a test.

    `PromptTurnTests` had the same three-assertion block in two tests; it is now one `private static func expectRequiresActionThenRunning(in:)` that both tests call.

    ## Notes for the next agent

    - `JSONValue` is ambiguous in `TierTwoTests`: write `FoundationModelsACP.JSONValue`.
    - `TurnStop` is a top-level type, not `PromptTurn.TurnStop`.
    - `TierTwoTests` site 4 dropped the `await fixture.close()` from its failure path. Every other unwrap in that same test already throws without closing, so the new code matches the prevailing form of the file.
  timestamp: 2026-09-17T15:10:25.694235+00:00
- actor: claude-code
  id: 01m2qyps81528g2zr9n7byekk5
  text: |-
    ### implement — changed
    - evidence: 10 files in `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent/Tests/FoundationModelsACPAgentTests/` — `Support/ProjectionTestSupport.swift` (10 new shared readers), `CancellationTests.swift` (3), `CommandRegistryTests.swift` (2), `EventProjectionTests.swift` (7), `InitializationTests.swift` (2), `Integration/TierTwoTests.swift` (5), `PromptContentTests.swift` (8), `PromptTurnTests.swift` (7), `SessionLifecycleTests.swift` (1), `TerminalStreamTests.swift` (2). 37 sites corrected, not the 14 the card counted; the survey script now reports 0. `swift test`: 16 issues before and 16 issues after, the same 5 failing tests, all inside `TierTwoTests` and all belonging to card ^fry23gm. No new test failed and no new suite failed. Build warnings: 1 before and 1 after, the same llbuild bundle line; no Swift compiler warning. No production file changed: `git diff -- Sources/` is empty. Failure proof, with `awaitingUser` perturbed to drop the `requires_action` send: `awaitingUserPairsRequiresActionWithTheRouterGate` and `awaitingUserReturnsToRunningWhenTheBodyThrows` each reported 1 issue in the old form and 3 issues in the new form; the perturbation is reverted. The card's own proof shape — old passes, new fails — is not possible here, because all 37 old `else` bodies call `Issue.record`; see the comment above.
    - next: /review
  timestamp: 2026-09-17T15:10:34.753623+00:00
- actor: claude-code
  id: 01m2qyzpv90e0sn5qtd7m1qt8k
  text: |
    ### review — findings
    - scope: `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent` at commit `66b1663`. The `review` engine cannot reach a sibling repository, so the team checked this change by hand.
    - evidence: 4 findings — TierTwoTests.swift:1244, TierTwoTests.swift:604, TierTwoTests.swift:616, InitializationTests.swift:69
    - verified correct: no `guard` stays directly in a `@Test` body (10 remaining `guard` statements are all in closures or loops that continue); the 37 rewritten sites keep the old assertion and the old message text; the 10 shared readers in `Support/ProjectionTestSupport.swift` each carry a doc comment and each has a call site; `swift test` gives 563 tests, 16 issues, 1 known, and the same 5 failures, all in `TierTwoTests`; a forced recompile of the test target gives zero compiler warnings; `Sources/` is untouched.
    - next: correct the 4 findings, then run `/review ^jv3nxd5` again.
  timestamp: 2026-09-17T15:15:27.209404+00:00
- actor: claude-code
  id: 01m2qzf9xmsvpdwcmvv3a6qrm1
  text: |-
    Iteration 2. The four findings are corrected. Notes for the next agent.

    ## Finding 1: the shape that closes the fixture on every path

    `defer { await fixture.close() }` COMPILES. `await` is legal in a `defer` body with the Swift 6.4 toolchain this package builds with. A separate `swiftc -typecheck -warnings-as-errors -swift-version 6` check proved it before the edit, and the package build then proved it again with zero compiler warnings.

    The other two shapes were rejected, and here is why:
    - `defer { Task { await fixture.close() } }` is the form 14 other blocks in this test target use (`BuiltinCommandsTests`, `CommandDispatchTests`). The `swift`/`concurrency` rule states: "Don't leak unstructured `Task { }`; prefer structured concurrency." A fire-and-forget task also does not close before the test ends. The prevailing form is therefore NOT the correct form here.
    - An explicit close on the failure path needs `do { ... } catch { await fixture.close(); throw error }`, because a `try #require` throws to the test runner and not to a local `else`. That re-indents 70 lines and adds two close calls.

    The correction: `defer { await fixture.close() }` sits under the fixture, and the `await fixture.close()` that stood before the last four assertions is removed. The wire now closes exactly once, at the exit of the test, on every path. Nothing reads the wire after that point; the convergence values are already in a local.

    ## The same defect elsewhere in the change: measured, and there is one site

    A script compared every function of the 10 changed files at `66b1663` with the same function at `66b1663~1`. It reports each function that holds a cleanup call with a throwing expression before it, and it says whether the throw is new.

    Result: **every** such function is marked `pre-existing`. Not one function gained its first throwing point before its cleanup. `git show 66b1663 | rg "^-.*close\("` agrees: the change removed exactly ONE cleanup call, the one at the exit-terminal site. The old bare `return` already skipped the trailing close at all the other sites, so the change made no other site worse.

    The script is at `scan_cleanup.py` in the scratchpad.

    ## Findings 2, 3 and 4: one reader for each JSON shape

    `Support/ProjectionTestSupport.swift` now holds `jsonObject(of:)` and `jsonString(of:)`, beside the other shared readers. Four copies are deleted: `TierTwoTests.jsonObject(of:)`, `TierTwoTests.jsonString(of:)`, `EventProjectionTests.objectFields(_:)`, `EventProjectionTests.stringValue(_:)`, `CommandDispatchTests.objectFields(in:)` and `InitializationTests.objectMembers(in:)`. 25 call sites now call the two shared readers.

    `EventProjectionTests` wrote `value ?? .null` before the match. The shared reader matches the optional directly, which gives the same answer for every input, so the `?? .null` is dropped at each call site.
  timestamp: 2026-09-17T15:23:58.260294+00:00
- actor: claude-code
  id: 01m2qzfpq1w6zz2xmdk1h5eb3v
  text: |-
    ### implement — changed
    - evidence: 5 files under `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent/Tests/FoundationModelsACPAgentTests/` — `Support/ProjectionTestSupport.swift` (+2 shared readers), `Integration/TierTwoTests.swift`, `EventProjectionTests.swift`, `CommandDispatchTests.swift`, `InitializationTests.swift`. 53 insertions, 92 deletions. All 4 findings are corrected and ticked.
    - issue count: 16 before (563 tests, 61 suites, 1 known issue) and 16 after, with the same 5 failing tests, all in `TierTwoTests`: `aDisabledShellSectionKeepsTheShellNamespaceOffTheSession`, `anOutOfRootReadRefusesInBandThroughTheCorrectionField`, `aRealToolCallProjectsAStableUpsertLifecycle`, `aClientDeclaredMCPServerMountsUnderItsOwnNoun`, `theCatalogComposesTheSurfaceFromTheLoadedConfiguration`. Card `^fry23gm` holds that fault.
    - proof that the fixture closes on the throwing path: a temporary `print("PROOF-FIXTURE-CLOSED")` went into `ScriptedTurnFixture.close()`, and the first `#require` at the exit-terminal site was forced to fail (`terminalUpdate(of: nil)`). With the `defer`, the run printed the failure message "expected the exit terminal_update to carry the output replacement" AND `PROOF-FIXTURE-CLOSED`, in that order. With the `defer` deleted, the same forced failure printed the marker 0 times. Both instrumentations are reverted; `git status` shows no change to `Support/ScriptedTurnFixture.swift`.
    - warnings: a forced recompile of the test target (`touch` on every file under `Tests/`, then `swift build --build-tests`) gave zero compiler warnings. The one `missing creator for mutated node` line comes from the SwiftPM build system for the `mlx-swift` bundle, and it is present before this change as well.
    - `Sources/` is untouched: `git diff -- Sources/` is empty. `acp-agent.score_fix1.json` and `logs/` stay untracked. No git worktree was made. Nothing is committed.
    - next: /review
  timestamp: 2026-09-17T15:24:11.361430+00:00
- actor: claude-code
  id: 01m2qznhzdvd4wzssqfq34awaw
  text: |
    ### review — clean (round 2, closing verification)

    Scope: `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent`, commit `5922652`. The `review` engine cannot reach a sibling repository, so the team checked this by hand. Only the four round-1 findings were verified. No new ground was opened.

    - evidence:
      1. **The fixture closes on every path — proved by measurement.** `TierTwoTests.swift` line 1188 holds `defer { await fixture.close() }` at the top of `aStreamedShellRunRidesTheTerminalStreamAndConverges()`, after `runToolTurn`. To prove the `defer` runs when a `#require` throws, the team put a marker write in `ScriptedTurnFixture.close()` and made the exit-terminal `#require` fail (`terminalUpdate(of: nil)`). The run gave this order:
         - `Test ... recorded an issue at TierTwoTests.swift:1226:30: Expectation failed: terminalUpdate(of: nil)`
         - `ZZMARKER-CLOSE-RAN`
         - `Test ... failed after 0.904 seconds with 1 issue.`
         The marker comes AFTER the thrown check and BEFORE the end of the test, so the close runs on the throwing path. Both instruments were then reverted with `git checkout --`, and `git diff` is empty.
      2. **One reader for each JSON shape.** `jsonObject(of:)` and `jsonString(of:)` are declared once, both in `Tests/FoundationModelsACPAgentTests/Support/ProjectionTestSupport.swift` (lines 218 and 230). `objectFields`, `objectMembers` and `stringValue` are gone from the test target. The remaining `.object` / `.string` matches are compound guards in files this commit did not touch (`AssertionHelpers.swift`, `ElicitationRelayTests.swift`, `SessionResumeTests.swift`, `PromptContentTests.swift`, `SessionSetupTests.swift`, `PromptTurnTests.swift`); each unwraps two values in one statement, so none is a copy of a single-shape reader.
      3. **The issue count did not grow.** `swift test`: `563 tests in 61 suites failed after 1.799 seconds with 16 issues (including 1 known issue)`. The 5 failing tests are all in `TierTwoTests`, the only failed suite: `aClientDeclaredMCPServerMountsUnderItsOwnNoun`, `aDisabledShellSectionKeepsTheShellNamespaceOffTheSession`, `anOutOfRootReadRefusesInBandThroughTheCorrectionField`, `aRealToolCallProjectsAStableUpsertLifecycle`, `theCatalogComposesTheSurfaceFromTheLoadedConfiguration`. Card `^fry23gm` holds that fault. Output went to a scratchpad log.
      4. **No new build warning.** A forced recompile (`touch` on every `.swift` file, then `swift build --build-tests`) gave exactly one warning line: `missing creator for mutated node: .../mlx-swift_Cmlx.bundle/Contents/MacOS`. That line comes from the SwiftPM build system for the `mlx-swift` bundle, and this change does not cause it. Zero compiler warnings. `Sources/` is untouched: the 5 files in `5922652` are all below `Tests/`. `git worktree list` names one checkout, the main one. The two untracked scratch paths (`acp-agent.score_fix1.json`, `logs/`) are still untracked.
    - next: none. All four round-1 findings hold. Card moved to `done`. The unchecked boxes that stay in the card body are the work list and the acceptance criteria, which the implementer did not tick; the review evidence above measures each of them.
  timestamp: 2026-09-17T15:27:23.117787+00:00
- actor: claude-code
  id: 01m2qzpjpkr520npjcxtpqavc3
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — Support/ProjectionTestSupport.swift, Integration/TierTwoTests.swift, EventProjectionTests.swift, CommandDispatchTests.swift, InitializationTests.swift
    - test: the count holds — 563 tests in 61 suites, 16 issues before and after, the same 5 failures, all in TierTwoTests (^fry23gm)
    - commit: 5922652 fix(tests): close fixture on every path in TierTwoTests
    - review: clean — 0 new findings, all 4 of iteration 1 hold
    - result: the card is in done.

    Finding 1 was a regression that the orchestrator's own instruction caused. The orchestrator told the iteration 1 agent to drop `await fixture.close()` from the failure path. That was wrong: `try #require` throws, thus the throw goes past the trailing close and the fixture never closed on a failure. A `defer { await fixture.close() }` now closes the wire one time on every path. The repository's usual form is `defer { Task { await fixture.close() } }`, and the agent correctly did not copy it, because an unstructured Task does not close before the test ends.

    Proof, made by the implementer and again by the reviewer: with a marker in `close()` and the exit-terminal `#require` forced to fail, the marker prints after the thrown check and before the end of the test. With the `defer` deleted, the marker prints zero times. Each instrument was reverted and `git diff` is empty.

    Findings 2 to 4: `jsonObject(of:)` and `jsonString(of:)` are now declared one time, in Support/ProjectionTestSupport.swift. Six copies are deleted, two of them older than this card, and 25 call sites read the shared readers.

    Iteration 1 also corrected the card itself: the count is 37 sites, not 14, and the card's stated reason was wrong. Every old block called `Issue.record` before the `return`, thus none let a broken program pass. The true gain is that a bare `return` no longer skips every assertion after it.
  timestamp: 2026-09-17T15:27:56.627581+00:00
position_column: done
position_ordinal: ea80
title: 'ACPAgent: 14 more guard-and-return blocks in test bodies'
---
## What

**Cross-repository task.** The code is in `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent`.

Card `^9kbzt9k` corrected the two `guard case ... else { ... return }` blocks in `Tests/FoundationModelsACPAgentTests/CommandDispatchTests.swift`. A sweep of the whole ACPAgent test target found 14 more blocks with the same cause. Each is inside a `@Test` function body, and each ends with a bare `return`, which takes the test out before the assertions that follow it.

Card `^9kbzt9k` proved the danger: with a wrong value, a `guard ... else { return }` lets the test report a pass, and the assertions after the block never run.

Use the same correction: an unwrap that fails. `try #require(...)` on the bound value, or `#expect(...)` on the condition.

### The blocks

- [ ] `SessionLifecycleTests.swift` — the idle state update
- [ ] `PromptTurnTests.swift` — 4 blocks: the user_message echo, the running state, and two requires-action pairs
- [ ] `CommandRegistryTests.swift` — 2 blocks: the `.action` body and the `.rendered` body
- [ ] `InitializationTests.swift` — 2 blocks: the capabilities tree and the initialize result
- [ ] `CancellationTests.swift` — the strict terminator
- [ ] `Integration/TierTwoTests.swift` — 5 blocks: the runCode rawInput, the runCode rawOutput, the wait rawOutput, the exit terminal update, and the settled call content

A `guard` inside a closure that returns a value — `CIWorkflowTests.swift`, `EventProjectionTests.swift`, `TranscriptFidelityTests.swift`, and two closures in `TierTwoTests.swift` — is NOT this cause. A closure returns a value to its caller; it does not end a test.

## Acceptance Criteria
- [ ] No `guard` that ends a test body with a bare `return` in the ACPAgent test target
- [ ] The issue count of a full `swift test` run does not grow
- [ ] No new build warning

## Tests
- [ ] `swift test`

## Review Findings (2026-09-17 10:14)

Scope: `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent`, commit `66b1663`. The `review` engine cannot reach a sibling repository, so the team checked this change by hand.

- [x] `Tests/FoundationModelsACPAgentTests/Integration/TierTwoTests.swift:1244` `manual/cleanup` — The rewrite of the exit-terminal block dropped the `await fixture.close()` call that the old block made on its failure path. The old `guard ... else` did `Issue.record`, then `await fixture.close()`, then `return`. The new `try #require` at this line and at line 1247 THROWS, so it goes past the `await fixture.close()` at line 1276, and the fixture never closes when either check fails. This change makes the cleanup worse, and the commit message names that same cleanup as the reason for the change. Close the fixture on every path. Put the fixture behind a `defer { ... }` block, or use the same shape the other tests in this file use.
- [x] `Tests/FoundationModelsACPAgentTests/Integration/TierTwoTests.swift:604` `manual/duplication` — The new `jsonObject(of:)` reader is a copy of `EventProjectionTests.objectFields(_:)` (line 178) and of `CommandDispatchTests.objectFields(in:)` (line 96). Each one unwraps `.object` from a `JSONValue?`. This change states that the case-match code is now in one place, but it adds a third copy. Move one reader to `Tests/FoundationModelsACPAgentTests/Support/ProjectionTestSupport.swift`, beside the other shared readers, and delete the copies.
- [x] `Tests/FoundationModelsACPAgentTests/Integration/TierTwoTests.swift:616` `manual/duplication` — The new `jsonString(of:)` reader is a copy of `EventProjectionTests.stringValue(_:)` (line 184). Both unwrap `.string` from a `JSONValue?`. Move one reader to `Support/ProjectionTestSupport.swift` and delete the copy.
- [x] `Tests/FoundationModelsACPAgentTests/InitializationTests.swift:69` `manual/duplication` — The new `objectMembers(in:)` reader is a fourth copy of the same `.object` unwrap. Use the shared reader from `Support/ProjectionTestSupport.swift` and delete this copy.

### What the review checked and found correct

- No `guard` stays directly in a `@Test` body. A scan of every `@Test` function in `Tests/` found 10 `guard` statements, and each one is inside a closure that gives a value to its caller (`TierTwoTests.swift:1225`, `:1230`, `:1237`, `:1264`, `:1292`; `TranscriptFidelityTests.swift:175`; `CIWorkflowTests.swift:415`) or inside a loop where the `else` branch does `continue` (`EventProjectionTests.swift:742`; `CIWorkflowTests.swift:291`, `:302`). None ends a test.
- The 37 rewritten sites keep the assertion of the old block and the old message text. The review compared each site against `git show 66b1663`.
- The 10 shared readers in `Support/ProjectionTestSupport.swift` each carry a doc comment and each has at least one call site: `patchValue` 8, `idleState` 3, `isIdleState` 2, `isRunningState` 2, `isRequiresActionState` 1, `userMessageEcho` 1, `agentMessageChunk` 2, `agentMessageReplace` 1, `usageReport` 1, `terminalUpdate` 1.
- `swift test`: 563 tests in 61 suites, 16 issues, 1 of them a known issue. The 5 failing tests are all in `TierTwoTests`, and card `^fry23gm` holds that fault. The count did not grow.
- No new build warning. A forced recompile of the test target (`swift build --build-tests` after `touch`) gave zero compiler warnings. The one `missing creator for mutated node` line comes from the SwiftPM build system for the `mlx-swift` bundle, and this change does not cause it.
- `Sources/` is untouched. All 10 changed files are below `Tests/`.
- The card premise was wrong, and the implementer corrected it. Every old block called `Issue.record` before the `return`, so no old block passed quietly. The review records no finding for this.
