---
position_column: todo
position_ordinal: '9e80'
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