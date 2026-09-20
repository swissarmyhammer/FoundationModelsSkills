---
depends_on:
- 01M2X2J679TGA1ENB64G9JT4SQ
- 01M2XD7YJF87V9PF0EPSG5CF2N
position_column: todo
position_ordinal: '9480'
title: 'Resources: take the confinement from Extras; delete the local PathConfinement'
---
## What

`Sources/FoundationModelsSkills/Resources/PathConfinement.swift` (155 lines) is a copy of the rule that `FoundationModelsExtras` holds: it calls `FileManager.fileExists`, `resolvingSymlinksInPath` and `standardizedFileURL` itself. The Extras stack applies that rule on each lookup, thus the copy must go. This card needs no new Extras API.

The `Marketplace/` folder of this package also calls the local type (`CatalogFileSource.swift`, `CatalogResolver.swift`). The card ^sg5cf2n deletes that folder first, thus this card depends on it.

1. **`SkillOverlay.resolve(_:)`** takes the winning copy from its stack (the skill directories are the layer roots of that stack, thus a path relative to the skill is a path relative to a layer root). It no longer calls `winningCopy(relativePath:in:)`.
2. **The contract of `resolve(_:)` for a path that no layer holds.** Today it gives the highest directory that confines the path, and the caller uses that to tell "not there" from "denied". New contract: `resolve(_:)` gives `nil` when no layer holds the path. It gives a directory index only for a copy that exists. The caller makes the difference with two checks that open no file in this package: the pure string check of a well-formed relative path, and `PathConfinement.isConfined(_:to:)` of Extras for the candidate URL under the highest contributing directory. A path that fails one of the two gives the denied corrective; a path that passes both and has no copy gives the not-found corrective.
3. **What stays here, as pure string functions in `ResourceSupport.swift`:** the check of a well-formed relative path (empty, a leading `/`, a leading `~`, a `..` component), and the text of the denied corrective.
4. **Delete `Resources/PathConfinement.swift`.** Caution: this module re-exports Extras, and the local `internal enum PathConfinement` wins the name today. When the local file goes, each call site binds to the Extras type, which has only `isConfined(_:to:)`. Change each call site in the same commit: `ReadResource.swift`, `ListResource.swift`, `RunScript.swift`, `SkillOverlay.swift`.
5. `Tests/FoundationModelsSkillsTests/PathConfinementTests.swift`: the cases of the symbolic link rule are covered in Extras; delete them here. Keep the cases of the well-formed path check and of the corrective texts, against their new home.

## Acceptance Criteria

- [ ] `Resources/PathConfinement.swift` does not exist, and no file under `Sources/FoundationModelsSkills/` names `resolvingSymlinksInPath` or `standardizedFileURL`.
- [ ] A path that leaves the skill through `..` gives the denied corrective for `read resource` and for `run script`.
- [ ] A path that leaves the skill through a symbolic link gives the denied corrective.
- [ ] A well-formed path that no layer holds gives the not-found corrective.
- [ ] `run script` still uses the layer directory that gave the winning copy as its working directory.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/RunScriptTests.swift`: the confinement corrective case and the not-under-scripts case pass with no change of their expected texts.
- [ ] `Tests/FoundationModelsSkillsTests/ReadResourceTests.swift`: a `..` path and a symbolic link that leaves the skill give the denied corrective; a missing file gives the not-found corrective.
- [ ] `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift`: `resolve` gives `nil` for a path that no layer holds, and the index of the higher directory for a path that two layers hold.
- [ ] `Tests/FoundationModelsSkillsTests/ResourcePathRulesTests.swift` (new, from the kept cases of `PathConfinementTests.swift`): the well-formed path check, as a table.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills
