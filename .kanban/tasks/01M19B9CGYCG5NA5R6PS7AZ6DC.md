---
assignees:
- claude-code
position_column: todo
position_ordinal: 8a80
title: Align the mlx-swift-lm dependency URL across Router and MetadataRegistry
---
## What

Two sibling packages declare the same SwiftPM package identity `mlx-swift-lm` with two different URLs:

- `FoundationModelsRouter/Package.swift:107` uses `https://github.com/swissarmyhammer/mlx-swift-lm`
- `FoundationModelsMetadataRegistry/Package.swift:212` uses `git@github.com:swissarmyhammer/mlx-swift-lm.git`

SwiftPM maps both URLs to one identity. It therefore keeps two mirror repositories in `.build/repositories` (`mlx-swift-lm-46294311` and `mlx-swift-lm-56690f82`) and it can remove and clone the `.build/checkouts/mlx-swift-lm` working copy again on a later resolution.

### Why this is a problem

Found while ^avyccbj bumped the sibling packages. `swift build` stopped with:

```
error: 'mlx-swift-lm': Error Domain=NSCocoaErrorDomain Code=513
"mlx-swift-lm couldn't be removed because you don't have permission to access it."
```

The cause is a race, not a permission: `sourcekit-lsp` starts a background index build
(`swift-build --package-path .../checkouts/mlx-swift-lm ... --experimental-prepare-for-indexing`)
that writes into the checkout while SwiftPM tries to remove it. The removal then fails with `EPERM`.

The work-around used in ^avyccbj was to stop `sourcekit-lsp`, delete the checkout, and build again. That is a manual step, and the condition comes back.

### Steps

1. Choose one URL form for `mlx-swift-lm` -- match the family convention (`git@github.com:swissarmyhammer/`).
2. Change `FoundationModelsRouter/Package.swift` to use that form.
3. Confirm `FoundationModelsMetadataRegistry` already uses it.
4. In a clean clone of `FoundationModelsSkills`, run `swift package resolve` and confirm `.build/repositories` holds exactly one `mlx-swift-lm-*` mirror.

Both files are in sibling repositories, not in `FoundationModelsSkills`. Do the work in those repositories.

## Acceptance Criteria

- [ ] `FoundationModelsRouter` and `FoundationModelsMetadataRegistry` declare `mlx-swift-lm` with the same URL.
- [ ] A clean resolve of `FoundationModelsSkills` makes one `mlx-swift-lm-*` mirror directory, not two.
- [ ] Two `swift build` runs in a row do not clone the `mlx-swift-lm` checkout again.

## Tests

- [ ] `swift build` and `swift test` pass in `FoundationModelsSkills` after the change.
- [ ] `swift test` passes in `FoundationModelsRouter` and `FoundationModelsMetadataRegistry`.