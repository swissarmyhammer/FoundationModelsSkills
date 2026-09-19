---
assignees:
- claude-code
position_column: todo
position_ordinal: '9380'
title: SkillOverlay.entries leaves out a file that is not UTF-8 text
---
## What

`SkillOverlay.entries()` (`Sources/FoundationModelsSkills/Resources/SkillOverlay.swift`) reads `DotfolderStack.tree(_:)`, as card ^xhb2s4d ordered. The value of `tree` is `Located<String>`: the **text** of the winning copy. `DotfolderStack.winningTexts(of:)` drops a copy that `String(contentsOf:encoding:.utf8)` cannot read.

Thus `entries()` leaves out each file of a skill whose bytes are not UTF-8 text — for example a PNG under `assets/`, or a compiled helper under `scripts/`.

`list resource` must give such a file: its `kind` is `asset`, and the listing states the size in bytes. The operation gives no text, thus the text is of no use to it.

## The work

1. Read the current `FoundationModelsExtras` main. A view that gives the URL of the winning copy, with no text read, is the correct API — for example `urls(_ subdirectory: String?) -> [String: Located<URL>]`, beside `tree(_:)`.
2. If Extras has no such API, make a card on the Extras board first. Do **not** write a walk of the directories in this package (card ^cw1z0q7 and the §3 rule).
3. Point `entries()` at the new API, and add a test: a file whose bytes are not UTF-8 is in `entries()`.

## Acceptance Criteria

- [ ] `entries()` gives each file of the union, whether or not its bytes are text.
- [ ] `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift`: a file of bytes that are not UTF-8 is in `entries()`, with the copy of its own directory.
- [ ] No type in this package walks the layer directories itself.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

#dotfolder-overlay #skills #cross-repo