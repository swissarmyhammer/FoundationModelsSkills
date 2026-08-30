---
assignees:
- claude-code
depends_on:
- 01M19A09R1HSTQTHZJGV3640VH
- 01M19AK51NF7PEDQSMWAVYCCBJ
position_column: todo
position_ordinal: '8480'
title: Run the gated live-model suite in the CI integration job
---
## What

`HotReloadLiveTests` is the only suite in this package that needs a real model. It never runs anywhere at present. Wire it into the shared workflow's integration job.

This task owns every change to `Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift`'s header and gate. No other task on this board rewrites that region.

### Verify the runner first

The shared workflow runs on `[self-hosted, macOS]`. Nothing on this board establishes that the pool has Apple Intelligence. Check it before you change the gate: start a `workflow_dispatch` run, or ask the pool owner.

- If the pool has no on-device model, **stop and report**. An integration job that matches a test which always skips either reports green having run nothing, or fails the shared action's "matched no test case" guard at `../workflows/.github/actions/swift-test/action.yml:87-89`.
- If it does, continue.

### Change the gate

`integration-filter` selects tests, but it sets no environment variable. Thus the double gate in `HotReloadLiveTests.swift` must change:

1. Remove the `SKILLS_INTEGRATION_TESTS` gate and its two helper properties, `isIntegrationFlagSet` (line 47) and `modelAvailabilityGatePasses` (line 63). Those are the only two occurrences of that variable name in the whole repository.
2. Keep `SystemLanguageModel.default.isAvailable` as the only gate. It stays a Swift Testing skip, never a failure and never a silent no-op.
3. Rewrite the suite header at lines 12-42. Two things there go stale: the "deviation from a literal Router-backed twin" disclosure, and the description of a two-part gate.

**Record the change to the default developer run as deliberate, not as a side effect.** The header at lines 55-62 states that an ungated `swift test` "never probes on-device model availability at all". After this task, a developer machine that has Apple Intelligence runs a live-model test on a plain `swift test`. Write that trade in the new header: the suite is cheap, one add and one remove burst, and a live path that no one ever runs is a live path that rots.

### Change the workflow

```yaml
    with:
      # Hold the live-model suite out of the unit job: it needs Apple
      # Intelligence on the runner.
      test-skip: FoundationModelsSkillsTests.HotReloadLiveTests
      # Run that same suite, and only it, in the integration job.
      integration-filter: FoundationModelsSkillsTests.HotReloadLiveTests
```

Confirm the exact selector form against the `test-filter` input description in `../workflows/.github/workflows/swift-ci.yaml`.

`docs/` holds no occurrence of `SKILLS_INTEGRATION`. No documentation change is needed for the variable.

- [ ] Verify the runner has Apple Intelligence. Stop and report if it does not.
- [ ] Simplify the `HotReloadLiveTests` gate to model availability alone, and rewrite its header.
- [ ] Add the two inputs to `ci.yml`.
- [ ] Correct `CIWorkflowTests`.
- [ ] Run the full test suite.

## Acceptance Criteria

- [ ] A plain `swift test` on a machine with no Apple Intelligence reports `HotReloadLiveTests` as skipped, not failed.
- [ ] `grep -r SKILLS_INTEGRATION_TESTS` over the repository gives no result.
- [ ] `ci.yml` passes `test-skip` and `integration-filter`, and no other `integration-*` input.
- [ ] The new suite header states the deliberate change to the default developer run.

## Tests

- [ ] Change the `CIWorkflowTests` input case: assert that `ci.yml` holds a `test-skip` line and an `integration-filter` line, both naming `FoundationModelsSkillsTests.HotReloadLiveTests`, and that no `integration-package-path`, `integration-skip`, or `integration-gate-env` line is present. Match the key case-insensitively, for the reason the sibling suite records.
- [ ] Add a test case that walks `Sources/`, `Tests/`, and `.github/`, and asserts no file names `SKILLS_INTEGRATION_TESTS`. This pins the removal of the gate.
- [ ] `swift test` passes, and it reports `HotReloadLiveTests` as skipped on a host with no model.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.