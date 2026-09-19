# Changelog

Each change to the public API of this package is recorded here. The newest
change is at the top.

## Unreleased

### Changed: `use skill` gives the text of the skill, not JSON

This change breaks the source of a host that reads `UseSkillOutput` or
`UseSkill.execute(in:)`. The success value is now the rendered body, a
`String`, not a `UseSkillResult`. A host that gives the `skills` tool to a
session, and does not read the answer, compiles with no change.

**Cause.** In a SWE-bench run, `use skill` gave
`{"body": "…", "id": "explore"}`. The procedure was an escaped JSON string
(`\n`, `\/`), not text, and the model did not follow it.

**What changed.**

- The answer of `{"op": "use skill", "id": "<id>"}` from
  `SkillsCatalogTool.call(arguments:)` and `SkillsCatalogTool.perform(_:)` is
  the rendered body of the skill as plain text, and nothing else: no JSON, no
  `body` key, no `id` key, no escape sequences, and no tag, marker, or
  wrapper. Each verb alias of `use skill` (`call`, `invoke`, `get`) gives the
  same answer.
- An error of `use skill` is a plain sentence, not a quoted JSON string. An
  unknown or hidden id names the ids that the model can use. A missing
  required argument names the argument.
- `UseSkillOutput` is now `CorrectiveOutcome<String>`. `UseSkillResult` stays:
  it is the `skill` field of a `search skill` result.
- The other operations keep their JSON answers.
- The command line prints the JSON of each operation, thus `skills skill use`
  prints the body as one JSON string.

See [docs/operations.md](docs/operations.md) for the new answer.

### Changed: the `skills` tool shows its catalog and a use rule, and its `id` is an enum

This change breaks the source of a host that names the type
`OperationTool<SkillsToolContext>`. A host that holds the tool as `any Tool`
compiles with no change.

**Cause.** In a SWE-bench run, the model searched for a skill but never loaded
one. The tool description was "Search, list, and use skills from the local
skill library." It did not say what a skill is, it did not tell the model to
follow a skill that applies, and the model did not see which skills exist. The
`id` field was any string, thus the model could not see the valid ids.

**What changed.**

- Every `SkillsTool.make` factory returns `SkillsCatalogTool`, a new `Tool`. It
  forwards each call to `SkillsCatalogTool.operationTool`, the
  `OperationTool<SkillsToolContext>` that the factories returned before. It
  conforms to `ForkableTool` and `OperationDescribing`, and it has
  `operations` and `skillIDs`. `SkillsCLI` gives `operationTool` to
  `OperationCLIDriver`.
- The tool description is made from the catalog when the tool is made:
  `registry.metadata()`, filtered by the visibility predicate, in catalog
  order. It has two fixed sentences, then one `- <id>: <description>` line for
  each skill. With no visible skill, it is the first sentence and
  `No skills are installed now.`
- `catalogCharacterLimit` is a new parameter of
  `SkillsTool.make(context:catalogCharacterLimit:)` and of the two assembly
  factories that forward to it. The default is
  `SkillsTool.defaultCatalogCharacterLimit`, 8,000 characters. Over the limit,
  the list shortens each description to 200 characters, then gives the ids on
  one line, then gives as many ids as fit and
  ``<N> more skills are not listed. Find them with `search skill`.`` The fixed
  sentences are never cut.
- The `id` field of the fused schema is an enum of the visible ids. With no
  visible skill, it stays a plain string. The schema root has no description.
- The description and the enum are fixed when the tool is made. A skill that
  a hot reload adds is found by `search skill`, but the model cannot load it
  with `use skill` until the next session makes a new tool.
- New operation texts. `use skill`: "Load the instructions of a skill. Follow
  them." `search skill`: "Find the skills for the kind of work that you will
  do next, for example explore code, find callers, or run tests. Search by the
  kind of work, not by the topic of the task." `list skill`: "List each skill
  with its description." The `id` parameter of `use skill`: "The id of the
  skill to load."

See [docs/operations.md](docs/operations.md) for the description and the enum.

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
