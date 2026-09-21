---
comments:
- actor: claude-code
  id: 01m321txye3az5fcrsbjxc0str
  text: |-
    Research, before the first edit.

    Extras at cf4be5c gives what this card needs; the card is not stuck.

    - `FoundationModelsExtras.PathConfinement.isConfined(_:to:)` is public. It resolves the symbolic links of the longest prefix that exists, for the root and for the candidate alike, thus it already holds the `^2dzxvms` fix of the local copy.
    - `DotfolderStack.nearest(_:)` gives the URL of the copy in the highest layer that holds a path. Each lookup applies `isSafeRelativePath` and then `Layer.confines(_:)`, thus a path that leaves a layer root gives `nil`.
    - `DotfolderStack` gives no index of the winning layer. `SkillOverlay.resolve(_:)` thus asks one single-layer stack for each contributing directory, highest first, and gives the index of the first directory that answers. A stack opens no file when it is made, thus the loop costs one lookup for each directory.
    - The Extras stack gives the joined URL, not the symbolic-link-free URL. `SkillOverlay.entries()` already gives that form, thus `resolve(_:)` now agrees with it. `SkillOverlayTests` compares against the joined path, and `LayerFixtureSupport.resolvedPath(of:)` then has no caller and goes.
    - The Extras text check accepts a leading `~`, thus the well-formed check of this package stays: it refuses the empty path, a leading `/`, a leading `~` and a `..` component. It moves to `ResourcePathRules` in `ResourceSupport.swift`, with the denied text beside it.
    - `ListResource.swift` names `PathConfinement` in no line, thus it needs no change. The other three call sites change: `SkillOverlay.swift`, `ReadResource.swift`, `RunScript.swift`.
    - Order of the guards of `run script` must not move. Today the denied text comes after the `scripts/` check and before the grant check, and a script that is not there draws the executable-bit-and-shebang text after the grant check. Thus `run script` asks `confines(_:)` where it asked `resolve(_:)` before, and asks `resolve(_:)` after the grant check. A script that no layer holds draws the same text as a script that carries neither the bit nor a shebang.
  timestamp: 2026-09-21T13:17:40.686361+00:00
- actor: claude-code
  id: 01m32258byexfndpy8h6dy3t8w
  text: |-
    The TDD cycle, and the decisions of the implementation.

    RED, step one: the new `ResourcePathRulesTests` did not compile -- "cannot find 'ResourcePathRules' in scope". RED, step two: with `isWellFormedRelativePath` giving `true` and `deniedMessage` giving the empty text, and `SkillOverlay.confines(_:)` giving `false`, `swift test --filter 'ResourcePathRulesTests|SkillOverlayTests|ReadResourceTests'` gave 8 failures, each for the reason the card names: the 5 refused path shapes, the denied text, `resolve` of a path no directory holds, and `confines` of a well-formed path. GREEN: the real bodies made the run pass.

    Decisions:

    - `SkillOverlay.resolve(_:)` walks the directories highest first and asks one single-layer `DotfolderStack` for `nearest(_:)`. The stack gives no layer index, thus the index comes from the loop. Making a stack opens no file, and the count of directories of one skill is small.
    - The URL that `resolve(_:)` gives is now the joined URL, not the symbolic-link-free one. `entries()` already gave that form, thus the two agree now. `SkillOverlayTests` compares against the joined path, and `LayerFixtureSupport.resolvedPath(of:)` lost its last caller and is deleted.
    - `SkillOverlay.confines(_:)` is the new home of the two checks. It reads the highest contributing directory, as the card states.
    - `run script` keeps the order of its guards: the `scripts/` check, then `confines(_:)` for the denied text, then the grant, then `resolve(_:)`. A script that no layer holds draws `missingScriptMessage(path:)`, which `requirementMessage(path:unmet:)` builds from both direct-exec requirements -- word for word the text that a script which carries neither the execute bit nor a shebang drew before, thus no corrective text of this package changed.
    - `ReadResource` asks `unresolvedMessage(path:in:)`, which gives the unreadable text for a confined path and the denied text for a path that leaves the skill.
    - `ListResource.swift` needed no change: it names `PathConfinement` in no line.
    - The two tests of `ReadResourceTests` for a `..` path and for a symbolic link that leaves the skill passed before the change as well as after it. The card asks for them, and they guard the behaviour through the move; the new behaviour of `resolve(_:)` is what the two failing overlay tests hold.

    `swift build --build-tests`: exit 0, 0 warnings. `swift test`: 587 tests in 54 suites, 0 failures, 0 skipped. `Sources/` names `resolvingSymlinksInPath` and `standardizedFileURL` in no line.
  timestamp: 2026-09-21T13:23:19.038497+00:00
