---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0zn440cyr4g9kkse6ttsd0d
  text: |-
    ## Research — cause of the warning

    ### Dependency path
    This package does not declare `mlx-swift` and does not import `MLX` (no match in `Sources`, `Tests`, `Examples`). The dependency is transitive:

    `FoundationModelsSkills` -> `FoundationModelsMetadataRegistry` (main) -> `FoundationModelsRouter` -> `swissarmyhammer/mlx-swift-lm` (branch `stable`) -> `ml-explore/mlx-swift` `.upToNextMinor(from: "0.31.6")`.

    `Package.resolved` pins `mlx-swift` at `0.31.6` (revision `0bb916c`). `0.31.6` is the newest tag. The 10 commits on upstream `main` after the tag do not touch the `Cmlx` target, its resources, or the bundle.

    ### Cause
    The `Cmlx` target in `.build/checkouts/mlx-swift/Package.swift` (line 217) declares no `resources:`. It contains 49 `.metal` files under `Source/Cmlx/mlx-generated/metal`. SwiftPM treats `.metal` files as resources, compiles them to `default.metallib`, and puts the result in the resource bundle `mlx-swift_Cmlx.bundle/Contents/Resources`. The bundle has no `Contents/MacOS` directory.

    The warning comes from the swift-build build system (Swift 6.4, Xcode-beta), not from `mlx-swift`. In `.build/out/Intermediates.noindex/XCBuildData/*.xcbuilddata/manifest.json` the only command that names `mlx-swift_Cmlx.bundle/Contents/MacOS` is the `stale-file-removal` task for the target `mlx-swift_Cmlx-PACKAGE-RESOURCE`. Its `expectedOutputs` list includes `mlx-swift_Cmlx.bundle/Contents/MacOS` and `mlx-swift_Cmlx.bundle/_CodeSignature`, as if the bundle had an executable. No command has that path as an output. llbuild marks the node `is-mutated: true` and reports `missing creator for mutated node`. The three `mlx-swift-lm_*.bundle` resource bundles (plain resources, no Metal) get no `Contents/MacOS` node and no warning.

    The four `-Wc++17-extensions` warnings come from the Metal compile of `steel_attention.metal` inside the same `Cmlx` target.

    ### Options examined
    - (a) A different `mlx-swift` revision: not possible from this package. The pin is in `mlx-swift-lm/Package.swift` line 61. No newer tag exists, and the warning does not depend on the `mlx-swift` revision (it is toolchain behavior for a Metal-resource bundle).
    - (b) Remove the dependency: not possible. This package does not declare it.
    - (c) Files under `.build/checkouts` are not part of this repo and must not be patched.

    ### Baseline
    `rm -rf .build/out && swift build --build-tests 2>&1 | rg warning:` -> 5 warnings (1 `missing creator`, 4 `-Wc++17-extensions`). All 5 come from `mlx-swift`.
  timestamp: 2026-08-26T18:25:37.804460+00:00
- actor: claude-code
  id: 01m0zn4gs30amm8eyzm2mg0wtv
  text: |-
    ### implement — stuck
    - evidence: 0 source files changed. Cause found and recorded (research comment). The warning comes from the swift-build `stale-file-removal` task for the `mlx-swift_Cmlx` Metal resource bundle. `mlx-swift` `0.31.6` is the newest tag and is pinned by `mlx-swift-lm`, not by this package. Options (a), (b) do not apply; (c) `.build/checkouts` must not be patched.
    - next: a person decides. Report upstream (swift-build or mlx-swift), or move the `mlx-swift-lm` pin when a fixed release exists. Acceptance criteria 2 and 3 and the test line stay open.
  timestamp: 2026-08-26T18:25:50.883936+00:00
- actor: claude-code
  id: 01m0zn4j52f94njkhybmwf0n1v
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — cause recorded, no fix possible in this repo
    - test: not run — no change to test
    - commit: not run — nothing to commit
    - review: not run
    - note: a stale `swift-test` process (pid 21359) belongs to the `EditorKit` project, not this one. It was not killed.
  timestamp: 2026-08-26T18:25:52.290430+00:00
- actor: claude-code
  id: 01m0zn8tax170ejrk65tqsn10t
  text: |-
    ### Decision — warning accepted
    - The owner accepts the warning for now. The cause is in swift-build (Swift 6.4, Xcode-beta): the stale-file-removal task for a Metal-only resource bundle expects `Contents/MacOS`, which no command creates. This package cannot remove it.
    - The card is archived. Open it again when swift-build or the toolchain changes, or to report the defect upstream.
  timestamp: 2026-08-26T18:28:11.741667+00:00
position_column: doing
position_ordinal: '80'
title: 'Build warning from the mlx-swift dependency: "missing creator for mutated node" on mlx-swift_Cmlx.bundle/Contents/MacOS'
---
## What
Each `swift build --build-tests` and `swift test` in this package prints one build-system warning:

`warning: missing creator for mutated node: ('.build/out/Products/Debug/mlx-swift_Cmlx.bundle/Contents/MacOS')`

The warning comes from the `Cmlx` target of the `mlx-swift` dependency, not from a source file in this package. It reproduces with the working tree stashed (found while `^w5mjseg` was in test), and after a full delete of `.build/out`. A clean build of that target also prints four `-Wc++17-extensions` warnings from `Source/Cmlx/mlx-generated/metal/steel/attn/kernels/steel_attention.h`.

## Acceptance Criteria
- [x] Find the cause in the `mlx-swift` package manifest (the `Cmlx` resource bundle or its build plugin) and record it on this card
- [ ] Remove the warning: an upstream fix in `mlx-swift`, or a pinned revision that does not print it
- [ ] `swift build --build-tests` prints zero warnings

## Tests
- [ ] `swift test` — exit 0, zero warnings

## Blocker
The cause is not in this repo. The warning comes from the swift-build `stale-file-removal` task for the `mlx-swift_Cmlx` Metal resource bundle (see the research comment). `mlx-swift` is a transitive dependency: `FoundationModelsMetadataRegistry` -> `FoundationModelsRouter` -> `swissarmyhammer/mlx-swift-lm` (stable) -> `ml-explore/mlx-swift` `0.31.6` (newest tag). This package cannot change the pin, cannot remove the dependency, and must not patch `.build/checkouts`. A person must decide: report the bug to swift-build / mlx-swift, or change `mlx-swift-lm`'s pin when a fixed release exists.