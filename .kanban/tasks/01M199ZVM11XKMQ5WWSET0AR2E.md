---
assignees:
- claude-code
depends_on:
- 01M199XKPWKJAFZ3RN8MX1RKQX
position_column: todo
position_ordinal: '8280'
title: Follow registry reloads automatically from the tool factory
---
## What

A host that builds the tool with `watch: true` must now pump `registry.onReload` into `searchAgent.update(items:)` itself. The "just a tool" path must do this for the host.

`SkillsRegistry.onReload` is an `AsyncStream<[SkillMetadata]>?` (`Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:179`). It is `nil` when the registry was built with `watch: false`.

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

1. **The forwarding task must capture only the stream and the agent, never `self`.** A `Task` started in `init` that captures `self` keeps the instance alive for ever, `deinit` never runs, and the release test hangs. This package already records that exact trap for itself at `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:806-812`. Read that comment first.
2. **Subscribe before you seed.** `onReload` publishes "every publication from this point forward" (`Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:925-927`). A factory that reads `registry.metadata()` first and subscribes second drops any reload that lands in that window. Take the stream first, then read the seed catalog.

Then, in the `SkillsToolAssembly.swift` factories:
1. Add a `followReloads: Bool = true` parameter.
2. When `followReloads` is true and `registry.onReload` is not `nil`, build a `SkillsReloadFollower`.
3. Hold the follower on `SkillsToolContext` as a new `public let reloadFollower: SkillsReloadFollower?`, thus its life matches the life of the tool.

Add the new property to `SkillsToolContext` as a parameter with a default of `nil`, thus every current call site compiles with no change.

- [ ] Add `SkillsReloadFollower` with its doc comments and the no-`self`-capture rule.
- [ ] Add the `reloadFollower` property to `SkillsToolContext`.
- [ ] Wire `followReloads` into the three factory overloads, subscribing before seeding.
- [ ] Add the tests.

## Acceptance Criteria

- [ ] A tool built by the factory over a `watch: true` registry finds a skill that was written to a layer root after the tool was built, with no host code between.
- [ ] A tool built over a `watch: false` registry builds without error, and its `reloadFollower` is `nil`.
- [ ] `followReloads: false` gives a `nil` follower even for a `watch: true` registry.
- [ ] Every current `SkillsToolContext.init` call site compiles with no change.
- [ ] No forwarding task outlives its tool. The release test finishes and does not hang.

## Tests

- [ ] New file `Tests/FoundationModelsSkillsTests/SkillsReloadFollowerTests.swift`.
- [ ] A test case builds a factory tool over a temporary `watch: true` root that holds one skill, writes a second skill file, awaits the reload, then dispatches `search skill` and asserts the new id is in the results. Use the temporary-directory and reload-await helpers in `Tests/FoundationModelsSkillsTests/HotReloadTestSupport.swift`.
- [ ] A test case removes a skill directory and asserts the id leaves the search results.
- [ ] A test case asserts `reloadFollower` is `nil` for a `watch: false` registry, and not `nil` for a `watch: true` one.
- [ ] A test case releases the last reference to a follower and asserts that its forwarding task stops. Count the forwards with an actor counter. Give the case a Swift Testing time limit, thus a captured `self` fails the case instead of hanging the suite.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.