---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2k8ajbzhq8n278s20dx9kmc
  text: |-
    Research: marketplace.md §8.1 to §8.3 and decisions 13 and 15 give the shape. §6.2 pins the event cases: `.checked(id:current:latest:)` and `.updateAvailable(id:from:to:)`. `MarketplaceEvent` held only `.updated` and `.failed`, thus both cases are new here. `current` and `from` are optional, as `.updated(from:)` already is: a cold marketplace holds no snapshot yet.

    Design of the store:
    - One `PassKind` (`.check` or `.update(force:)`) per request. `resolved(_:)` turns an update into a check when `checkOnly` is on, thus the dry run never fetches, also for an explicit `update()`.
    - Coalescing: `inFlight[index]` holds the task of the pass that runs now, with an id. A new request joins it when `PassKind.answers(_:)` says the running pass answers it; an update answers a check, a check answers no update. The task takes itself out of the table before it ends, thus a joiner that wakes later starts a pass of its own and no loop spins.
    - The interval loop sleeps on the injected clock, thus the package holds no interval. `stop()` cancels the loop and each pass that runs now.
    - `fetchTimeout` runs the fetch and one clock sleep in a task group. The first to end wins; the sleep gives `MarketplaceTimeoutError`, which the failure path turns into `.failed` with `keptVersion`.

    Test support (`MarketplaceUpdateTestSupport.swift`): a `ManualClock` (a `Clock` over a `Mutex`, with a sleep count and a wait for a sleeper), a `GatedGitTransport` that wraps another transport and holds a call until the test releases it or the task is cancelled, a `MarketplaceEventLog`, and a `TestSignal`. The gate wraps `RecordingGitTransport`, thus no count is written twice.
  timestamp: 2026-09-15T19:22:28.095053+00:00
- actor: claude-code
  id: 01m2k8at32rv5cgf8vyjmpqdqt
  text: |-
    ### implement — changed
    - evidence: 9 files — Sources/FoundationModelsSkills/Marketplace/{MarketplacePolicy,MarketplaceEvent,MarketplaceStore,MarketplaceStatus,MarketplaceTimeoutError}.swift, Tests/FoundationModelsSkillsTests/{MarketplaceUpdateTests,MarketplaceUpdateTestSupport,MarketplaceTestSupport,MarketplaceStoreTests}.swift. `swift test --filter MarketplaceUpdateTests`: 11 tests, 1 suite, all pass. `swift test`: 640 tests in 47 suites pass. `swift build --build-tests`: zero errors and zero warnings.
    - discovery: `theStoreHoldsALeaseOnTheSnapshotItServesAndReleasesTheOneItLeaves` fails in about one of four full runs. I stashed this work and ran the full suite four times on the code before it: the same failure appeared. Thus it is older than this card. It is now task ^432j35x.
    - next: /review
  timestamp: 2026-09-15T19:22:36.002930+00:00
- actor: claude-code
  id: 01m2kb4jwx639mm4mvfn8qg277
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (b4733fa) — 0 findings, 0 confirmed, 0 refuted; 7 validators; 10 files reviewed
    - time values: the diff has no built-in time. `checkInterval` and `fetchTimeout` default to `nil`, and the two `clock.sleep` calls use the value that the host gives.
    - next: the task moved to done.
  timestamp: 2026-09-15T20:11:37.757372+00:00
- actor: claude-code
  id: 01m2kb534y0hy9p61pw4aq02fw
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 9 files; `check()`, `stop()`, coalescing, the optional interval loop over an injected clock, and the fetch timeout as a task-group race; the host gives every time value
    - test: green — swift build --build-tests 0 warnings; swift test x4, 640 passed each run, 0 failed, 0 skipped. The step also found and corrected a real defect: the cache lock descriptors had no `O_CLOEXEC`, thus a forked child kept a `flock(2)` lock alive after this process closed it (task ^432j35x, now done). 34 full runs green after the fix.
    - commit: b4733fa feat(marketplace): add update checks and fix cache lock leak
    - review: clean — 0 findings; no hard-coded time value in the diff; task moved to done
  timestamp: 2026-09-15T20:11:54.398185+00:00
depends_on:
- 01M2H10AWYB2KQ6P0N4B43PG6M
position_column: done
position_ordinal: d780
title: Add update checks and automatic update to MarketplaceStore (no built-in times)
---
## What

marketplace.md §8.1–§8.3 and decisions 13 and 15. The package has no built-in time value. A check runs at `start()` and on request. A periodic check runs only when the host gives an interval. Pins and `.nextLaunch` are a separate task.

In `Sources/FoundationModelsSkills/Marketplace/MarketplaceStore.swift` and `MarketplacePolicy.swift`:
- `MarketplacePolicy` gets `checkInterval: Duration?` (default `nil`), `autoUpdate: Bool` (default `true`), `checkOnly: Bool` (default `false`), and `fetchTimeout: Duration?` (default `nil`). `SKILLS_MARKETPLACE_AUTOUPDATE=0` in the environment has the same effect as `autoUpdate: false`.
- `func check() async -> [MarketplaceStatus]`: one `remoteHead` for each git source. It publishes `.checked`, and `.updateAvailable` when the head differs. It never fetches.
- **Coalescing:** while a check or update of a marketplace is in progress, another request for it waits for the same `Task`. No second remote connection.
- `start()`: check each source. Update it when `autoUpdate` is on and `checkOnly` is off; otherwise publish `.updateAvailable`.
- Interval: only when `checkInterval` is not `nil`, a loop checks at that interval until `stop()`. The internal init takes a clock (`any Clock<Duration>`), so tests use a manual clock.
- `stop()` cancels the loop and any fetch in progress; `current` does not change. When `fetchTimeout` is set, a fetch that takes longer is cancelled and publishes `.failed` with `keptVersion`.

- [x] Policy fields and the environment switch
- [x] `check()` with coalescing
- [x] Update rules at `start()`: auto, off, `checkOnly`
- [x] The optional interval loop and `stop()`
- [x] `fetchTimeout` and cancellation

## Acceptance Criteria
- [x] With the default policy, `start()` makes one remote-head call for each source, and no later call happens until a request comes
- [x] Two concurrent `check()` calls make one remote-head call
- [x] `autoUpdate: false`, the environment switch, and `checkOnly` publish `.updateAvailable` and never fetch
- [x] `stop()` during a fetch ends the fetch, and `current` does not change
- [x] A fetch longer than `fetchTimeout` fails with `keptVersion`

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceUpdateTests.swift` with the counting `GitTransport` double, a blocking transport double, and a manual clock: default policy (no later calls); coalesced checks; auto-update fetch; `autoUpdate: false`; `checkOnly`; the environment switch; the interval loop advances only when the manual clock advances; `stop()` ends the loop; `stop()` during a blocked fetch (`current` unchanged); `fetchTimeout` with the manual clock
- [x] Run `swift test --filter MarketplaceUpdateTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace