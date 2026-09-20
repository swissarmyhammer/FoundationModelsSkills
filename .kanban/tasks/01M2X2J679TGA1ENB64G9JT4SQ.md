---
depends_on:
- 01M2X2HX820957M3JE41JKNJ0E
- 01M2X2J1KXF8CGFNFY9XHB2S4D
position_column: todo
position_ordinal: '8380'
title: list resource and read resource over the combined view
---
## What

`list resource` and `read resource` see one directory only, and each one does its own raw file work. `run script` already uses `SkillOverlay`, so the three operations do not agree today. They must see the combined view of the skill, and they must get it from the Extras stack.

The boundary rule (the user, 2026-09-20): the raw work of loading lives in `FoundationModelsExtras` (the file system, the layers, Stencil, the frontmatter split). This package keeps only the work of the skill schema. Thus this card adds **no** new `FileManager`, `FileHandle` or `URL.resourceValues` call, and it removes the ones named below.

1. `ListResource` (`Sources/FoundationModelsSkills/Resources/ListResource.swift`) stops its own recursive `contentsOfDirectory` walk. It takes the union of the paths from `SkillOverlay.entries()`, which reads `DotfolderStack.urls()`. One row for each path, with the winning copy. A path that two layers hold gives one row. The hidden-file rule, the `SKILL.md` exclusion, the kind by top-level folder, the order, the row cap and the visibility rule do not change; apply them to the path strings. The byte count of a row comes from `size(of:)` of the stack.
2. `ReadResource` (`Sources/FoundationModelsSkills/Resources/ReadResource.swift`) reads the winning copy through the stack. `LineWindowScanner` stops its `FileHandle`: it reads chunks with `data(_:in:)` of the stack, and the size for the non-UTF-8 corrective comes from `size(of:)`. The line window, the byte budget, the incremental UTF-8 check and the correctives are the contract of this operation, thus they stay here and do not change.
3. `SkillOverlay` gives the stack (or the two reads) to the operations, so no operation builds a URL of its own. `ResourceSupport` (`Sources/FoundationModelsSkills/Resources/ResourceSupport.swift`) gives the overlay to all three operations; `withResolvedDirectory` goes away.
4. One call stays for the next card: the `executable` column of a row still needs the execute bit, and the stack cannot give it yet (card `^00nmjzg` on the `FoundationModelsExtras` board; the card after this one on this board takes it up). Keep the one `resourceValues(forKeys: [.isExecutableKey])` call for it, in one private function, with a comment that names that card.

## Acceptance Criteria

- [ ] `list resource` shows a file that only a lower layer holds.
- [ ] `list resource` shows one row for a path that two layers hold, and the row names the higher copy.
- [ ] `list resource` shows a file whose bytes are not UTF-8 text, with its size.
- [ ] `read resource` gives the text of the higher copy for a path that two layers hold.
- [ ] `read resource` gives the text of the lower copy for a path that only the lower layer holds.
- [ ] `ListResource.swift` has no `contentsOfDirectory` call, and `ReadResource.swift` has no `FileHandle` and no `resourceValues` call.
- [ ] A skill with one layer directory behaves exactly as before: the paging, the caps and each corrective text.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift`: the fixture of the example (`defaults` holds `scripts/report.sh` and `references/rules.md`; `user` holds `scripts/lint.sh`; `project` holds `references/house-style.md`) gives all four paths in `list resource`, each one time.
- [ ] Same file: `read resource` of `scripts/lint.sh` gives the text of the user layer.
- [ ] Same file: `read resource` of `scripts/report.sh` gives the text of the defaults layer.
- [ ] Same file: a PNG under `assets/` is one row of `list resource`, with the kind `asset`.
- [ ] `Tests/FoundationModelsSkillsTests/ReadResourceTests.swift`: the paging cases, the byte budget case and the non-UTF-8 case pass with no change of their expected values.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#dotfolder-overlay #skills #loading-boundary