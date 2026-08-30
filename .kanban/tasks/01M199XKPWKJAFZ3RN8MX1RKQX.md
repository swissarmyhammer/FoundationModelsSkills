---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19crkx22d0re19a2qgv2fa0
  text: |-
    ### Research

    Confirmed the signatures the card names.

    - `MetadataSearcher` has a synchronous `init(items:mode:weights:selection:onDiagnostic:)` and an `async init(items:mode:weights:embedder:selection:onDiagnostic:)`. The `embedder` parameter has no default value on the async one, thus naming `embedder:` selects the async initializer with no ambiguity. This is why the three factories must be `async`.
    - `SelectionConfig` has `init(model:preamble:capacityCharacterLimit:candidateLimit:)` (one-argument `@Sendable (String) -> any AgentSession`) and `init(session:preamble:capacityCharacterLimit:candidateLimit:)`.
    - `MetadataSearcher.search` in `.auto` mode uses the selection tier when one is configured, and falls back to retrieval when none is. Thus the two session overloads can keep `.auto`, and only the no-session overload needs the explicit `mode: .retrieval`.

    Test plan facts.

    - The fused tool encodes its result with `JSONEncoder` and `outputFormatting = [.sortedKeys]` (`Operations/AnyOperation.swift`). Thus the tests decode the returned JSON into a local `Decodable` mirror instead of matching substrings in a fixed key order.
    - `deploy` is the model-hidden fixture skill (`disable-model-invocation: true`).
    - `SkillMetadata.renderBlock()` joins id, description, and parameters. No fixture block other than `commit` contains the text "commit", thus a two-axis fake embedder can align the query vector with `commit` only.
    - The cosine proof is behavioral: a query with no keyword or trigram overlap gives zero matches with no embedder, and gives exactly the cosine-aligned skill with the fake embedder. `HybridRanker` ranks only positively scored documents, thus a match can only come from the cosine signal.
    - `AgentSession` needs only `respond(to:)`. `fork()` and `respond(to:generating:)` have protocol defaults.
  timestamp: 2026-08-30T13:11:56.578425+00:00
- actor: claude-code
  id: 01m19d1hnnhatdtzndad5exej5
  text: |-
    ### Implementation landed

    Followed `/tdd`. The test file went in first and failed to compile with only "incorrect argument label in call (have 'registry:', expected 'context:')" and "missing argument for parameter 'context'". That is the correct RED for a new Swift API.

    Added `Sources/FoundationModelsSkills/Operations/SkillsToolAssembly.swift` with three `async throws` `SkillsTool.make` overloads and one private `assemble` helper that holds the four shared assembly steps. The session overloads use `mode: .auto`, thus the configured selection tier answers every search. The no-session overload uses `mode: .retrieval` explicitly. `SkillsTool.make(context:)` is untouched.

    Added `FixtureLibrary.stack(thisFile:)`, which builds the three-layer `DotfolderStack` over `Examples/skill-library` with an empty environment. This reuses `FixtureLibrary.root(thisFile:)` instead of a second copy of the path walk.

    Mutation check on the cosine case: with `embedder: nil` forced inside `assemble`, `theEmbedderReachesTheSearcherAndItsCosineSignalRanksAMatch` fails on `cosineIDs == [Self.alignedSkillID]`. Thus the case really does detect a dropped embedder. The change was reverted immediately.

    `swift test`: 386 tests in 28 suites passed. No failures and no warnings.
  timestamp: 2026-08-30T13:16:49.205481+00:00
- actor: claude-code
  id: 01m19d89n2adg02zwt5cpq1whh
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsSkills/Operations/SkillsToolAssembly.swift (new), Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift (new), Tests/FoundationModelsSkillsTests/FixtureLibrary.swift (added `stack(thisFile:)`). `swift build`: build complete, no new warning. `swift test`: 386 tests in 28 suites passed, 0 failures, 0 warnings.
    - next: /review
  timestamp: 2026-08-30T13:20:30.370563+00:00
- actor: claude-code
  id: 01m19dqfr5q869q5y20da96ffc
  text: |
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (backend local) — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. 3 files reviewed. Acceptance criteria checked: all three `make` overloads resolve (swift build --build-tests: exit 0, no ambiguity), the async `MetadataSearcher(items:mode:embedder:selection:)` initializer is the one called, the no-session overload passes `mode: .retrieval`, no `SystemLanguageModel` and no `.default` in the new source or test file, and `SkillsTool.make(context:)` is untouched.
    - next: task moved to done.
  timestamp: 2026-08-30T13:28:48.133901+00:00
