---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Re-export the search seam so one import is sufficient
---
## What

A host that builds the `skills` tool must now write `import FoundationModelsMetadataRegistry` to name `MetadataSearcher`, `SelectionConfig`, and `AgentSession`. Remove that second import.

Add `Sources/FoundationModelsSkills/Search/MetadataRegistryReexport.swift` with `@_exported import FoundationModelsMetadataRegistry`.

`FoundationModelsMetadataRegistry` already has `@_exported import FoundationModelsRanker` in `Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift`. Thus one re-export here gives a host all of these types:

- `MetadataSearcher<Item>`, `SearchMode`, `Match`
- `SelectionConfig`, `AgentSession`, `SelectionTierUnavailable`
- `extension LanguageModelSession: AgentSession`
- `TextEmbedding`, `SignalWeights`

Write a doc comment on the new file. Say why the re-export is there: a host that gives the tool a standard `LanguageModelSession` must not need to know which sibling package holds the search seam.

Keep the plain `import FoundationModelsMetadataRegistry` lines in `Search/SkillSearchAgent.swift` and `CLI/SkillsCLI.swift`. They are correct, and the re-export does not make them wrong.

- [ ] Add the re-export file with its doc comment.
- [ ] Add the single-import test.
- [ ] Run the full test suite.

## Acceptance Criteria

- [ ] A source file whose only skills-related import is `import FoundationModelsSkills` can name `MetadataSearcher`, `SelectionConfig`, and `AgentSession`, and it compiles.
- [ ] A `LanguageModelSession` can be used where an `any AgentSession` is expected, with no `import FoundationModelsMetadataRegistry` and no `import FoundationModelsRanker`.
- [ ] `swift build` gives no new warning.

## Tests

- [ ] New file `Tests/FoundationModelsSkillsTests/SingleImportTests.swift`. Its imports are only `FoundationModels`, `FoundationModelsSkills`, and `Testing` — it must not import `FoundationModelsMetadataRegistry` or `FoundationModelsRanker`.
- [ ] A test case builds a `MetadataSearcher<SkillMetadata>` and a `SkillSearchAgent`, and asserts that a search over a two-item catalog gives a match. This proves the types are visible.
- [ ] A test case assigns `LanguageModelSession(model: .default, instructions: "test")` to a `let session: any AgentSession` binding. This proves the `AgentSession` conformance arrives through the re-export. Do not send a prompt, thus the test needs no on-device model.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.