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
- actor: claude-code
  id: 01m2zd29mgxqvahtetb4sze5ts
  text: 'Unblocked on 2026-09-20. The Extras card ^0gbdkmg is done: commit 01e2ed1 "feat(dotfolder-stack): add a URL view of the winning copies" is on Extras main, and Package.resolved here pins 1c150fb, which holds it. Step 3 can start now: point SkillOverlay.entries() at the URL view, and add the non-UTF-8 test. No package update is necessary.'
  timestamp: 2026-09-20T12:36:13.072369+00:00
- actor: claude-code
  id: 01m2zd37rwrt1paybpy938q73w
  text: |-
    ### Research — the block is gone

    `Package.resolved` now pins `FoundationModelsExtras` at `1c150fb` on branch `main`, and that revision holds the view card `^0gbdkmg` asked for.

    Read at `.build/checkouts/FoundationModelsExtras/Sources/FoundationModelsExtras/`:

    - `DotfolderStacking.swift` declares `func urls(_ subdirectory: String?) -> [String: Located<URL>]` as a requirement of the protocol, beside `tree(_:)`. Its documentation states that the view applies the same override rule as `tree(_:)` and holds every file, because the stack reads no file to make it.
    - `DotfolderStack.swift` gives `public func urls(_ subdirectory: String? = nil) -> [String: Located<URL>]`, which is `winningCopies(in:).mapValues { Located(url: $0.url, layer: $0.layer, value: $0.url) }`. The URL is both the `url` and the `value` of each entry, thus `mapValues(\.url)` still reads the copy.
    - `FrontmatterDocumentStack` and `StenciledDotfolderStack` each forward `urls(_:)` to the base stack.

    Thus `SkillOverlay.entries()` moves from `tree().mapValues(\.url)` to `urls().mapValues(\.url)`, and this package still walks no directory of its own.

    `entries()` has one call site in `Sources/` — none. The three tests in `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift` are its only callers today, thus the change of the view breaks no caller.
  timestamp: 2026-09-20T12:36:43.932701+00:00
- actor: claude-code
  id: 01m2zd8rkq7xqyyzxw59fn954k
  text: |-
    ### implement — changed

    - evidence: 3 files — `Sources/FoundationModelsSkills/Resources/SkillOverlay.swift` (`entries()` reads `urls()` in place of `tree()`, and the documentation states that a file of bytes is in the view), `Tests/FoundationModelsSkillsTests/LayerFixtureSupport.swift` (new `writeBytesFile(at:in:)`, which writes the eight bytes of a PNG signature, and the shared private `preparedFileURL(at:in:)` that both writers call, thus the two writers hold no copy of the same lines), `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift` (new test `entriesGiveAFileWhoseBytesAreNotText`, the fixture writes `assets/logo.png` in the lowest directory, and the union test names that path too).
    - red first: `swift test --filter SkillOverlayTests` before the change of `entries()` — 2 of 7 tests failed. `entries[Self.bytesOnlyPath]?.path` was `nil`, and `Set(entries.keys)` held the three text paths only. That is the report of the card, reproduced.
    - green: `swift test --filter SkillOverlayTests` — 7 of 7 passed. `swift build --build-tests` — 0 warnings, 0 errors. `swift test` — 788 tests in 64 suites passed. `check working` diagnostics — 0 errors, 0 warnings.
    - discovery: the two writers of `LayerFixtureSupport` shared the two lines that make the URL and the directories above it. The new writer takes that shape from one private helper, thus the file holds one copy of it.
    - next: `/review`. This card unblocks `^g9jt4sq` (`list resource` and `read resource` over the combined view), which needs a row for a file of bytes.
  timestamp: 2026-09-20T12:39:45.015865+00:00
- actor: claude-code
  id: 01m2zdcmymx1bmn4jrkgv8tnv3
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` — build complete, 0 warnings, 0 errors. `swift test` — 788 tests in 64 suites, all passed, 0 failed, 0 skipped.
    - evidence: `swift build --build-tests` re-run after touching the changed files (SkillOverlay.swift, LayerFixtureSupport.swift, SkillOverlayTests.swift) — build complete, 0 warnings.
    - evidence: LSP diagnostics check on working changes — 0 errors, 0 warnings.
    - No config file for swiftformat, swift-format, or swiftlint is in the repo. No skipped or ignored tests are in the suite.
  timestamp: 2026-09-20T12:41:52.340922+00:00
position_column: doing
position_ordinal: '80'
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

## The Extras API landed

Card `^0gbdkmg` on the `FoundationModelsExtras` board is done. `Package.resolved` pins `FoundationModelsExtras` at `1c150fb` on branch `main`, and that revision declares `urls(_ subdirectory: String?) -> [String: Located<URL>]` on `DotfolderStacking`, which names every file and reads no text. `DotfolderStack` builds the view from `winningCopies(in:)`, thus it applies the same override rule as `tree(_:)`, and the URL is both the `url` and the `value` of each entry.

Thus step 3 is done: `entries()` is `DotfolderStack(layers: layers).urls().mapValues(\.url)`.

## Acceptance Criteria

- [x] `entries()` gives each file of the union, whether or not its bytes are text.
- [x] `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift`: a file of bytes that are not UTF-8 is in `entries()`, with the copy of its own directory.
- [x] No type in this package walks the layer directories itself.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

#dotfolder-overlay #skills #cross-repo