- actor: claude-code
  id: 01m3225dmdtt8g1pyvkv3xpdth
  text: |-
    ### implement — changed
    - evidence: 9 files — deleted Sources/FoundationModelsSkills/Resources/PathConfinement.swift and Tests/FoundationModelsSkillsTests/PathConfinementTests.swift; added Tests/FoundationModelsSkillsTests/ResourcePathRulesTests.swift; changed Sources/FoundationModelsSkills/Resources/{ResourceSupport,SkillOverlay,ReadResource,RunScript}.swift and Tests/FoundationModelsSkillsTests/{SkillOverlayTests,ReadResourceTests,LayerFixtureSupport}.swift. `swift build --build-tests` exit 0, 0 warnings. `swift test` exit 0, 587 tests in 54 suites, 0 failures, 0 skipped. Each acceptance item and each test item of the card is checked.
    - next: /review
  timestamp: 2026-09-21T13:23:24.429492+00:00
- actor: claude-code
  id: 01m322bq0t4eyq5xwycghty2av
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` (clean, after `swift package clean`) — build OK, 0 warnings. `swift test` — 587 tests in 54 suites, all passed, 0 failures, 0 skipped (root-only environment gates unchanged from before).
    - checks done:
      - No file under `Sources/FoundationModelsSkills/` names `resolvingSymlinksInPath` or `standardizedFileURL`.
      - `Resources/PathConfinement.swift` and `Tests/FoundationModelsSkillsTests/PathConfinementTests.swift` are gone.
      - Escape-case tests exist and assert exact denied-corrective text (able to fail):
        - `..` path: `ReadResourceTests.readResourceOnAPathThatWalksUpDrawsTheDeniedCorrective`, `RunScriptTests.pathGuardsFireInOrderUnderAFullGrant` (`scripts/../../outside.sh`), `RunScriptTests.hostPolicyGateFiresBeforeAnyIDOrPathResolution` (`../../etc/passwd`).
        - absolute path: `ResourcePathRulesTests.aPathThatIsNotWellFormedIsRefused` (`/etc/passwd` case, table test).
        - symbolic link out of the layer: `ReadResourceTests.readResourceOnASymbolicLinkThatLeavesTheSkillDrawsTheDeniedCorrective`.
      - `SkillOverlayTests`: `resolveDeniesAPathThatLeavesEachDirectory` and `resolveGivesNothingForAPathThatNoDirectoryHolds` both check the new `nil` contract.
    - next: ready for review.
  timestamp: 2026-09-21T13:26:50.650463+00:00
depends_on:
- 01M2X2J679TGA1ENB64G9JT4SQ
- 01M2XD7YJF87V9PF0EPSG5CF2N
position_column: doing
position_ordinal: '80'
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

- [x] `Resources/PathConfinement.swift` does not exist, and no file under `Sources/FoundationModelsSkills/` names `resolvingSymlinksInPath` or `standardizedFileURL`.
- [x] A path that leaves the skill through `..` gives the denied corrective for `read resource` and for `run script`.
- [x] A path that leaves the skill through a symbolic link gives the denied corrective.
- [x] A well-formed path that no layer holds gives the not-found corrective.
- [x] `run script` still uses the layer directory that gave the winning copy as its working directory.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/RunScriptTests.swift`: the confinement corrective case and the not-under-scripts case pass with no change of their expected texts.
- [x] `Tests/FoundationModelsSkillsTests/ReadResourceTests.swift`: a `..` path and a symbolic link that leaves the skill give the denied corrective; a missing file gives the not-found corrective.
- [x] `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift`: `resolve` gives `nil` for a path that no layer holds, and the index of the higher directory for a path that two layers hold.
- [x] `Tests/FoundationModelsSkillsTests/ResourcePathRulesTests.swift` (new, from the kept cases of `PathConfinementTests.swift`): the well-formed path check, as a table.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills
