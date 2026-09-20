---
depends_on:
- 01M2ZDRMMGTDZCMB4ZS15QQK20
position_column: todo
position_ordinal: '9680'
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

- [ ] `Registry/SkillWatcher.swift` does not exist, and no file of `Sources/FoundationModelsSkills/` names `DispatchSource`, `O_EVTONLY` or `SkillWatcher`.
- [ ] `SkillsRegistry(watch: true)` rebuilds its catalog one time for a burst of changes, for a new skill folder, for a change of a file deep in a skill, and for a layer root that appears after the start.
- [ ] A marketplace layer that is not watchable still reloads on the `layerUpdates` signal only.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green, 5 runs in sequence with no failure.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/SkillsRegistryReloadTests.swift`: each case passes with no change of its expected values, the five-reload burst case included.
- [ ] `Tests/FoundationModelsSkillsTests/HotReloadTests.swift`: the named end-to-end hot-reload case passes.
- [ ] A source scan test: no file under `Sources/` names `DispatchSource` or `O_EVTONLY`.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills
