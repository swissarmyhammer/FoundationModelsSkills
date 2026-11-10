---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m732x34xkn19xx118pqagmqt
  text: |-
    Research and implementation notes.

    - Design: `SkillsRegistry.onReload` is now a non-optional `AsyncStream<[SkillMetadata]>`. Every registry has a `ReloadCoordinator`; it starts a `DotfolderWatcher` only when `watch` is `true`. A new private `CatalogRebuilder` holds the rebuild: load, replace and publish run under one `Mutex<CatalogFingerprint>`. The fingerprint is `metadata()` + `skillContents()` + `diagnostics`. The rebuild publishes only when the fingerprint changes. Diagnostics are in the fingerprint because an unparseable new skill changes only the diagnostics (test `reloadIntroducingAGenuinelyMalformedYAMLSkillSurfacesASkipDiagnostic`).
    - The registry holds the `EventBroadcaster` itself, and read-only views (`detachedReader`) share it. A view can outlive the coordinator, thus `EventBroadcaster.subscribe()` after `finishAll()` now gives a stream that is already finished (new test `EventBroadcasterTests`). Before, such a stream waited for ever.
    - `commandUpdates` stays optional because `SlashCommandProviding` (Extras) declares it optional; it is never `nil` now.
    - Callers changed: `SkillChangeFeed` (nil branch removed), `SkillsToolAssembly.makeContext` (notice follower always made), `SkillsRegistry+SlashCommands`, `Examples/skills-demo/WatchMode.swift`, doc comments of `SkillsToolContext` and `SkillsReloadFollower`.
    - Behavior change that existing tests showed: a rebuild that finds the same catalog no longer publishes. Changed tests: `HotReloadTests` step 2 (a no-op touch now gives no update), `SkillsGraphChangesTests.aReloadWithNoDifferenceGivesNoEvent` (no onReload value), `SkillsRegistryReloadTests.writingAFileDeepInsideASkillDirectoryGivesExactlyOneRebuild` (a reference file is not in the catalog; the test now counts catalog-load spans through an `InMemoryTracer`), `SkillsReloadFollowerTests` and `SkillsCatalogNoticeTests` (a `watch: false` registry now gets both followers), `SlashCommandProvidingTests` (the nil test became a write + `reload()` test).
    - Environment: `Package.resolved` (git-ignored) pinned an old FoundationModelsExtras commit without `ChangeLog`/`CatalogNoticeBoard`; `swift package update` was necessary to build.
    - Formatting: `swift format -i -r Sources Tests` with the toolchain default (2 spaces, 100 columns) rewrites all 135 files, because the repo has no `.swift-format` file and uses 4 spaces and 120 columns. I reverted that churn. Files that I changed are formatted to 4 spaces and 120 columns. A `.swift-format` configuration in the repo would prevent this; that is not part of this task.
  timestamp: 2026-11-10T15:58:21.853187+00:00
- actor: claude-code
  id: 01m732x90zsqfwmwnh2qfkzyjm
  text: |-
    ### implement — changed
    - evidence: 19 files. Sources: Registry/SkillsRegistry.swift, Registry/SkillsRegistry+SlashCommands.swift, Registry/EventBroadcaster.swift, GraphQL/SkillChangeFeed.swift, Operations/SkillsToolAssembly.swift, Operations/SkillsToolContext.swift, Search/SkillsReloadFollower.swift; Examples/skills-demo/WatchMode.swift. Tests: EventBroadcasterTests.swift (new), ReloadTestSupport.swift, SkillsRegistryReloadTests.swift, SkillsGraphChangesTests.swift, SlashCommandProvidingTests.swift, HotReloadTests.swift, HotReloadLiveTests.swift, MarketplaceLocalSourceTests.swift, MarketplaceRegistryTests.swift, SkillsReloadFollowerTests.swift, SkillsCatalogNoticeTests.swift. `swift test`: 701 tests in 65 suites passed, 0 issues, no compiler warnings.
    - next: /review
  timestamp: 2026-11-10T15:58:27.871142+00:00
position_column: doing
position_ordinal: '80'
title: 'SK-6a: SkillsRegistry gets a public reload that always sends a change event'
---
## What
Part of SK-6 (TestudoApp/features/packages/foundationmodels-skills.md, SK-6; D87 (d), D175). After a write of the `skills` tool, the catalog must reload, and the `skills` endpoint (SK-5) must send a change event. Today `SkillsRegistry` has no public reload. Only the `DotfolderWatcher` or the marketplace updates start `ReloadCoordinator`'s `rebuild` closure (`Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`, `ReloadCoordinator.init`). A registry with `watch: false` and no marketplace has no `ReloadCoordinator`, thus `onReload` is `nil`, and `SkillChangeFeed` (`Sources/FoundationModelsSkills/GraphQL/SkillChangeFeed.swift:36`) sends no event.

Change `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`:
- Always make a `ReloadCoordinator` (the broadcaster), also with `watch: false`. Start the watcher only when `watch` is `true`. Thus `onReload` is never `nil`. Change each caller and each doc comment that says "`nil` for `watch: false`" (no backward compatibility, ARCHITECTURE.md). Remove the dead `nil` branch of `SkillChangeFeed`.
- Add the new method `public func reload()`. It runs the same `rebuild` as the watcher.
- One write gives exactly one `onReload` value, also on a `watch: true` registry. Today the watcher event of the write and the explicit `reload()` would both publish. The catalog notice follower and `SkillSearchAgent` would then get two events, and `ReloadTestSupport.expectExactlyOneEvent` fails. Rule: `rebuild` publishes only when the new catalog differs from the current catalog (compare `metadata()` or the skill contents). Thus the second rebuild publishes nothing.
- Make the rebuilds run one at a time: put load, replace and publish under one lock (or a serial queue) in `ReloadCoordinator`. Thus an old load cannot replace a newer catalog when a watcher event and `reload()` run at the same time.

## Acceptance Criteria
- [x] `SkillsRegistry.onReload` is not `nil` for a registry with `watch: false`.
- [x] `reload()` puts a skill that was written to disk into `metadata()` before it returns.
- [x] One write plus `reload()` gives exactly one `onReload` value with `watch: false` and with `watch: true`.
- [x] `reload()` with no change on disk gives no `onReload` value.
- [x] A watcher rebuild and a `reload()` at the same time end with the newest catalog.
- [x] A `subscription` of the `skills` endpoint over a `watch: false` registry gets one change event after a write and `reload()`.

## Tests
- [x] `Tests/FoundationModelsSkillsTests/SkillsRegistryReloadTests.swift`: `watch: false` and `watch: true` cases of write + `reload()` with `ReloadTestSupport.expectExactlyOneEvent`; a no-change `reload()` case; a concurrent `reload()` + watcher event case.
- [x] `Tests/FoundationModelsSkillsTests/SkillsGraphChangesTests.swift`: one `ChangeLog` entry after write + `reload()` on a `watch: false` registry.
- [x] Update each test that asserts `onReload == nil` for `watch: false`. `HotReloadTests` and `TelemetryContentSafetyTests` still pass.
- [x] `swift test` passes with no warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1