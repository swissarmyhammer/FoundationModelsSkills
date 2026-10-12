---
assignees:
- claude-code
depends_on:
- 01M4R0ANACQ08YDG539AAJ8FA4
position_column: todo
position_ordinal: '8180'
title: 'read resource: give the absolute path of a binary file, not an error'
---
## What
Now, `read resource` of a file that is not UTF-8 text (for example `assets/logo.bin`) gives a corrective message (`ReadResource.nonUTF8Message`). Change this to a successful result. The result tells the model that the file is binary, and gives the absolute path of the winning copy and the byte size. The model can give the path to a different tool.

- `Sources/FoundationModelsSkills/Resources/ResourceRow.swift`: add these fields to `ReadResourceResult`: `binary: Bool`, `absolutePath: String?`, `byteSize: Int?`. Give the new `init` parameters default values (`binary: false`, `absolutePath: nil`, `byteSize: nil`), so that each call of `ReadResourceResult(id:path:content:start:end:totalLines:)` compiles with no change. For a binary read, `content` is one sentence, for example: "This file is binary. It is not shown as text. Its absolute path is `<path>` and its size is <n> bytes." `start`, `end` and `totalLines` are `0` for a binary read. Update the doc comments.
- `Sources/FoundationModelsSkills/Resources/ReadResource.swift`: in `execute(in:)`, the `.nonUTF8` case of the scan returns `.success` with the binary result. The absolute path is `overlay.resolve(relativePath)?.url.path` with no change. Do NOT call `resolvingSymlinksInPath`: `LoadingBoundaryTests` forbids it. The round trip works because the absolute-path rule resolves the symlinks through Extras. The scan still stops at the first byte that is not valid UTF-8, so the operation never loads the whole binary file. Delete `nonUTF8Message`. Update the doc comments that name the non-UTF-8 corrective.
- `ReadResource.operationDescription`: add that a binary file gives its absolute path and its size, not its content.
- Docs: `docs/operations.md` (the `read resource` row) and `docs/development.md` (where it describes the non-UTF-8 corrective).

## Acceptance Criteria
- [ ] `read resource` of `assets/logo.bin` in the `release-notes` fixture gives `.success` with `binary == true`, the correct `byteSize`, an `absolutePath` of the winning copy, and a `content` sentence that says the file is binary.
- [ ] The `absolutePath`, when given as the `path` of a second `read resource` call, gives the same binary result again.
- [ ] A text read gives the JSON fields and values of now, plus `"binary":false`.
- [ ] A binary copy in a lower layer, with no copy in a higher layer, gives the absolute path of the lower-layer copy.
- [ ] `LoadingBoundaryTests` passes.

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift`: change the non-UTF-8 corrective tests to the binary-success result.
- [ ] `Tests/FoundationModelsSkillsTests/ReadResourceTests.swift`: add the absolute-path round-trip test and the lower-layer binary test. The existing memberwise-init tests compile with no change.
- [ ] Search `Tests/` for `not valid UTF-8` and update each other match.
- [ ] `swift test` passes with no failure.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.