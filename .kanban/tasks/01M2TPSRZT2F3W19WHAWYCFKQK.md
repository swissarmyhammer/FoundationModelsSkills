---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'MarketplaceCacheTests: two lock tests fail now and then in a loaded full parallel run'
---
## What

Two tests in the suite "Marketplace cache" (`Tests/FoundationModelsSkillsTests/MarketplaceCacheTests.swift`) failed during the work on card `^dfgw3nc`. The run was 25 full `swift test --filter FoundationModelsSkillsTests` runs with 64 `yes > /dev/null` load processes on 2026-09-18. Each test failed one time in 25 runs. Six runs with no load passed.

- `aLeaseHoldsItsSnapshotUntilItIsReleased` — `Expectation failed: !SnapshotLockProbe.isLocked(directory: directory)`. The snapshot folder was still locked after the release of the lease.
- `cleanupKeepsASnapshotThatASharedLockHolds` — `Caught error: Another writer holds the marketplace folder of ".../skills-ce750fb6/lock" now.`

The work on `^dfgw3nc` changed only `SkillWatcher.swift` and `SkillWatcherTests.swift`. It did not touch the marketplace cache.

## Context

Card `^01M2K8A6` found that a forked child process (from `RunScriptTests` or `ShellInjectionTests`) inherits an open lock file handle, and it added `O_CLOEXEC` to the `open(2)` calls. These two failures show the same symptom (a lock that stays after its owner released it, or a lock that a different holder has). Thus a path possibly remains where a child process gets a lock handle. An example: `posix_spawn` or `fork` that occurs between `open` and the moment the flag applies, or a handle that a different `open` call makes without the flag.

## The work

- [ ] Reproduce the two failures under a loaded full parallel run. Use `lsof` on the lock file at the moment of failure to name the process that holds the lock.
- [ ] Find the cause and correct it. Do not add a retry, a skip, or a longer wait.
- [ ] Make sure that 25 loaded full runs pass.