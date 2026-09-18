# Changelog

Each change to the public API of this package is recorded here. The newest
change is at the top.

## Unreleased

### Added: a `search skill` result tells the model to use a skill that applies, and how

This change breaks no host source. The new fields are JSON for the model, and
each new Swift parameter has a default.

**Cause.** In a SWE-bench run, `search skill` returned four matches, and the
model did not load one. It read the list as information, not as a step to do,
and it never got the procedure of a skill. The same model obeyed the `next`
text of another tool 28 times, thus a clear instruction in the result is
followed.

**What changed.**

- Each `search skill` match has a `use` field with the exact arguments of the
  call that loads it: `{"op": "use skill", "id": "<id>"}`. `SkillRow.use` and
  the new `SkillUseCall` hold it. A `list skill` row has no `use` field.
- A result with at least one match has a `next` field with one instruction to
  the model. A result with no match has no `next` field.
- When the selection tier chose the first match, the result has a `skill`
  field with the rendered body of that one skill, from the same render path as
  `use skill`, and `next` tells the model that the first skill is loaded. A
  retrieval rank, and a first match with a required argument, give no body.
- `SkillSearchAgent.answer(query:limit:)` is new. It returns a
  `SkillSearchAnswer`: the matches, and `isSelection`, which is `true` only
  when the selection tier chose them. `search(query:limit:)` is unchanged.
- `SearchSkillResult.init(matches:total:skill:)` takes an optional `skill`
  and derives `next`. `SearchSkillResult.useInstruction` and
  `SearchSkillResult.loadedInstruction` hold the two `next` texts.

See [docs/operations.md](docs/operations.md) for the output.

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
