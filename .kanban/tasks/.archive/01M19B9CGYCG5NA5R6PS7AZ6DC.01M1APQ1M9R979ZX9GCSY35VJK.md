---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19fzaf48hw67m1ttqkpk0dk
  text: |-
    ### finish — out of scope, tagged blocked-upstream

    Two reasons this card is held out of the current batch.

    1. **It edits a sibling repository.** Every step is in `FoundationModelsRouter/Package.swift`. The plan for this board is explicitly "verify only, do not edit siblings". A human must decide to do this work in that repository.

    2. **`^02wba0s` probably makes it moot.** The whole reason `mlx-swift-lm` is in this package's graph is the Router branch. Once `FoundationModelsMetadataRegistry` drops its five unused dependency entries, `mlx-swift-lm` leaves the graph of `FoundationModelsSkills` completely, and there is no identity for two mirrors to compete over here.

    Do `^02wba0s` first. Then check whether this card still describes a real problem for this package. It may still matter for `FoundationModelsRouter`'s own consumers, which is a decision for that repository.

    The work-around stays available meanwhile: stop `sourcekit-lsp`, delete `.build/checkouts/mlx-swift-lm`, build, resume.
  timestamp: 2026-08-30T14:08:02.020486+00:00
- actor: claude-code
  id: 01m1apq112bzhj4t5zv8r608g0
  text: |-
    ### moot — the premise no longer holds. Archiving.

    This card said: "Two sibling packages declare the same SwiftPM package identity `mlx-swift-lm` with two different URLs." That is no longer true. Checked on 2026-08-30, after `^02wba0s`:

    - `git show origin/main:Package.swift` in `FoundationModelsMetadataRegistry` declares **no** mlx package at all. Its whole `dependencies:` list is one entry, `FoundationModelsRanker`.
    - `FoundationModelsRouter` is now the only declarer of `mlx-swift-lm`. One declarer cannot disagree with itself, thus there is no identity to give two URLs, and no reason for SwiftPM to keep two mirrors.
    - `grep -c mlx Package.resolved` in this package gives 0. `mlx-swift-lm` left this package's graph completely when the Router branch went.
    - `.build/repositories` holds no `mlx-swift-lm` mirror.

    The `sourcekit-lsp` race that made this card is also out of reach for this package: `swift package update` here no longer removes a multi-gigabyte mlx checkout, because there is none.

    **Nothing is left to do in this repository.** Whether `FoundationModelsRouter` prefers `https://` or `git@` for its own `mlx-swift-lm` pin is that repository's decision, and it is now a style question, not a conflict.

    Archived rather than deleted, thus the measurement that made the card stays findable if two declarers ever appear again.
  timestamp: 2026-08-31T01:25:04.674071+00:00
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
- [ ] `swift test` passes in `FoundationModelsRouter` and `FoundationModelsMetadataRegistry`. #blocked-upstream