- actor: claude-code
  id: 01m19dr7m4b2jccw8xe30n00aj
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files (SkillsToolAssembly.swift, SkillsToolAssemblyTests.swift, FixtureLibrary.swift)
    - test: green — swift test, 386 tests in 28 suites, 0 failures, 0 warnings
    - commit: 5398846
    - review: clean — review sha HEAD~1..HEAD, 0 findings, 7 validators attempted, 0 failed
    - next: task is in done; ^et0ar2e is now unblocked
  timestamp: 2026-08-30T13:29:12.580970+00:00
depends_on:
- 01M199WZNA6SCK8332HZDE3S2T
- 01M19AK51NF7PEDQSMWAVYCCBJ
position_column: done
position_ordinal: bc80
title: Add a one-call SkillsTool factory that takes an injected session
---
## What

Today a host must assemble four things by hand to get the `skills` tool: a `SkillsRegistry`, a `MetadataSearcher`, a `SkillSearchAgent`, and a `SkillsToolContext`. Give the host one call instead, and make the selection session an injected parameter.

`OperationTool` already conforms to the FoundationModels `Tool` protocol (`../FoundationModelsExtras/Sources/Operations/OperationTool.swift:25`). Thus the result of this factory goes straight into `LanguageModelSession(tools:)`.

Add `Sources/FoundationModelsSkills/Operations/SkillsToolAssembly.swift`. It holds an `extension SkillsTool` with three factory methods. The first two match `SelectionConfig`'s own two initializers, at `../FoundationModelsRanker/Sources/FoundationModelsRanker/Selection/SelectionConfig.swift:90` and `:118`:

```swift
// The host makes a session for each assembled candidate prefix.
public static func make(
    registry: SkillsRegistry,
    session: @escaping @Sendable (String) -> any AgentSession,
    embedder: (any TextEmbedding)? = nil,
    visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool = { $0.isModelVisible }
) async throws -> OperationTool<SkillsToolContext>

// The host already holds one live session.
public static func make(
    registry: SkillsRegistry,
    session: any AgentSession,
    ...
) async throws -> OperationTool<SkillsToolContext>

// No model at all: keyword retrieval only.
public static func make(
    registry: SkillsRegistry,
    embedder: (any TextEmbedding)? = nil,
    visibilityPredicate: ... 
) async throws -> OperationTool<SkillsToolContext>
```

### Two constraints that fix the signature

1. **The factories must be `async`.** `MetadataSearcher`'s embedder-taking initializer is `async` (`../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:179`). Only the initializer at `:139` is synchronous. A non-`async` factory cannot honor a non-`nil` `embedder`.
2. **The no-session overload must pass `mode: .retrieval` explicitly.** The default is `.auto`, not `.retrieval`.

Each factory does the same four steps:
1. Read `registry.metadata()` and keep the `visibilityPredicate` subset.
2. Build the `MetadataSearcher` with that subset. Give it the `SelectionConfig` when a session was supplied.
3. Wrap it in a `SkillSearchAgent` with the same `visibilityPredicate`.
4. Build the `SkillsToolContext` and call the existing `SkillsTool.make(context:)`.

Confirm the exact `MetadataSearcher` parameter names against the two initializers named above before you write the calls.

Do not change or remove `SkillsTool.make(context:)`. It stays the low-level door for a host that tunes the searcher itself.

- [x] Add the three factory overloads with full doc comments.
- [x] Add the factory tests.
- [x] Run the full test suite.

## Acceptance Criteria

- [x] `try await SkillsTool.make(registry: registry, session: mySession)` gives a tool, in one call, with no `MetadataSearcher` named by the caller.
- [x] The no-session overload gives a working `.retrieval` tool, and a `search skill` op against it gives ranked matches with no model on the host.
- [x] A non-`nil` `embedder` reaches the searcher. A test proves the cosine signal is present in the results.
- [x] The supplied session, and only the supplied session, backs selection. No factory hardcodes `SystemLanguageModel` or `.default`.
- [x] `SkillsTool.make(context:)` keeps its current signature and behavior.

## Tests

- [x] New file `Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift`.
- [x] A test case builds a registry over the `Examples/skill-library` fixture stack, calls the no-session overload, dispatches `search skill` through `tool.call(arguments:)`, and asserts on the ranked ids. Follow the dispatch pattern already in `Tests/FoundationModelsSkillsTests/SkillOperationsTests.swift`.
- [x] A test case passes a scripted fake `AgentSession` (the double pattern in `Tests/FoundationModelsSkillsTests/HotReloadTests.swift`) to the factory-closure overload, then asserts the fake was called. This proves the injected session is the one that runs.
- [x] A test case passes the same fake to the live-session overload and asserts the same.
- [x] A test case passes a deterministic fake `TextEmbedding` and asserts the cosine signal is non-zero in a match. This proves the `embedder:` parameter is honored, which the `async` signature exists for.
- [x] A test case asserts that the model-hidden fixture skill is absent from the results of a factory built with the default `visibilityPredicate`.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.