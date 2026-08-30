---
assignees:
- claude-code
depends_on:
- 01M19A09R1HSTQTHZJGV3640VH
position_column: todo
position_ordinal: '8480'
title: Run the gated live-model suite in the CI integration job
---
## What

`HotReloadLiveTests` is the only suite in this package that needs a real model. It never runs anywhere at present. Wire it into the shared workflow's integration job.

The shared workflow gives two ways to do this. `integration-filter` is the current one. `integration-gate-env` is marked LEGACY in `../workflows/.github/workflows/swift-ci.yaml:48-53`, and its own text says `integration-filter` replaces it. Use `integration-filter`.

`integration-filter` selects tests, but it does not set an environment variable. Thus the double gate in `Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift` must change:

1. Remove the `SKILLS_INTEGRATION_TESTS` environment-variable gate and its two helper properties, `isIntegrationFlagSet` and `modelAvailabilityGatePasses`.
2. Keep the `SystemLanguageModel.default.isAvailable` gate as the only gate. A developer machine with no Apple Intelligence still skips the suite, and it is still a Swift Testing skip, never a failure and never a silent no-op.
3. Correct the suite doc comment. It describes a two-part gate that will no longer exist.

Then change `.github/workflows/ci.yml`:

```yaml
    with:
      # Hold the live-model suite out of the unit job: it needs Apple
      # Intelligence on the runner.
      test-skip: FoundationModelsSkillsTests.HotReloadLiveTests
      # Run that same suite, and only it, in the integration job.
      integration-filter: FoundationModelsSkillsTests.HotReloadLiveTests
```

Confirm the exact selector form against the `test-filter` input description in the shared workflow before you commit.

Correct the `CIWorkflowTests` case that pins the input set. It must now assert the two inputs above are present, and that no other `integration-*` input is present.

Also correct `docs/development.md`, which tells a developer to set `SKILLS_INTEGRATION_TESTS=1`.

- [ ] Simplify the `HotReloadLiveTests` gate to model availability alone.
- [ ] Add the two inputs to `ci.yml`.
- [ ] Correct `CIWorkflowTests` and `docs/development.md`.
- [ ] Run the full test suite.

## Acceptance Criteria

- [ ] A plain `swift test` on a machine with no Apple Intelligence reports `HotReloadLiveTests` as skipped, not failed.
- [ ] A plain `swift test` on a machine with Apple Intelligence runs `HotReloadLiveTests` with no environment variable set.
- [ ] `grep -r SKILLS_INTEGRATION_TESTS` over the repository gives no result.
- [ ] `ci.yml` passes `test-skip` and `integration-filter`, and no other `integration-*` input.

## Tests

- [ ] Change the `CIWorkflowTests` input case: assert that `ci.yml` holds a `test-skip` line and an `integration-filter` line, both naming `FoundationModelsSkillsTests.HotReloadLiveTests`, and that no `integration-package-path`, `integration-skip`, or `integration-gate-env` line is present. Match the key case-insensitively, for the reason the sibling suite records.
- [ ] Add a test case that asserts no source file, test file, or workflow file names `SKILLS_INTEGRATION_TESTS`. This pins the removal of the gate.
- [ ] `swift test` passes, and it reports `HotReloadLiveTests` as skipped on a host with no model.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.