---
assignees:
- claude-code
depends_on:
- 01M199WZNA6SCK8332HZDE3S2T
position_column: todo
position_ordinal: '8180'
title: Add a one-call SkillsTool factory that takes an injected session
---
## What

Today a host must assemble four things by hand to get the `skills` tool: a `SkillsRegistry`, a `MetadataSearcher`, a `SkillSearchAgent`, and a `SkillsToolContext`. Give the host one call instead, and make the selection session an injected parameter.

`OperationTool` already conforms to the FoundationModels `Tool` protocol (`FoundationModelsExtras/Sources/Operations/OperationTool.swift:25`). Thus the result of this factory goes straight into `LanguageModelSession(tools:)`.

Add `Sources/FoundationModelsSkills/Operations/SkillsToolAssembly.swift`. It holds an `extension SkillsTool` with two new factory methods, one for each way a host supplies a session. The two shapes match `SelectionConfig`'s own two initializers in `FoundationModelsRanker/Sources/FoundationModelsRanker/Selection/SelectionConfig.swift:90` and `:118`:

```swift
// The host makes a session for each assembled candidate prefix.
public static func make(
    registry: SkillsRegistry,
    session: @escaping @Sendable (String) -> any AgentSession,
    embedder: (any TextEmbedding)? = nil,
    visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool = { $0.isModelVisible }
) throws -> OperationTool<SkillsToolContext>

// The host already holds one live session.
public static func make(
    registry: SkillsRegistry,
    session: any AgentSession,
    ...
) throws -> OperationTool<SkillsToolContext>
```

Add a third overload with no `session` parameter. It builds a keyword-only `.retrieval` searcher, which is the catalog search that needs no model at all.

Each factory does the same four steps:
1. Read `registry.metadata()` and keep the `visibilityPredicate` subset.
2. Build the `MetadataSearcher` with that subset. Give it the `SelectionConfig` when a session was supplied.
3. Wrap it in a `SkillSearchAgent` with the same `visibilityPredicate`.
4. Build the `SkillsToolContext` and call the existing `SkillsTool.make(context:)`.

Confirm the exact `MetadataSearcher.init(items:mode:...)` parameter names against `FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:139` before you write the call.

Do not change or remove `SkillsTool.make(context:)`. It stays the low-level door for a host that tunes the searcher itself.

- [ ] Add the three factory overloads with full doc comments.
- [ ] Add the factory tests.
- [ ] Run the full test suite.

## Acceptance Criteria

- [ ] `try SkillsTool.make(registry: registry, session: mySession)` gives a tool, in one call, with no `MetadataSearcher` named by the caller.
- [ ] The no-session overload gives a working `.retrieval` tool, and a `search skill` op against it gives ranked matches with no model on the host.
- [ ] The supplied session, and only the supplied session, backs selection. No factory hardcodes `SystemLanguageModel` or `.default`.
- [ ] `SkillsTool.make(context:)` keeps its current signature and behavior.

## Tests

- [ ] New file `Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift`.
- [ ] A test case builds a registry over the `Examples/skill-library` fixture stack, calls the no-session overload, dispatches `search skill` through `tool.call(arguments:)`, and asserts on the ranked ids. Follow the dispatch pattern already in `Tests/FoundationModelsSkillsTests/SkillOperationsTests.swift`.
- [ ] A test case passes a scripted fake `AgentSession` (the double pattern in `Tests/FoundationModelsSkillsTests/HotReloadTests.swift`) to the factory-closure overload, then asserts the fake was called. This proves the injected session is the one that runs.
- [ ] A test case passes the same fake to the live-session overload and asserts the same.
- [ ] A test case asserts that the model-hidden fixture skill is absent from the results of a factory built with the default `visibilityPredicate`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.