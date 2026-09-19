---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2xref2bxtxdpstmtg5qwwpg
  text: |-
    Research, before the edits:

    - `LayerFixtureSupport` gives `makeLayerDirectories(count:)`, `removeDirectories(_:)`, `writeTextFile(at:in:)` and `resolvedPath(of:)`. `PathConfinementTests` and `SkillOverlayTests` already call it.
    - The two copies of `writeTextFile` have different signatures. `LayerFixtureSupport.writeTextFile` takes a relative path and a directory; the private copy in `SkillDiscoveryTests` took one URL. Each call site thus changed shape, from `at: roots[0].appendingPathComponent("review/scripts/lint.sh")` to `at: "review/scripts/lint.sh", in: roots[0]`.
    - The text the two helpers write is different: the shared helper writes the directory name into the text as well. No test of `SkillDiscoveryTests` reads the text of such a file, thus the difference changes no result.
    - `PathConfinementTests` already calls `LayerFixtureSupport.removeDirectories([directory])` for one directory, thus `SkillDiscoveryTests` now does the same in place of its own `try? FileManager.default.removeItem(at:)` line.

    What changed:

    - `SkillDiscoveryTests` lost `makeTempDirectory()`, `makeTempDirectories(count:)`, `removeDirectories(_:)` and `writeTextFile(at:)`. It keeps `writeSkillFile(in:)` and `comparableProjection(_:)`, which are of that suite alone.
    - The four tests that make more than one layer directory call `LayerFixtureSupport`. The four tests that need one directory call `WatcherTestSupport.makeTempDirectory()`.
    - `LayerFixtureSupport` now names the three suites that call it in its doc comment, and the doc of `removeDirectories(_:)` now covers one directory as well.
    - No third copy was made: one grep over `Tests/` finds `removeDirectories` and `writeTextFile` in `LayerFixtureSupport` only.
  timestamp: 2026-09-19T21:16:37.323189+00:00
- actor: claude-code
  id: 01m2xrek6vfhmnk27w994cjj6d
  text: |-
    ### implement — changed
    - evidence: 2 files -- Tests/FoundationModelsSkillsTests/SkillDiscoveryTests.swift, Tests/FoundationModelsSkillsTests/LayerFixtureSupport.swift (29 insertions, 74 deletions). `swift build --build-tests` exit 0, 0 warnings. `swift test` exit 0, 783 tests in 63 suites, 0 failures. `swift test --filter SkillDiscoveryTests` exit 0, 16 tests.
    - next: review
  timestamp: 2026-09-19T21:16:41.563377+00:00
- actor: claude-code
  id: 01m2xrhdrj0e2n1bg1bgj6vh31
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` — build OK, no warnings; `swift test` — 783 tests passed, 63 suites, 0 failed, 0 skipped, 0 warnings.
  timestamp: 2026-09-19T21:18:14.290029+00:00
position_column: doing
position_ordinal: '80'
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

- [x] `SkillDiscoveryTests` makes no temporary directory of its own.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

#skills #tests