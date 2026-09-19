---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2xr1kzt21gn463bb9matkzd
  text: |-
    ### Research

    Read `FoundationModelsExtras` at the pinned revision `2123cdf`, which is the head of `origin/main` today, in `.build/checkouts/FoundationModelsExtras/Sources/FoundationModelsExtras/`.

    The cause of the report is exact. `DotfolderStack.tree(_:)` builds its entries with `winningTexts(of:)`, which applies the override rule and then calls `compactMapValues(locatedText)`. `locatedText` reads `String(contentsOf:encoding:.utf8)` and gives `nil` for bytes that are not UTF-8. Thus `SkillOverlay.entries()`, which is `tree().mapValues(\.url)`, loses each such file.

    The public API of the stack today:

    - Text views: `tree(_:)`, `enumerate(_:suffix:)`, `items(in:named:)`, `item(at:)`, `content(_:)`. Each one applies the same UTF-8 rule.
    - Directory views: `childDirectories(of:)` gives the names of the child directories only, and `layerDirectories(_:)` gives the layers that hold one directory. Neither one names a file.
    - One-path readers: `data(_:)`, `data(_:in:)`, `size(of:)`, `exists(_:)`, `nearest(_:)`, `locate(_:)`. Each one takes a path that the caller already knows.

    Thus there is **no** view that gives the URL of the winning copy of each file. The union of the file paths cannot be built from the API that exists. `data(_:)` and `size(of:)` answer for a path that is already known, thus they serve `read resource` and the size of a row, but they cannot make the row list.

    `DotfolderStacking` is the protocol over the three stacks (`DotfolderStack`, `FrontmatterDocumentStack`, `StenciledDotfolderStack`). `data`, `size(of:)` and `exists` are already requirements there, and the two layered stacks forward each one to the base. A `urls(_:)` requirement follows that same shape.

    `entries()` has no caller in `Sources/` yet; card ^g9jt4sq puts `list resource` on it. The three tests in `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift` are the only callers today.

    Step 2 of the card applies: Extras has no such API, thus this pass makes the Extras card and writes no directory walk in this package (card ^cw1z0q7 and the §3 rule).
  timestamp: 2026-09-19T21:09:36.378953+00:00
- actor: claude-code
  id: 01m2xr23pcsj33195w1d57xx4p
  text: |-
    ### implement — stuck

    - evidence: 0 source files changed in this package. Step 1 of the card is done (`FoundationModelsExtras` at the pinned revision `2123cdf` holds no view that gives the URL of the winning copy). Step 2 of the card is done: card `^0gbdkmg` is on the `FoundationModelsExtras` board, column `todo`, tags `dotfolder-overlay` and `cross-repo`, with the full specification of `urls(_ subdirectory: String? = nil) -> [String: Located<URL>]`. Step 3 cannot start: the API does not exist, and the card forbids a walk of the directories in this package (card ^cw1z0q7 and the §3 rule). The 4 acceptance items stay unchecked.
    - blocker: this package reads `FoundationModelsExtras` as a remote dependency on the branch `main`, thus `entries()` can call the new view only after card `^0gbdkmg` lands on that branch and `Package.resolved` pins the new revision. The local `FoundationModelsExtras` clone is 7 commits in front of `origin/main` and holds modified board files, thus another session works that repository now; this session writes nothing there but the new card.
    - next: work card `^0gbdkmg` on the `FoundationModelsExtras` board, push `main`, then start this card again. This card blocks `^g9jt4sq`.
  timestamp: 2026-09-19T21:09:52.460756+00:00
- actor: wballard
  id: 01m2xr3659eea8dkfywbc6kc0z
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — the Extras stack gives no view of the winning URLs, thus entries() cannot show a file of bytes
    - test: not run
    - commit: none
    - review: not run
    - next: the Extras card ^0gbdkmg must land first; then bump the dependency and finish this card. It blocks ^g9jt4sq.
  timestamp: 2026-09-19T21:10:27.753448+00:00
position_column: todo
position_ordinal: '9580'
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

## Blocked on the Extras API

Step 1 is done. `FoundationModelsExtras` main (`2123cdf`, the pinned revision) holds **no** view that gives the URL of the winning copy. `tree(_:)`, `enumerate(_:suffix:)` and `items(in:named:)` each give text, `childDirectories(of:)` and `layerDirectories(_:)` give directories only, and `data(_:)`, `size(of:)` and `exists(_:)` each take one known path. Thus this package cannot build the union of the file paths from the API that exists today.

Step 2 is done. Card `^0gbdkmg` on the `FoundationModelsExtras` board — "Give the dotfolder stack a view of the winning URLs, with no text read" — carries the full specification of `urls(_ subdirectory: String? = nil) -> [String: Located<URL>]`.

Step 3 waits for that card. The work in this package starts again when the Extras card lands on `main` and `Package.resolved` pins the new revision.

## Acceptance Criteria

- [ ] `entries()` gives each file of the union, whether or not its bytes are text.
- [ ] `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift`: a file of bytes that are not UTF-8 is in `entries()`, with the copy of its own directory.
- [ ] No type in this package walks the layer directories itself.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

#dotfolder-overlay #skills #cross-repo