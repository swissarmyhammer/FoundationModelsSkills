---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'Build warning from the mlx-swift dependency: "missing creator for mutated node" on mlx-swift_Cmlx.bundle/Contents/MacOS'
---
## What
Each `swift build --build-tests` and `swift test` in this package prints one build-system warning:

`warning: missing creator for mutated node: ('.build/out/Products/Debug/mlx-swift_Cmlx.bundle/Contents/MacOS')`

The warning comes from the `Cmlx` target of the `mlx-swift` dependency, not from a source file in this package. It reproduces with the working tree stashed (found while `^w5mjseg` was in test), and after a full delete of `.build/out`. A clean build of that target also prints four `-Wc++17-extensions` warnings from `Source/Cmlx/mlx-generated/metal/steel/attn/kernels/steel_attention.h`.

## Acceptance Criteria
- [ ] Find the cause in the `mlx-swift` package manifest (the `Cmlx` resource bundle or its build plugin) and record it on this card
- [ ] Remove the warning: an upstream fix in `mlx-swift`, or a pinned revision that does not print it
- [ ] `swift build --build-tests` prints zero warnings

## Tests
- [ ] `swift test` — exit 0, zero warnings