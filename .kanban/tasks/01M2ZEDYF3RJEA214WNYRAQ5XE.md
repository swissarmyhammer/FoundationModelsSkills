---
comments:
- actor: claude-code
  id: 01m323kk497f5h3asnfgthf1dj
  text: |-
    Picked up the card and made the research.

    Step 1 of the card, the check of the upstream: `Package.resolved` of this package pins `FoundationModelsExtras` at `cf4be5c`. The checkout at `.build/checkouts/FoundationModelsExtras` holds `func isExecutable(_ relativePath: String) -> Bool` as a requirement of `DotfolderStacking` and as a member of `DotfolderStack`, `FrontmatterDocumentStack` and `StenciledDotfolderStack`. `DotfolderStack.isExecutable(_:)` reads the copy that `nearest(_:)` gives, thus it answers for the winning copy of the combined view. The card is not blocked.

    The public surface gives all that the card needs:
    - the execute bit: `isExecutable(_:)`.
    - the first bytes: `data(_:in:)`, which seeks to the lower bound and reads `range.count` bytes. A file that is shorter gives fewer bytes, and an unreadable file gives `nil`. Thus a comparison with the two bytes `#!` keeps the answer of `FileHandle.readData(ofLength:)`.

    The plan of the change:
    1. `SkillOverlay` gains `isExecutable(_:)`, which asks the one stack over every layer directory, beside `size(of:)` and `data(_:in:)`.
    2. `ListResource.resourceRows(in:)` takes the `executable` column from `overlay.isExecutable(path)`, and `ListResource.isExecutable(at:)` goes away.
    3. `RunScript.executabilityIssue(path:at:)` becomes `executabilityIssue(path:in:)` over the overlay, and `hasShebang(at:)` becomes `hasShebang(of:in:)` over `data(_:in: 0..<2)`.
    Every corrective text stays as it is.

    The rules that a review applies: read the dump of the validators for a Swift file. The rule bodies of `code-hygiene` (data-driven, dead-code, function-length, magic-numbers, missing-docs, no-commented-code), `duplication` with its Swift carve-outs, `reuse`, `swift` (each of the 13 guideline files), `completeness`, `code-security` and `test-integrity` were read whole. The tool-gate sections for Dart, Go, Python, Rust and TypeScript were not read, because no file of the change is in those languages.
  timestamp: 2026-09-21T13:48:37.385609+00:00
- actor: claude-code
  id: 01m323xwgkxa3bw90b3vcpv6n8
  text: |-
    The work landed. The order of the steps was the TDD order:

    1. Wrote the tests first. `SkillOverlayTests` asks `isExecutable(_:)` of the overlay, which did not compile -- the red of step 1. `NoResourceFileReadTests` walks `Sources/FoundationModelsSkills/Resources` and failed on the three reads that were there -- the red of the two operations. The two new cases of `ResourceOpsTests` hold the `executable` column to the copy of the winning layer; they are the record of the behaviour across the change, thus they passed before the change as well. The two cases of `RunScriptTests` for the missing execute bit and the missing shebang kept their texts.
    2. `SkillOverlay.isExecutable(_:)` asks the one stack over every layer directory, beside `size(of:)` and `data(_:in:)`.
    3. `ListResource.resourceRows(in:)` reads the paths of `entries()` and asks the overlay for the execute bit; `ListResource.isExecutable(at:)` is gone. A row now takes each column that reads the disk from the overlay.
    4. `RunScript.executabilityIssue(path:in:)` reads a small table of the two requirements, thus no accumulator grows through the checks. `RunScript.hasShebang(of:in:)` compares the first two bytes of `data(_:in:)` with the prefix. The offset of the first byte is a named constant.

    What to know for the next card:
    - `DotfolderStack.isExecutable(_:)` answers for the copy that `nearest(_:)` gives, which is the copy of the highest layer that holds the path. Thus the answer of a row, of the `chmod +x` gate and of the run itself is one and the same copy. Before the change, the two operations read the URL of the winning copy themselves, thus the behaviour is the same and no corrective text moved.
    - `data(_:in: 0..<2)` gives fewer bytes for a file that is shorter, and nothing for a file that cannot be read. Neither one matches the prefix, thus the answer of the old `FileHandle` read stands.
    - `LayerFixtureSupport.makeExecutable(_:)` is the one writer of the execute bit of a fixture now; `ResourceTestSupport.writeExecutableShebangScript` calls it instead of setting the attributes itself.
    - `NoResourceFileReadTests` guards the whole `Resources` directory, not only the two files of this card. The card `^q3x4bx` widens the same guard to the package.

    ### implement — changed
    - evidence: 8 files -- Sources/FoundationModelsSkills/Resources/{ListResource,RunScript,SkillOverlay}.swift, Tests/FoundationModelsSkillsTests/{NoResourceFileReadTests (new),SkillOverlayTests,ResourceOpsTests,LayerFixtureSupport,ResourceTestSupport}.swift. `swift build --build-tests`: 0 errors, 0 warnings. `swift test`: 594 tests in 55 suites, 0 failures.
    - next: /review
  timestamp: 2026-09-21T13:54:14.675772+00:00
