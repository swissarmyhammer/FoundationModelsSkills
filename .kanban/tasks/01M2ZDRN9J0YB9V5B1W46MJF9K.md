---
comments:
- actor: claude-code
  id: 01m324gmdkwtacjcv7jt8a8rwn
  text: |-
    Picked up. Research done.

    Upstream check (step 1 of the card): `.build/checkouts/FoundationModelsExtras` stands at `cf4be5c`, which is `origin/main`, and it holds `Sources/FoundationModelsExtras/DotfolderWatcher.swift`. The pin is correct, thus the card is not blocked.

    Public surface of `DotfolderWatcher` that I read in the checkout:
    - `public final class DotfolderWatcher: @unchecked Sendable`
    - `public static let defaultDebounceInterval` (200 ms)
    - `public convenience init(roots: [URL], debounceInterval: DispatchTimeInterval = DotfolderWatcher.defaultDebounceInterval, onChange: @escaping @Sendable () -> Void)`
    - `public convenience init(stack: some DotfolderStacking, debounceInterval:..., onChange:...)`
    - `public func start()`, `public func stop()`, and a `deinit` that stops.

    No rule is lost. I compared the body of the local `SkillWatcher` with the body of `DotfolderWatcher` line by line: the debounce and the stale-timer number, the ancestor arming with the awaited children, the filter of an ancestor event, the cancel of a source that a later `installSource` replaces under the same path, the rebuild before `onChange`, and the reentrant `stop()` from inside `onChange` are all the same code. The one text difference is the file event mask, which Extras names as `fileEventMask` and this package wrote inline; the bits are equal.

    No test rule is lost either. Each of the 19 cases of `SkillWatcherTests` has a case of `DotfolderWatcherTests` in Extras with the same shape: the three single-change cases, the burst case, the two depth cases, the `.git` case, the missing root, the late root, the delete and create again, the escalation, the unrelated work under an armed ancestor, the deep ancestor, the unreadable directory, the descriptor leak of a root that comes before its parent, the change made while `onChange` runs, `stop()`, and the reentrant stop. Extras adds two cases (a stack watcher and the README example). Thus no card for the Extras board is necessary.

    `WatcherTestSupport.swift` stays: 9 other test files call `makeTempDirectory()` or `withTempDirectory(_:)`.

    Plan: write the source-scan guard test first (RED), then delete `Registry/SkillWatcher.swift`, give `ReloadCoordinator` a `DotfolderWatcher`, delete `SkillWatcherTests.swift`, and rewrite each doc comment that names `SkillWatcher`.
  timestamp: 2026-09-21T14:04:28.979504+00:00
