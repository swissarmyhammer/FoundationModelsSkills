---
assignees:
- claude-code
position_column: todo
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

- [ ] Add the re-export file with its doc comment.
- [ ] Add the single-import test.
- [ ] Run the full test suite.

## Acceptance Criteria

- [ ] A source file whose only skills-related import is `import FoundationModelsSkills` can name `MetadataSearcher`, `SelectionConfig`, `AgentSession`, and `DotfolderStack`, and it compiles.
- [ ] A `LanguageModelSession` can be used where an `any AgentSession` is expected, with no `import FoundationModelsMetadataRegistry` and no `import FoundationModelsRanker`.
- [ ] `swift build` gives no new warning.

## Tests

- [ ] New file `Tests/FoundationModelsSkillsTests/SingleImportTests.swift`. Its imports are only `FoundationModels`, `FoundationModelsSkills`, and `Testing` — it must not import `FoundationModelsMetadataRegistry`, `FoundationModelsRanker`, or `FoundationModelsExtras`.
- [ ] A test case builds a `MetadataSearcher<SkillMetadata>` and a `SkillSearchAgent`, and asserts that a search over a two-item catalog gives a match. This proves the search types are visible.
- [ ] A test case builds a `DotfolderStack` over a temporary directory. This proves the Extras types are visible.
- [ ] A test case assigns `LanguageModelSession(model: .default, instructions: "test")` to a `let session: any AgentSession` binding. This proves the `AgentSession` conformance arrives through the re-export. Do not send a prompt, thus the test needs no on-device model.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.