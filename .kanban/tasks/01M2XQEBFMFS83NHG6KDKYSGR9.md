---
assignees:
- claude-code
position_column: todo
position_ordinal: '9480'
title: SkillDiscoveryTests keeps private copies of the layer-fixture helpers
---
## What

Card ^xhb2s4d added `Tests/FoundationModelsSkillsTests/LayerFixtureSupport.swift`, which gives `makeLayerDirectories(count:)`, `removeDirectories(_:)` and `writeTextFile(at:in:)` to each test that makes more than one layer directory on disk.

`Tests/FoundationModelsSkillsTests/SkillDiscoveryTests.swift` holds a private copy of each of those three helpers (`makeTempDirectory`, `makeTempDirectories(count:)`, `removeDirectories(_:)`, `writeTextFile(at:)`). The copies were there before the new file, thus card ^xhb2s4d left them alone.

## The work

1. Delete the four private helpers from `SkillDiscoveryTests`.
2. Point each call at `LayerFixtureSupport`, or at `WatcherTestSupport.makeTempDirectory()` for the tests that need one directory only.
3. Keep `writeSkillFile(in:)`, which is of that suite alone.

## Acceptance Criteria

- [ ] `SkillDiscoveryTests` makes no temporary directory of its own.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

#skills #tests