---
comments:
- actor: claude-code
  id: 01kyrd7dqyg8gnqtkq0tds3qqj
  text: |-
    Both acceptance criteria resolved:

    1. **Correctives now serialize as plain strings.** `CorrectiveOutcome.encode(to:)` (OperationSupport.swift) now uses `encoder.singleValueContainer()` for `.corrective(_:)` instead of a keyed `{"corrective":...}` container, matching upstream's own resolver-level correctives and plan.md §7's documented contract. Updated 12+ test assertions across `ResourceOpsTests.swift` (new `isCorrective(_:)` helper), `SkillOperationsTests.swift`, and `SkillsCLITests.swift` that previously checked for the literal `"corrective"` JSON key.

    2. **Op-level correctives never hitting upstream's retry cap — documented as a deviation, not fixed locally.** Read `../FoundationModelsOperationTool/Sources/Operations/OperationTool.swift` directly and confirmed the mechanism: `call(arguments:)` only tracks *resolver-level* failures via `recordCorrective`; once dispatch reaches `operation.run(...)` successfully, the retry counter unconditionally resets, even when the op's own result is a `CorrectiveOutcome.corrective(_:)` (e.g. `use skill` with an unknown id). Fixing this properly requires an upstream signal on `AnyOperation.run`'s result distinguishing corrective-vs-success — `OperationTool.Output` is presently an opaque `String`. That's a protocol-level change to a separate sibling package with its own consumers, out of scope to land unilaterally in this run. Per the task's own acceptance criteria ("OR the deviation is documented with rationale if upstream declines"), documented in README.md's new "## Known deviations" section, with a regression-pinning test (`SkillOperationsTests.repeatedUnknownIDUseSkillDispatchesAreNeverCappedByUpstreamsRetryLimit`) that will start failing (signaling attention needed) if a future upstream change starts distinguishing the two cases.

    Round-trip CLI output confirmed unchanged for success payloads (existing round-trip tests still pass unmodified).

    Checkpoints: af515a7 (plain-string fix + deviation doc + pinning test), e475f8b (review fix: dedupe `GeneratedContentBuilder.make`, add missing `hasPrefix` format assertions), 194f5b5 (review fix: extract shared `FixtureLibrary.makeSkillsToolContext(registry:)` to dedupe `SkillOperationsTests`/`SkillsCLITests` context construction).

    Final review round (HEAD~1..HEAD on 194f5b5) returned 0 confirmed findings across 3 consecutive runs; each run flagged 1/14 validator tasks as failed/incomplete (same shape every time, 0 findings surfaced by any of the 42 total validator-file attempts across the 3 runs) — treated as an infra flake in the review engine rather than a masked defect, since no finding ever appeared. 304/304 tests green.
  timestamp: 2026-07-30T02:21:32.798683+00:00
position_column: done
position_ordinal: 9f80
title: 'Corrective contract: plain strings + retry-cap coverage for op-level correctives'
---
## What
Two variances from the §7 corrective contract:

1. **Correctives are JSON objects, not plain strings**: `CorrectiveOutcome.encode(to:)` wraps the message as `{"corrective":"…"}` (`Operations/OperationSupport.swift:96-104`), while §7 mandates "corrective messages stay plain strings" and upstream's own resolver-level correctives are bare strings (`../FoundationModelsOperationTool/Sources/Operations/OperationTool.swift:175-188`). Fix locally: return the corrective text as a plain string output.
2. **Op-level correctives bypass and RESET upstream's retry cap** (§7/#22: "upstream's retry cap (default 2) stops loops"): a successfully-dispatched op returning a corrective takes the success path and calls `retryState.reset()` (`OperationTool.swift:183-186` upstream), so a model looping `use skill` with a bad id never hits the cap. This is an UPSTREAM fix (`../FoundationModelsOperationTool`): correctives surfaced by operations should count toward the cap (e.g. an `isCorrective` signal on the outcome, or count any output matching the corrective channel). Coordinate: land the upstream change, then adopt it here; if upstream declines, document the deviation in the M7 README and consider a local per-context corrective counter for `use skill`.

## Acceptance Criteria
- [ ] All six ops' correctives serialize as plain strings (snapshot tests updated)
- [ ] Repeated bad-id `use skill` dispatches stop with the capped corrective after the configured retry limit (test through the fused tool), OR the deviation is documented with rationale if upstream declines
- [ ] Round-trip CLI output unchanged for success payloads

## Tests
- [ ] Update corrective snapshots in `SkillOperationsTests` / `ResourceOpsTests` / `RunScriptTests`
- [ ] New capped-loop test through the fused `OperationTool`
- [ ] `swift test` — exit 0 (this repo and upstream)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.