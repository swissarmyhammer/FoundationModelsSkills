---
comments:
- actor: wballard
  id: 01m2zeeadcnpfwdtdpgzgbwzwk
  text: 'The text of this card changed on 2026-09-20 while it was in Doing. Read it again. Three rules were added to step 1, because DotfolderStack.urls() gives hidden paths and does not go into a symbolic link to a directory: (1) leave out a path with any component that begins with a dot; (2) leave out a path for which size(of:) gives nil, which covers a dangling link; (3) a file under a symbolic link to a directory is not listed any more, as a decided change. Step 4 keeps one resourceValues call for the execute bit; the execute bit card of this board removes it after the Extras card ^00nmjzg lands.'
  timestamp: 2026-09-20T13:00:15.660698+00:00
- actor: claude-code
  id: 01m2zemq6y4nnbydcazhnfks81
  text: |-
    Picked up. Research of the code before the first edit:

    - `SkillOverlay` (`Sources/FoundationModelsSkills/Resources/SkillOverlay.swift`) gives `resolve(_:)` (winning copy + directory index, through `PathConfinement`) and `entries()` (the union of the paths, through `DotfolderStack.urls()`). It gives no size and no bytes yet, thus this card adds `size(of:)` and `data(_:in:)` that pass through to the same stack.
    - `DotfolderStack` of `FoundationModelsExtras` gives `urls(_:)`, `size(of:)` and `data(_:in:)`. The walk of `urls(_:)` skips no name ("which names to ignore is the policy of the consumer"), thus `ListResource` keeps the hidden-file rule and applies it to the path strings. The walk drops a file that resolves outside its own layer root, thus the escaping-symlink row goes away on its own.
    - `ReadResource` must keep the confinement check of its `path` parameter, because the corrective for `../x` and for an escaping symlink is "not accessible", and the stack alone would give "could not be read". `overlay.resolve(path)` gives that check.
    - The unreadable correctives stay the same through the stack: a missing file, a dangling link and a file with no read permission each give `size(of:) == nil`.

    Tests first (TDD): the three-layer example of the card, the shared path of two directories, and the file of bytes under `assets/`.
  timestamp: 2026-09-20T13:03:45.374410+00:00
- actor: claude-code
  id: 01m2zf4x4swrp1jdxrjask9wfa
  text: |-
    What the work did, in order:

    1. Tests first. `ResourceOpsTests` got a combined-view section: the three-layer example of the card, a two-layer fixture that gives one path to each directory with copies of different length, and a PNG under `assets/`. Five of the six new tests were red before the code changed; the sixth (`read resource` of a file that only the lowest directory holds) was green already, because the lowest directory gives the `SKILL.md` and thus was the one directory the old code read.
    2. `SkillOverlay` got `size(of:)` and `data(_:in:)`, which pass through to the same `DotfolderStack` that `entries()` reads.
    3. `ListResource` takes its rows from `entries()`, the byte count from `size(of:)`, and applies the hidden-file rule and the `SKILL.md` exclusion to the path strings. The recursive `contentsOfDirectory` walk is gone.
    4. `ReadResource` checks the confinement of its `path` with `overlay.resolve(path)`, reads the size with `size(of:)`, and the scanner reads its chunks with `data(_:in: offset..<offset + chunkByteSize)`. `FileHandle` and `resourceValues` are gone from the file.
    5. `ResourceSupport`: `withResolvedDirectory` is gone, as the card states. With it the `Resolution` enum and `resolve(id:context:)` went, because nothing read them after the change; `withResolvedOverlay` now guards with a private `isUsable(id:context:)` that makes the same two checks (the visibility predicate, and a directory in the registry).

    Two notes for the next agent:

    - The one `resourceValues(forKeys: [.isExecutableKey])` call stays in `ListResource.isExecutable(at:)`, with a comment that names card `^00nmjzg` of the `FoundationModelsExtras` board and card `^yraq5xe` of this board.
    - `LayerFixtureSupport` got `writeTextFile(_:at:in:)`, which takes the text. The shared-path test needs two copies of different length, and the text of `writeTextFile(at:in:)` names the directory, thus the two copies of that form always hold the same count of bytes.
  timestamp: 2026-09-20T13:12:35.737799+00:00
- actor: claude-code
  id: 01m2zf51aq4awwq2et7kj0tj4n
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsSkills/Resources/ListResource.swift, Sources/FoundationModelsSkills/Resources/ReadResource.swift, Sources/FoundationModelsSkills/Resources/ResourceSupport.swift, Sources/FoundationModelsSkills/Resources/SkillOverlay.swift, Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift, Tests/FoundationModelsSkillsTests/LayerFixtureSupport.swift. `swift build --build-tests`: 0 warnings. `swift test`: 794 tests in 64 suites, 0 failures. Six new tests; five of them were red before the code changed.
    - next: review
  timestamp: 2026-09-20T13:12:40.023286+00:00
- actor: claude-code
  id: 01m2zfaz6pfx3p3szk82z98vkf
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` (clean, after `rm -rf .build`) — build complete, 0 warnings; `swift test` — 794 tests in 64 suites passed, 0 failed, 0 skipped
    - next: ready for review
  timestamp: 2026-09-20T13:15:54.454249+00:00
depends_on:
- 01M2X2HX820957M3JE41JKNJ0E
- 01M2X2J1KXF8CGFNFY9XHB2S4D
position_column: doing
position_ordinal: '80'
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

- [x] `list resource` shows a file that only a lower layer holds.
- [x] `list resource` shows one row for a path that two layers hold, and the row names the higher copy.
- [x] `list resource` shows a file whose bytes are not UTF-8 text, with its size.
- [x] `read resource` gives the text of the higher copy for a path that two layers hold.
- [x] `read resource` gives the text of the lower copy for a path that only the lower layer holds.
- [x] `ListResource.swift` has no `contentsOfDirectory` call, and `ReadResource.swift` has no `FileHandle` and no `resourceValues` call.
- [x] A skill with one layer directory behaves exactly as before: the paging, the caps and each corrective text.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift`: the fixture of the example (`defaults` holds `scripts/report.sh` and `references/rules.md`; `user` holds `scripts/lint.sh`; `project` holds `references/house-style.md`) gives all four paths in `list resource`, each one time.
- [x] Same file: `read resource` of `scripts/lint.sh` gives the text of the user layer.
- [x] Same file: `read resource` of `scripts/report.sh` gives the text of the defaults layer.
- [x] Same file: a PNG under `assets/` is one row of `list resource`, with the kind `asset`.
- [x] `Tests/FoundationModelsSkillsTests/ReadResourceTests.swift`: the paging cases, the byte budget case and the non-UTF-8 case pass with no change of their expected values.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#dotfolder-overlay #skills #loading-boundary