- actor: claude-code
  id: 01m3254kq5przsgen9pgsehaq9
  text: |-
    Implementation landed.

    What changed:
    - Deleted `Sources/FoundationModelsSkills/Registry/SkillWatcher.swift` (491 lines) and `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift` (19 cases).
    - `SkillsRegistry.ReloadCoordinator` now holds `private let watcher: DotfolderWatcher?` and makes `DotfolderWatcher(roots: $0, onChange: rebuild)`. The schema half did not change: `watchedRoots`, the rebuild, the swap of `CatalogBox`, the marketplace `layerUpdates` task and the `EventBroadcaster` are the same code.
    - Rewrote each doc comment that named `SkillWatcher`: five in `Registry/SkillsRegistry.swift`, and five in the test target (`SkillsRegistryReloadTests`, `SkillsReloadFollowerTests`, `SkillOperationsTests`, `WatcherTestSupport`, `ReloadTestSupport`). Two of them named `SkillWatcherTests`, which is gone; I took the dead name out instead of pointing at the Extras suite, because a mirror to another repository goes stale. `ReloadTestSupport` also named `MarketplaceCatalogTests`, which an earlier card deleted; that sentence now names the marketplace suites.
    - `WatcherTestSupport.swift` stays. Nine test files call it.
    - `docs/` and `README.md` never named `SkillWatcher`, thus no document changed.

    New tests:
    - `Tests/FoundationModelsSkillsTests/NoFileSystemWatchTests.swift`: the source scan. It gives `SwiftSourceScan` a line test over `Sources/`, and reports a line that holds `DispatchSource`, `O_EVTONLY` or `SkillWatcher`. It follows the shape of `NoResourceFileReadTests` and `NoDotfolderStackExtensionTests`: two argument cases prove the line test reports the correct lines, and one case walks the tree. RED first: the run reported 24 lines of `SkillWatcher.swift` and `SkillsRegistry.swift` before the delete.
    - `SkillsRegistryReloadTests.writingAFileDeepInsideASkillDirectoryGivesExactlyOneRebuild`: the acceptance criterion names "a change of a file deep in a skill", and no registry-level case covered it -- each other reload case writes `<root>/<id>/SKILL.md`, one level below the root. The deep-file rule lived only in the watcher suite that this card deletes. The new case writes `<root>/deep-skill/references/notes.md` and waits for exactly one publication. I proved it can fail: with `watch: false` in place of `watch: true` the run reported both expectations of `expectExactlyOneEvent` as failures.

    No rule of this package is lost, thus no card for the Extras board is necessary. The comparison is in the comment above.

    `Examples/skills-demo/WatchMode.swift` still names `DispatchSource`, for `makeSignalSource(signal: SIGTERM)`. That is a signal source and not a watch of the file system, and `Examples/` is not under `Sources/`, thus the guard does not reach it and must not.
  timestamp: 2026-09-21T14:15:23.621961+00:00
- actor: claude-code
  id: 01m3254snedc8dweh6wkgwdpv2
  text: |-
    ### implement — changed
    - evidence: 6 files — deleted Sources/FoundationModelsSkills/Registry/SkillWatcher.swift and Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift; added Tests/FoundationModelsSkillsTests/NoFileSystemWatchTests.swift; changed Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Tests/FoundationModelsSkillsTests/SkillsRegistryReloadTests.swift, Tests/FoundationModelsSkillsTests/SkillsReloadFollowerTests.swift, Tests/FoundationModelsSkillsTests/SkillOperationsTests.swift, Tests/FoundationModelsSkillsTests/WatcherTestSupport.swift, Tests/FoundationModelsSkillsTests/ReloadTestSupport.swift. `swift build --build-tests`: 0 warnings, 0 errors. `swift test`: 580 tests in 55 suites, 5 runs in sequence, 0 failures.
    - next: /review
  timestamp: 2026-09-21T14:15:29.710402+00:00
