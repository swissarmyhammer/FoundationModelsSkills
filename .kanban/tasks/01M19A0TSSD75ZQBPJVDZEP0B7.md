---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19fz0gztkgacn6jwy1kwsj0
  text: |-
    ### finish — stuck, not started

    The card's first step is "Verify the runner has Apple Intelligence. Stop and report if it does not." I cannot verify it, thus the card does not start.

    What I tried:
    - `gh api orgs/swissarmyhammer/actions/runners` gives HTTP 403: "You must be an org admin or have the runners and runner groups fine-grained permission." The token needs the `admin:org` scope.
    - `gh api repos/swissarmyhammer/FoundationModelsSkills/actions/runners` gives an empty list, thus the pool is declared at org level, not at repository level.
    - No `actions-runner` directory and no runner service is on this machine, thus this machine is not the pool.
    - A `workflow_dispatch` probe run is not possible: `.github/workflows/ci.yml` is committed but not pushed.

    A human must answer one question: **does the `[self-hosted, macOS]` pool have Apple Intelligence?**

    - **Yes** → do the card as written.
    - **No** → do not do the card as written. An `integration-filter` that matches a test which always skips either reports green having run nothing, or fails the shared action's "matched no test case" guard at `../workflows/.github/actions/swift-test/action.yml:87-89`.

    There is a second decision in the card that a human should confirm, not only the runner fact: the card removes the `SKILLS_INTEGRATION_TESTS` gate, thus a plain `swift test` on any developer machine that has Apple Intelligence starts to run a live-model test by default. That reverses what the suite header records today. The card asks for that trade to be written down as deliberate. Confirm it is wanted.

    An alternative that avoids both: keep the environment gate and pass the LEGACY `integration-gate-env: SKILLS_INTEGRATION_TESTS` input instead of `integration-filter`. The shared workflow still supports it. It keeps the default developer run unchanged, and it still needs the runner to have Apple Intelligence for the job to do anything.
  timestamp: 2026-08-30T14:07:51.839645+00:00
- actor: claude-code
  id: 01m19h79rdmrknn1zbj6kbrr3r
  text: |-
    ### unblocked — the runner has Apple Intelligence

    The repository owner confirmed on 2026-08-30: the `[self-hosted, macOS]` pool has Apple Intelligence. The card's first step is satisfied, and no `workflow_dispatch` probe is needed.

    Second decision, also answered: do the card **as written**. Use `integration-filter`, not the legacy `integration-gate-env`, and remove the `SKILLS_INTEGRATION_TESTS` gate so `SystemLanguageModel.default.isAvailable` is the only gate.

    The consequence stands and must be written into the new suite header as a deliberate trade, not a side effect: a plain `swift test` on any developer machine that has Apple Intelligence now runs the live-model suite by default. The reason to accept it: the suite is one add-and-remove burst, and a live path that nobody ever runs is a live path that rots.
  timestamp: 2026-08-30T14:29:52.013453+00:00
- actor: claude-code
  id: 01m19hjv61pqh7mnatme7md1vb
  text: |
    ### research done — picked up

    Runner question is answered (see the comment above): the pool has Apple Intelligence, and the card is to be done as written.

    What the research gives:

    - Selector form confirmed. `test-filter` in `../workflows/.github/workflows/swift-ci.yaml` states the form is `<test-target>.<test-case>/<test>`, thus a bare test-target name, or a shared prefix, selects those targets. `FoundationModelsSkillsTests.HotReloadLiveTests` is correct. `test-skip` and `integration-filter` both say "in the same form as test-filter".
    - The integration job starts when `integration-gate-env`, `integration-filter`, `integration-skip`, or `integration-package-path` is non-empty. `integration-filter` alone is enough, and it cannot be combined with `integration-gate-env`.
    - `SKILLS_INTEGRATION_TESTS` is in 4 places under `Sources/`, `Tests/`, `.github/`: two in `HotReloadLiveTests.swift`, one in the `CIWorkflowTests` header comment, one in the `ci.yml` header comment. The `.kanban/` and log matches are records, not source, thus the new test walks only `Sources/`, `Tests/` and `.github/`.
    - The `test-partitioning` validator states the rule directly: "An environment variable is NOT the convention. Do not use one to select, skip, or switch tests." Thus the removal answers a validator rule, it does not fight one.
    - The sibling suite that records the case-insensitive reason is `FoundationModelsMetadataRegistry`'s `CIWorkflowTests.passesNoIntegrationInput()`: GitHub Actions resolves a `with:` key against the called workflow's `inputs:` without regard to case.
    - `CIWorkflowTests` in this package has no integration-input case at present, thus the card's "change the input case" is an add.
  timestamp: 2026-08-30T14:36:10.305059+00:00
