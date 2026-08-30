---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19bwdta1spxfygk4c412150
  text: |-
    Picked up. Research done.

    Facts found:
    - `FoundationModelsMetadataRegistry/Sources/.../FoundationModelsRankerReexport.swift` holds `@_exported import FoundationModelsRanker` with a `//` comment block. The new file follows that shape.
    - `extension LanguageModelSession: AgentSession` is in `FoundationModelsRanker/Sources/FoundationModelsRanker/Selection/LanguageModelSessionSupport.swift`. No `#if` and no `@available` guard.
    - `SelectionConfig.init(model:)` takes `@escaping @Sendable (String) -> any AgentSession`. `SelectionConfig.sessionSource` is a public `SelectionSessionSource` with a `.factory` case.
    - `DotfolderStack.init(name:workingDirectory:defaultsDirectory:userDirectory:environment:)` does no file I/O. With an empty environment and no `defaultsDirectory`, `layers` is `[.user, .project]`.
    - `WatcherTestSupport.makeTempDirectory()` already exists in the test target. The new test reuses it instead of a new copy.

    Rules read: `dump validators` over one Swift file gave code-hygiene, code-security, completeness, duplication, reuse, swift and test-integrity.
  timestamp: 2026-08-30T12:56:32.842285+00:00
- actor: claude-code
  id: 01m19c285fm1bdsh0aabcp5ws7
  text: |-
    TDD record.

    RED: `SingleImportTests.swift` was written first. `swift build --build-tests` gave the expected errors, one for each seam the card names:
    - `cannot find 'MetadataSearcher' in scope`
    - `cannot find 'SelectionConfig' in scope`
    - `cannot find type 'AgentSession' in scope`
    - `cannot find 'DotfolderStack' in scope`

    GREEN: `SeamReexports.swift` removed all four. `swift test` gives 381 tests in 27 suites, 0 failures.

    One thing that did not work, recorded so the next agent does not repeat it: the first draft of the dotfolder test used `defer { try? FileManager.default.removeItem(at:) }`, which is the prevailing pattern in this test target. It gave a fifth error, `cannot find 'FileManager' in scope`: Foundation does not reach this file through the re-exports, and the card holds the test file to `FoundationModels`, `FoundationModelsSkills` and `Testing` alone. The fix keeps both requirements: a new `WatcherTestSupport.withTempDirectory(_:)` makes the directory, gives it to the body, and removes it. The test file thus names no `FileManager`. `WatcherTestSupport`'s own doc comment was widened, because it named only two consumers and already had more.
  timestamp: 2026-08-30T12:59:43.663014+00:00
- actor: claude-code
  id: 01m19c2cnmjnvg0hatx582tdny
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsSkills/SeamReexports.swift (new), Tests/FoundationModelsSkillsTests/SingleImportTests.swift (new), Tests/FoundationModelsSkillsTests/WatcherTestSupport.swift (added `withTempDirectory(_:)`). `swift build`: build complete, no new warning. `swift test`: 381 tests in 27 suites passed, 0 failures.
    - next: /review
  timestamp: 2026-08-30T12:59:48.276839+00:00
position_column: doing
position_ordinal: '80'
title: Re-export the search seam so one import is sufficient
---
## What

A host that builds the `skills` tool must now write two extra imports: `import FoundationModelsMetadataRegistry` to name `MetadataSearcher`, `SelectionConfig`, and `AgentSession`, and `import FoundationModelsExtras` to name `DotfolderStack`. Remove both.

Add `Sources/FoundationModelsSkills/SeamReexports.swift`:

```swift
@_exported import FoundationModelsExtras
@_exported import FoundationModelsMetadataRegistry
```

`FoundationModelsMetadataRegistry` already has `@_exported import FoundationModelsRanker` in `Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift:12`. Thus one re-export gives a host all of these types:

- `MetadataSearcher<Item>`, `SearchMode`, `Match`
- `SelectionConfig`, `AgentSession`, `SelectionTierUnavailable`
- `extension LanguageModelSession: AgentSession` (`../FoundationModelsRanker/Sources/FoundationModelsRanker/Selection/LanguageModelSessionSupport.swift:30`, ungated by any `#if` or `@available`)
- `TextEmbedding`, `SignalWeights`

The `FoundationModelsExtras` re-export gives `DotfolderStack`, which every host needs to build the layer roots, and which the README usage block constructs.

Write a doc comment on the new file. Say why the re-exports are there: a host that gives the tool a standard `LanguageModelSession` must not need to know which sibling package holds the search seam or the dotfolder stack.

Keep the plain `import` lines in `Search/SkillSearchAgent.swift` and `CLI/SkillsCLI.swift`. They are correct, and the re-export does not make them wrong.

- [x] Add the re-export file with its doc comment.
- [x] Add the single-import test.
- [x] Run the full test suite.

## Acceptance Criteria

- [x] A source file whose only skills-related import is `import FoundationModelsSkills` can name `MetadataSearcher`, `SelectionConfig`, `AgentSession`, and `DotfolderStack`, and it compiles.
- [x] A `LanguageModelSession` can be used where an `any AgentSession` is expected, with no `import FoundationModelsMetadataRegistry` and no `import FoundationModelsRanker`.
- [x] `swift build` gives no new warning.

## Tests

- [x] New file `Tests/FoundationModelsSkillsTests/SingleImportTests.swift`. Its imports are only `FoundationModels`, `FoundationModelsSkills`, and `Testing` — it must not import `FoundationModelsMetadataRegistry`, `FoundationModelsRanker`, or `FoundationModelsExtras`.
- [x] A test case builds a `MetadataSearcher<SkillMetadata>` and a `SkillSearchAgent`, and asserts that a search over a two-item catalog gives a match. This proves the search types are visible.
- [x] A test case builds a `DotfolderStack` over a temporary directory. This proves the Extras types are visible.
- [x] A test case assigns `LanguageModelSession(model: .default, instructions: "test")` to a `let session: any AgentSession` binding. This proves the `AgentSession` conformance arrives through the re-export. Do not send a prompt, thus the test needs no on-device model.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.