- actor: claude-code
  id: 01m325a9z76a4n3rmjfgm91r7y
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` — 0 warnings, 0 errors. `swift test` — 580 tests, 55 suites, 0 failures, 0 skipped. `diagnostics check working` — 0 errors, 0 warnings.
    - checked: the local `SkillWatcher.swift` and `SkillWatcherTests.swift` stay deleted. `SkillsRegistry.ReloadCoordinator` makes `DotfolderWatcher(roots:onChange:)` of Extras. `NoFileSystemWatchTests.swift` scans `Sources/` for `DispatchSource`, `O_EVTONLY`, and `SkillWatcher` and finds none.
    - checked: each of the 18 active cases of the deleted `SkillWatcherTests.swift` has a matching case in `.build/checkouts/FoundationModelsExtras/Tests/FoundationModelsExtrasTests/DotfolderWatcherTests.swift` (the one `.disabled` root-only case matches too), so no watcher rule was dropped.
    - checked: `SkillsRegistryReloadTests.editingASkillFileTriggersExactlyOneRebuildAndOneOnReloadPublicationWithRefreshedMetadata`, `reloadRefreshesPreloadedBodiesAndDiagnostics`, `writingAFileDeepInsideASkillDirectoryGivesExactlyOneRebuild`, and `HotReloadTests.hotReloadEndToEndFiveStepScenario` still write real files under a real temp root to a real `SkillsRegistry(watch: true)` and wait for a real reload signal — proof of a true hot-reload path, not a mock.
    - next: /review
  timestamp: 2026-09-21T14:18:30.247562+00:00
depends_on:
- 01M2ZDRMMGTDZCMB4ZS15QQK20
position_column: doing
position_ordinal: '80'
title: Watch the layer roots with the Extras DotfolderWatcher; delete SkillWatcher
---
## What

**Status on 2026-09-20: not blocked.** The Extras card `^f2vtvn9` is done and pushed (commits `19af7e1` and `12257d2`): `DotfolderWatcher` is a public final class with two public convenience initializers (roots, and a stack), `defaultDebounceInterval`, `start()` and `stop()`. The build of this package is green with the shim in place and the public `DotfolderStack.init(layers:)` of Extras resolved at the same time: the compiler prefers the initializer of this module, and reports no ambiguity. Thus the shim card is a plain cleanup, and this card does not wait for it. `Package.resolved` of this package pins the Extras revision `cf4be5c`, which is `origin/main` of `FoundationModelsExtras` (checked on 2026-09-20; `swift build` of this package is green against it). The check of step 1 passes now; run it only to confirm the pin.

`Sources/FoundationModelsSkills/Registry/SkillWatcher.swift` (491 lines) is a recursive directory watcher with no skill content: it takes `roots: [URL]`, opens file descriptors with `open(path, O_EVTONLY)`, makes `DispatchSource` file system sources, lists directories with `FileManager`, and calls `onChange` after a quiet period. That is raw file system work, thus it belongs in `FoundationModelsExtras`.

This card needs the Extras card `^f2vtvn9` on the `FoundationModelsExtras` board ("Add DotfolderWatcher ..."), which moves the type and its tests.

1. **Check the upstream first.** Run `swift package update FoundationModelsExtras`. If the resolved revision has no `DotfolderWatcher`, stop, write a comment on this card, and leave it in To Do.
2. **Delete `Registry/SkillWatcher.swift`.** `SkillsRegistry.ReloadCoordinator` makes a `DotfolderWatcher(roots: watchedRoots, onChange: rebuild)` in its place. The schema half stays here and does not change: `LayerPlan.watchedRoots` (the local roots always; a marketplace root only when `isWatchable`), the rebuild of the catalog, the swap of `CatalogBox`, the `layerUpdates` signal of the marketplace provider, and the events of `EventBroadcaster`.
3. `SkillWatcher` is public today. Remove it from the public surface; it has no host use that `SkillsRegistry(watch: true)` does not cover. If `docs/` or `README.md` names it, change the text to name `DotfolderWatcher` of Extras.
4. **Tests.** Delete `Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift`; its cases live in Extras now. Keep `WatcherTestSupport.swift` only while another suite uses its temporary directory helper. The reload suites stay and must pass with the calls changed only: `SkillsRegistryReloadTests`, `HotReloadTests`, `SkillsReloadFollowerTests`, `MarketplaceRegistryTests`. These suites wait on the real 200 ms debounce and use no injected timer (`SkillOperationsTests.swift` and `SkillsReloadFollowerTests.swift` say so), thus the public surface of `DotfolderWatcher` is sufficient. Rewrite each doc comment that names `SkillWatcher` (`Registry/SkillsRegistry.swift` has five): the last card of this group walks comments too.

## Acceptance Criteria

- [x] `Registry/SkillWatcher.swift` does not exist, and no file of `Sources/FoundationModelsSkills/` names `DispatchSource`, `O_EVTONLY` or `SkillWatcher`.
- [x] `SkillsRegistry(watch: true)` rebuilds its catalog one time for a burst of changes, for a new skill folder, for a change of a file deep in a skill, and for a layer root that appears after the start.
- [x] A marketplace layer that is not watchable still reloads on the `layerUpdates` signal only.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green, 5 runs in sequence with no failure.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/SkillsRegistryReloadTests.swift`: each case passes with no change of its expected values, the five-reload burst case included.
- [x] `Tests/FoundationModelsSkillsTests/HotReloadTests.swift`: the named end-to-end hot-reload case passes.
- [x] A source scan test: no file under `Sources/` names `DispatchSource` or `O_EVTONLY`.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills
