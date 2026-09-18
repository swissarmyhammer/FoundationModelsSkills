# Changelog

Each change to the public API of this package is recorded here. The newest
change is at the top.

## Unreleased

### Changed: the `session:` closure of `SkillsTool.make` takes a `SelectionSessionRequest`

This change breaks the source of each host that gives the `skills` tool a
selection session.

**Cause.** The selection tier reads the answer of the model as
`{"ids": [String]}`. The `session:` closure got the instructions only, thus the
host did not know that the answer must have that shape. A host session with no
constraint let a small model write `[explore]`, not `{"ids": ["explore"]}`. The
decode of that answer failed, and the whole `skills` call failed with it.

**What changed.**

- `SkillsTool.make(registry:session:embedder:followReloads:visibilityPredicate:)`
  takes `@Sendable (SelectionSessionRequest) -> any AgentSession`. It took
  `@Sendable (String) -> any AgentSession`.
- `SelectionSessionRequest` is new. It holds `instructions`, `candidateIDs` and
  `jsonSchema`. `jsonSchema` limits the answer to `{"ids": [...]}`, where each id
  is one of `candidateIDs`, with `uniqueItems` and a `maxItems` of the candidate
  count.
- The overload `SkillsTool.make(registry:session: any AgentSession, ...)` is
  removed. One live session cannot apply a new JSON Schema for each call.
- `SkillSearchAgent.init(searcher:retrievalFallback:visibilityPredicate:)` takes
  an optional second searcher in `.retrieval` mode. When the selection tier
  throws, that searcher ranks the query, and the failure goes to the log. The
  factory always gives one. Thus an answer that does not decode gives the
  keyword rank, not a failed `skills` call.

### Migration

A host whose model takes a JSON Schema grammar applies `request.jsonSchema`
when it makes the session. `FoundationModelsACPAgent` makes this change in
`ToolCatalog.makeSkillsTool`:

```swift
// Before:
return try await SkillsTool.make(
    registry: registry,
    session: { instructions in
        SelectionAgentSession(session: profile.flash.makeSession(instructions: instructions))
    })

// After:
return try await SkillsTool.make(
    registry: registry,
    session: { request in
        SelectionAgentSession(session: profile.flash.makeGuidedSession(
            grammar: .jsonSchema(request.jsonSchema), instructions: request.instructions))
    })
```

A host that gives a `LanguageModelSession` reads `request.instructions`:

```swift
// Before:
session: { prefix in LanguageModelSession(model: .default, instructions: prefix) }

// After:
session: { request in LanguageModelSession(model: .default, instructions: request.instructions) }
```

A host that gave one live session to the removed overload gives a closure that
makes a session for each request.