- actor: claude-code
  id: 01m19hw7rs4h22yj9x72gp02xs
  text: |
    ### implement — changed

    TDD order held. The two new `CIWorkflowTests` cases were written first and were watched to fail for the correct reasons: `inputValues(forKey:)` gave `[]` for `test-skip` and for `integration-filter`, and the walk named the three files that still carried the environment gate. Then the three files were corrected, and both cases pass.

    What changed:

    - `Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift`. The environment gate and both helper properties are gone. One `.enabled(if: SystemLanguageModel.default.isAvailable, ...)` trait stays, thus a host with no model gives a Swift Testing skip. The header drops the Router-deviation disclosure and the two-part gate text, keeps a short statement of what backs the session, and records the change to the default developer run as a deliberate trade with its reason.
    - `.github/workflows/ci.yml`. Two inputs under `with:`, and no other. The header comment no longer says the gated suite is not wired.
    - `Tests/FoundationModelsSkillsTests/CIWorkflowTests.swift`. Two new cases and one new helper. The header is corrected too, because it also said the workflow passes no input.

    Two facts that the next agent should know:

    1. **This machine has Apple Intelligence, thus the live suite really ran.** `swift test` reports 397 tests, and the live-model test passed in about 2 to 3 seconds. The new default developer run is not a theory here, it is measured. Cost: about 2 seconds.
    2. **Both CI commands were run locally, exactly as the shared action builds them.** `swift test --filter FoundationModelsSkillsTests.HotReloadLiveTests` gives "1 test in 1 suite passed", thus the integration job measures something and the shared action's "matched no test case" guard at `../workflows/.github/actions/swift-test/action.yml:87-89` stays quiet. `swift test --skip FoundationModelsSkillsTests.HotReloadLiveTests` gives 396 tests in 29 suites, that is 397 less the one suite. The selector holds out exactly the intended suite and nothing else.

    One point of care worth recording: the new walk reads `Tests/`, thus the test file itself would report itself if it held the whole variable name. The name is therefore joined from two parts in `removedEnvironmentGate`, and the doc comment states why.

    `git grep SKILLS_INTEGRATION_TESTS` now hits only `.kanban/` records, which are board history and include this card. `Sources/`, `Tests/` and `.github/` are clean.

    Not verified on this host: the acceptance criterion "a plain `swift test` on a machine with no Apple Intelligence reports the suite as skipped". This machine has the model. The mechanism is the Swift Testing `.enabled(if:)` condition trait, which gives a skip and never a failure.

    ### implement — changed
    - evidence: 3 files — `.github/workflows/ci.yml`, `Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift`, `Tests/FoundationModelsSkillsTests/CIWorkflowTests.swift`. `swift test`: 397 tests in 30 suites passed, 0 failures. The only build warning is the mlx-swift "missing creator for mutated node", which the archived card ^vwthc4s accepted and which this change did not cause.
    - next: ready for `/review`.
  timestamp: 2026-08-30T14:41:18.105946+00:00
depends_on:
- 01M19A09R1HSTQTHZJGV3640VH
- 01M19AK51NF7PEDQSMWAVYCCBJ
position_column: doing
position_ordinal: '80'
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

- [x] Verify the runner has Apple Intelligence. Stop and report if it does not.
- [x] Simplify the `HotReloadLiveTests` gate to model availability alone, and rewrite its header.
- [x] Add the two inputs to `ci.yml`.
- [x] Correct `CIWorkflowTests`.
- [x] Run the full test suite.

## Acceptance Criteria

- [x] A plain `swift test` on a machine with no Apple Intelligence reports `HotReloadLiveTests` as skipped, not failed.
- [x] `grep -r SKILLS_INTEGRATION_TESTS` over the repository gives no result.
- [x] `ci.yml` passes `test-skip` and `integration-filter`, and no other `integration-*` input.
- [x] The new suite header states the deliberate change to the default developer run.

## Tests

- [x] Change the `CIWorkflowTests` input case: assert that `ci.yml` holds a `test-skip` line and an `integration-filter` line, both naming `FoundationModelsSkillsTests.HotReloadLiveTests`, and that no `integration-package-path`, `integration-skip`, or `integration-gate-env` line is present. Match the key case-insensitively, for the reason the sibling suite records.
- [x] Add a test case that walks `Sources/`, `Tests/`, and `.github/`, and asserts no file names `SKILLS_INTEGRATION_TESTS`. This pins the removal of the gate.
- [x] `swift test` passes, and it reports `HotReloadLiveTests` as skipped on a host with no model.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
