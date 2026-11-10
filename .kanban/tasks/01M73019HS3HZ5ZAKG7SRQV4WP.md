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
- actor: claude-code
  id: 01m7335wqq3d5td49bykd5b0g5
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (c04d4cc); 2 findings (2 confirmed, 4 refuted) — Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:1444, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:1447
    - next: Remove the assign-only properties `contents` and `diagnostics`, or read them, then run the review again.
  timestamp: 2026-11-10T16:03:10.199718+00:00
- actor: claude-code
  id: 01m7336ftg0zsfmf4ztcyw7ag4
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 19 files
    - test: green — swift test, 701 passed in 65 suites, 0 warnings
    - commit: c04d4cc
    - review: findings — Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:1444, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:1447
  timestamp: 2026-11-10T16:03:29.744960+00:00
- actor: claude-code
  id: 01m733cc27swtq7w41n3f9b6ax
  text: 'Review findings fix. Cause: the only reader of `CatalogFingerprint.contents` and `CatalogFingerprint.diagnostics` was the synthesized `==` of `Equatable`. Periphery cannot see synthesized reads. Fix: `CatalogFingerprint` now has an explicit `static func ==` that compares `metadata`, `contents` and `diagnostics`. Thus the comparison reads each property that it stores, and a rebuild still publishes only when the catalog changed. I did not use `// periphery:ignore`, because an explicit read removes the cause and a marker only hides it. No other private `Equatable`/`Hashable` type is in the file (the public types are retained by `--retain-public`). Proof: `periphery scan --skip-build --index-store-path .build/out --retain-public` gives the two findings on the old code (git stash) and zero findings in SkillsRegistry.swift on the new code. Note: on Swift 6.4 the index store is `.build/out` (it holds `v5`), not `.build/debug/index/store`. Periphery reports other assign-only properties in other files (Examples/skills-demo/WatchMode.swift, Tests/.../ScriptedLanguageModel.swift); they are not in this file and not in the findings.'
  timestamp: 2026-11-10T16:06:42.503303+00:00
- actor: claude-code
  id: 01m733cdm19ck252qy8nanqfek
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift (explicit `CatalogFingerprint.==`). `swift test`: 701 tests in 65 suites passed, 0 compiler warnings. Periphery: 0 findings in SkillsRegistry.swift. Both review findings checked.
    - next: /review
  timestamp: 2026-11-10T16:06:44.097802+00:00
- actor: claude-code
  id: 01m733e88c7hfn6sta5qgaeghf
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (bbe799a) — 0 findings (0 confirmed, 0 refuted, 7 attempted, 0 failed). All prior Review Findings items are checked.
    - next: The task is in done. Task 01M7301PF00406K3KN37EW4CHN is not blocked by this task now.
  timestamp: 2026-11-10T16:07:44.140788+00:00
- actor: claude-code
  id: 01m733em79jp0f4jar4yfawh6a
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 file (SkillsRegistry.swift)
    - test: green — swift test, 701 passed in 65 suites, 0 warnings
    - commit: bbe799a
    - review: clean — 0 findings; task in done
  timestamp: 2026-11-10T16:07:56.393243+00:00
position_column: done
position_ordinal: ffaa80
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

## Review Findings (2026-11-10 10:00)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 19 file(s) reviewed, 14 not reviewed.

> 14 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 14 file(s)

- [x] `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:1444` `code-hygiene/dead-code-swift` — var.instance `contents` is assignOnlyProperty.
- [x] `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:1447` `code-hygiene/dead-code-swift` — var.instance `diagnostics` is assignOnlyProperty.