- actor: claude-code
  id: 01m3243zbwezgvz59d6y86m2wj
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` (clean, after `rm -rf .build`) — 0 warnings, build complete. `swift test` — 594 tests, 55 suites, 0 failures, 0 skipped.
    - checked: `ListResource.swift` and `RunScript.swift` have no `FileManager`, no `FileHandle`, no `resourceValues`.
    - next: ready for review.
  timestamp: 2026-09-21T13:57:34.204532+00:00
depends_on:
- 01M2X2J679TGA1ENB64G9JT4SQ
position_column: doing
position_ordinal: '80'
title: 'Resources: take the execute bit and the shebang bytes from the Extras stack'
---
## What

**Status on 2026-09-20: not blocked.** The Extras card `^00nmjzg` is done and pushed (commit `62bf1aa`): `isExecutable(_:)` is a requirement of `DotfolderStacking`, and all three stacks answer it. The build of this package is green with the shim in place and the public `DotfolderStack.init(layers:)` of Extras resolved at the same time: the compiler prefers the initializer of this module, and reports no ambiguity. Thus the shim card is a plain cleanup, and this card does not wait for it. `Package.resolved` of this package pins the Extras revision `cf4be5c`, which is `origin/main` of `FoundationModelsExtras` (checked on 2026-09-20; `swift build` of this package is green against it). The check of step 1 passes now; run it only to confirm the pin.

After the card ^g9jt4sq, the resource operations still make three raw file calls: the execute bit of a `list resource` row, the `chmod +x` gate of `run script`, and the two-byte shebang read of `run script`. This card needs the Extras card `^00nmjzg` on the `FoundationModelsExtras` board, which adds `isExecutable(_:)` to the stack.

1. **Check the upstream first.** Run `swift package update FoundationModelsExtras`. If the resolved revision has no `isExecutable` requirement on `DotfolderStacking`, stop, write a comment on this card, and leave it in To Do.
2. **The execute bit of a row.** `ListResource` (`Sources/FoundationModelsSkills/Resources/ListResource.swift`) takes the `executable` column from `isExecutable(_:)` of the overlay stack. Delete the one `resourceValues(forKeys:)` call that the card ^g9jt4sq left for it.
3. **The `chmod +x` gate.** `RunScript.executabilityIssue` (`Sources/FoundationModelsSkills/Resources/RunScript.swift`) takes its answer from the same call. Delete `FileManager.default.isExecutableFile`.
4. **The shebang.** `RunScript.hasShebang` reads two bytes with `FileHandle`. Read them with `data(_:in: 0..<2)` of the overlay stack.

## Acceptance Criteria

- [x] `ListResource.swift` and `RunScript.swift` name no `FileManager`, no `FileHandle` and no `resourceValues`.
- [x] `list resource` gives the same `executable` value as before for a `0755` file and for a `0644` file.
- [x] `run script` gives the same `chmod +x` corrective and the same shebang corrective as before.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/RunScriptTests.swift`: the not-executable case and the no-shebang case pass with no change of their expected texts.
- [x] `Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift`: the `executable` column for a script that only a lower layer holds, and for the higher copy of a path that two layers hold with different modes.
- [x] A source scan test: `Resources/ListResource.swift` and `Resources/RunScript.swift` name none of `FileManager`, `FileHandle`, `resourceValues`.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills
