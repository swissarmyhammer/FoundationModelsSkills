---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19f2tp44a4hnvzx858rqvvy
  text: |
    Picked up. Research notes:

    - `SkillsRegistry.onReload` gives a fresh independent subscriber stream each access (`ReloadBroadcaster.subscribe()` makes a new `AsyncStream` with the default unbounded buffer). Thus a publication that lands between the subscribe call and the first pull is kept, not lost. The order rule on the card holds: take the stream first, read `metadata()` second.
    - The no-`self`-capture trap is recorded on `SkillsRegistry.detachedReader`.
    - `SkillSearchAgent` is a `Sendable` struct, thus the forwarding task can hold a copy with no lock.
    - `OperationTool.context` is `private` in the Operations package, thus a test cannot read `reloadFollower` off a built tool. The assembly step is split: a new `internal static func makeContext(...)` builds the `SkillsToolContext`, and the private `assemble` gives that context to `SkillsTool.make(context:)`. The tests reach `makeContext` with `@testable import`, which two test files in this package already use.
    - Test helpers: `HotReloadTestSupport.makeTempDirectory()` and `ReloadTestSupport.writeSkillFile(id:in:)` / `ReloadTestSupport.poll(_:until:timeout:)`.
  timestamp: 2026-08-30T13:52:28.356664+00:00
- actor: claude-code
  id: 01m19fddhqr14fb9gqaj0pc7v2
  text: |
    Implementation landed.

    What was built:
    - `Sources/FoundationModelsSkills/Search/SkillsReloadFollower.swift` — a `public final class ... Sendable` holding one `let forwarding: Task<Void, Never>`. `init` starts the task, `deinit` cancels it. The task closure names only `reloads` and `agent`; it never names `self`.
    - `SkillsToolContext` carries `public let reloadFollower: SkillsReloadFollower?`, with an `init` parameter defaulted to `nil`.
    - The three `SkillsTool.make` factories carry `followReloads: Bool = true` and pass it down.
    - The shared assembly step was split. `assemble(...)` now calls a new `internal static func makeContext(...)`, which takes `registry.onReload` FIRST and reads `registry.metadata()` second, then builds the follower with `reloads.map { ... }`.

    Two failure modes were each measured, not assumed:
    1. `SkillsReloadFollower` was temporarily changed to capture `self` (a `var forwarding: Task?` plus `Task { [self] in _ = self; ... }`, since the correct `let` shape makes the compiler refuse the capture outright). `releasingTheLastReferenceStopsTheForwardingTask` then FAILED at the counter assertion in 0.8 s. It failed; it did not hang. The time limit was never reached.
    2. The no-model factory default was temporarily set to `followReloads: false`. Both end-to-end cases then FAILED after the 10 s reload timeout. Thus each one genuinely measures the follower, and not the registry catalog.

    Both changes were reverted, and the suite is green.

    Notes for the next agent:
    - `SkillsCLI` and `Examples/skills-demo` build their contexts by hand with `SkillsToolContext(...)`, not through the factories. Thus they keep `reloadFollower == nil` and `WatchMode`'s own pump stays the only forwarder there. No double forward anywhere.
    - The release case counts forwards with an `AsyncStream(unfolding:)` fixture that records into an actor before each publication. That measures the forwarding task's own liveness directly, which no seam on `SkillSearchAgent` offers.
  timestamp: 2026-08-30T13:58:15.351981+00:00
- actor: claude-code
  id: 01m19fdht64wx0tw2ce4y2j205
  text: |
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsSkills/Search/SkillsReloadFollower.swift (new), Sources/FoundationModelsSkills/Operations/SkillsToolContext.swift, Sources/FoundationModelsSkills/Operations/SkillsToolAssembly.swift, Tests/FoundationModelsSkillsTests/SkillsReloadFollowerTests.swift (new, 5 cases). `swift test` — 395 tests in 30 suites passed, 0 failures, 0 compiler warnings.
    - next: /review
  timestamp: 2026-08-30T13:58:19.718619+00:00
depends_on:
- 01M199XKPWKJAFZ3RN8MX1RKQX
position_column: doing
position_ordinal: '80'
title: Follow registry reloads automatically from the tool factory
---
## What

A host that builds the tool with `watch: true` must now pump `registry.onReload` into `searchAgent.update(items:)` itself. The "just a tool" path must do this for the host.

`SkillsRegistry.onReload` is an `AsyncStream<[SkillMetadata]>?`. It is `nil` when the registry was built with `watch: false`.

Add `Sources/FoundationModelsSkills/Search/SkillsReloadFollower.swift`:

```swift
/// Forwards each registry reload publication to a search agent, and stops
/// when it is released.
public final class SkillsReloadFollower: Sendable {
    public init(reloads: AsyncStream<[SkillMetadata]>, agent: SkillSearchAgent)
    deinit  // cancels the forwarding task
}
```

### Two rules that make this work

1. **The forwarding task must capture only the stream and the agent, never `self`.** A `Task` started in `init` that captures `self` keeps the instance alive for ever, `deinit` never runs, and the release test hangs. This package already records that exact trap for itself on `SkillsRegistry.detachedReader`. Read that comment first.
2. **Subscribe before you seed.** `onReload` publishes "every publication from this point forward". A factory that reads `registry.metadata()` first and subscribes second drops any reload that lands in that window. Take the stream first, then read the seed catalog.

Then, in the `SkillsToolAssembly.swift` factories:
1. Add a `followReloads: Bool = true` parameter.
2. When `followReloads` is true and `registry.onReload` is not `nil`, build a `SkillsReloadFollower`.
3. Hold the follower on `SkillsToolContext` as a new `public let reloadFollower: SkillsReloadFollower?`, thus its life matches the life of the tool.

Add the new property to `SkillsToolContext` as a parameter with a default of `nil`, thus every current call site compiles with no change.

- [x] Add `SkillsReloadFollower` with its doc comments and the no-`self`-capture rule.
- [x] Add the `reloadFollower` property to `SkillsToolContext`.
- [x] Wire `followReloads` into the three factory overloads, subscribing before seeding.
- [x] Add the tests.

## Acceptance Criteria

- [x] A tool built by the factory over a `watch: true` registry finds a skill that was written to a layer root after the tool was built, with no host code between.
- [x] A tool built over a `watch: false` registry builds without error, and its `reloadFollower` is `nil`.
- [x] `followReloads: false` gives a `nil` follower even for a `watch: true` registry.
- [x] Every current `SkillsToolContext.init` call site compiles with no change.
- [x] No forwarding task outlives its tool. The release test finishes and does not hang.

## Tests

- [x] New file `Tests/FoundationModelsSkillsTests/SkillsReloadFollowerTests.swift`.
- [x] A test case builds a factory tool over a temporary `watch: true` root that holds one skill, writes a second skill file, awaits the reload, then dispatches `search skill` and asserts the new id is in the results. Use the temporary-directory and reload-await helpers in `Tests/FoundationModelsSkillsTests/HotReloadTestSupport.swift`.
- [x] A test case removes a skill directory and asserts the id leaves the search results.
- [x] A test case asserts `reloadFollower` is `nil` for a `watch: false` registry, and not `nil` for a `watch: true` one.
- [x] A test case releases the last reference to a follower and asserts that its forwarding task stops. Count the forwards with an actor counter. Give the case a Swift Testing time limit, thus a captured `self` fails the case instead of hanging the suite.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
