# Changelog

Each change to the public API of this package is recorded here. The newest
change is at the top.

## Unreleased

### Removed: `SkillParameter.required` and `SkillMetadata.parameterDetails`

This change breaks the source of a host that reads `SkillParameter.required`,
gives `required:` to `SkillParameter.init`, or reads
`SkillMetadata.parameterDetails`. A host that only lists, searches or uses
skills compiles with no change.

**Cause.** No argument is required. `use skill` and the command hint no longer
read the flag, thus nothing read `SkillParameter.required`.
`SkillMetadata.parameterDetails` existed only so that `use skill` could read
that flag, and nothing read the field.

**What changed.**

- `SkillParameter` has no `required` property. Its initializer is
  `init(name:position:variadic:placeholder:)`.
- `ParameterInference` sets no flag from an `argument-hint:` token. A
  well-formed `<x>` or `[x]` token gives `x` as the name; any other token
  gives its raw text as the name. Each token stays verbatim as the
  placeholder.
- `SkillMetadata` has no `parameterDetails` property, and its initializer has
  no `parameterDetails:` parameter.

### Changed: the synthesized command hint is `[name]`, never `<name>`

This change breaks no source. It changes one text: the `argumentHint` of a
`SlashCommand` whose skill declares `arguments:` and no `argument-hint:`. A
host that compared that hint with the `<name>` form must take the `[name]`
form.

**Cause.** `SkillsRegistry.parameterSummary(parameter:)` read the `required`
flag of the parameter and gave `<name>` when the flag was set. The flag was set
for each parameter with no hint token. No argument is required, thus the
`<name>` form showed the user a rule that does not exist.

**What changed.**

- A parameter with no `argument-hint:` token gets the hint `[name]`. An
  authored `argument-hint:` token is shown as written.
- `parameterSummary(parameter:)` reads `placeholder` and `name` only.

### Changed: each `SlashCommand` body is `.rendered` through the full pipeline

This change breaks no source. It changes the body kind of each `SlashCommand`
that `SkillsRegistry.commands(workingDirectory:)` and `commandUpdates` give.
A host that matched the `.prompt(template:)` case must match the `.rendered`
case.

**Cause.** Each command carried a `.prompt(template:)` body with the raw skill
text. The harness rendered that body with Stencil only. Pass 1 (`$ARGUMENTS`,
`$N`, `$name`) and pass 2 (shell injection) never ran, so `/name text` gave
the model a body with the `$` placeholders and the shell syntax still in it.

**What changed.**

- Each command body is `SlashCommand.Body.rendered`. When the user runs
  `/name text`, the body gives `text` to `call(id:arguments:)` as one
  argument. `$ARGUMENTS` gets the text as typed, and pass 1 splits the text
  into positions with shell-style quoting: for `/commit fix the bug`, `$0` is
  `fix`; for `/commit "fix the bug"`, `$0` is `fix the bug`.
- Text that is empty or whitespace only is no argument. `/name` with nothing
  after it renders with no `ARGUMENTS:` fallback.
- `SkillsRegistry.rawBody(id:)` is gone. It was internal, and the `.prompt`
  body was its only caller.

### Changed: `use skill` renders a missing argument as an empty string

This change breaks no source. It changes one answer of the `skills` tool: a
`use skill` call that gives fewer arguments than the skill declares. A host
that compared that answer with the corrective sentence must take the rendered
body.

**Cause.** `use skill` gave the corrective "Missing required argument `x` for
this skill." when the count of the arguments was below the position of a
parameter with the `required` flag. No argument is required. The render
pipeline already gives an empty string for a reference with no value.

**What changed.**

- `UseSkill.execute(in:)` no longer counts the arguments. It calls
  `SkillsRegistry.call(id:arguments:)` with the given arguments, or with no
  argument.
- The missing-argument corrective is gone. An unknown, stale, or hidden id
  still gives the unusable-id corrective with the current id list.
- `plan.md` §6.1 and §7 and `docs/operations.md` no longer describe a
  required argument.

### Changed: the use rule of the `skills` tool asks for each skill that helps

This change breaks no source. It changes two texts that the model reads: the
use rule of the tool description, and the last line of each `search skill` and
`list skill` answer. A host that compares either text word for word must take
the new words.

**Cause.** The rule said "When a task matches a skill below, load it", and the
last line said "If a skill in this list fits your task". Three faults: a task
does not match a skill, a skill helps with a task; the words permitted one
skill only, although more than one skill can help with one task; and the rule
spoke about the start of the task only.

**What changed.**

- The use rule of the description is now: `Read the skills below before you
  start. If a skill helps with any part of your task, load it now: call this
  tool with {"op": "use skill", "id": "<id>"}. Load each skill that helps. More
  than one can apply. The answer is the text of the skill. Do the work the way
  it says. Read this list again when the work changes.`
- The last line of the load instruction is now: `If a skill in this list helps
  with any part of your task, load it now, and do the work the way it says.
  Load each skill that helps. More than one can apply. Search again when the
  work changes.`
- The load call is the same call as before, and `SkillCatalogText` still writes
  it for all three texts.
- The character limit of the description counts the skill lines alone, thus the
  longer rule takes no room from them.

### Changed: the unit of override is the file, and `DiscoveredSkill` carries each layer directory

This change breaks the source of a host that reads the layer directories of a
skill, and it changes what a skill holds when more than one layer gives the
same id. A host that only lists, searches or uses skills compiles with no
change.

**Cause.** A skill id that more than one layer held gave the files of the
highest layer alone. A `user/review/SKILL.md` hid `defaults/review/scripts/`,
`defaults/review/references/` and each other file of the lower layers, also
when the `user` layer held no such path. Thus a user who wanted to change one
sentence of a skill had to copy each file of that skill. The reason for that
rule was the `DotfolderStack` of the day, which could give the winning copy of
one item and could not give the combined view of a directory. The stack gives
that view now.

**What changed.**

- A skill is the combined view of its layer directories. For each path of the
  skill, the copy in the highest layer that holds it wins, and a file that
  only a lower layer holds stays visible. `list resource`, `read resource`
  and `run script` read that same view, thus the three can never differ on
  which copy of a file they give.
- `DiscoveredSkill.contributingDirectories` is a new field. It carries every
  layer directory of an id, lowest precedence first, also a layer that holds
  the directory and no `SKILL.md` of its own. Each item is a
  `DiscoveredSkill.ContributingDirectory`, which holds `rootIndex`, `root` and
  `skillDirectory`.
- `DiscoveredSkill.shadowedCandidates` is removed. It named the copies of
  `SKILL.md` that lost, and no copy is hidden any more. A host that showed
  those copies reads `contributingDirectories` instead.
- `skillDirectory`, `root` and `rootIndex` keep their meaning: each one names
  the layer of the winning `SKILL.md` alone.
- `run script` runs the winning copy of the script in the layer directory that
  gave that copy, and not in one skill directory, because one skill has more
  than one. Thus a script reaches the files beside it with a relative path.

**Migration.** A host that read `shadowedCandidates` reads
`contributingDirectories` and drops the last item, which is the directory of
the winning `SKILL.md`.

### Added: `StandardStream` and `ReloadReport`

Two small public types that the package, its command groups and its example
share. No existing API changed.

- `StandardStream` is the one line writer of this package. It has the cases
  `.output` and `.error`, the constant `StandardStream.lineBreak`,
  `StandardStream.text(of:)` for a list of lines, and `write(line:)` and
  `write(lines:)`. Every line that the `marketplace` command group and the
  `skills-demo` example write to a standard stream goes through it, thus the
  line break at the end of a line is stated one time.
- `ReloadReport` reads what one hot reload changed: how many skills the
  registry published, how many of them the model sees, how long the refreshed
  preload text is, and which ids the refreshed `/` listing holds.
  `ReloadReport.make(metadata:registry:)` reads a registry after a reload, and
  `lines` gives the report as text. The `--watch` mode of the example writes
  those lines, and it keeps no copy of the reading.

### Changed: a body render is `async`, and the shell pass has a timeout and an output limit

This change breaks the source of a host that renders a body: the two methods
that render a body now suspend. A host that only lists or searches skills
compiles with no change, because the metadata render stays synchronous.

**Cause.** The package started a process in two places, and the two did not
have the same safety. `run script` had a process group, a timeout and a group
`SIGKILL`; the `` !`shell` `` pass had none of them. Thus a `` !`sleep 1000` ``
in a body held the render for ever, and a command that wrote without end grew
the memory of the host. Neither path registered its pid with the
`ProcessRegistry.global` of `FoundationModelsExtras`.

**What changed.**

- Both paths start their process with `FoundationModelsExtras.ProcessRunner`.
  Each command runs in a process group of its own, its pid stands in
  `ProcessRegistry.global` while it runs, the whole group dies with `SIGKILL`
  at the timeout, and the read of the output stops at a byte limit. This
  package starts no process of its own any more.
- `RenderPolicy` carries two new fields: `shellCommandTimeout` (a `Duration`,
  30 seconds by default) and `shellOutputByteLimit` (an `Int`, 1,048,576 by
  default). `RenderPolicy.defaultShellCommandTimeout` and
  `RenderPolicy.defaultShellOutputByteLimit` name the two defaults. Every
  existing initializer argument still works.
- A command that passes either limit writes no output into the body. The pass
  writes an inert marker in its place -- `ShellInjection.timedOutMarker` or
  `ShellInjection.outputOverTheLimitMarker`, which read like the
  `disabledMarker` that was already there -- and the render of the rest of the
  body goes on.
- `RenderPipeline.renderBody(_:)`, `SkillsRegistry.call(id:arguments:)` and
  `SkillsRegistry.preloadedBodies()` are `async`. A host writes `await` at each
  call. `preloadedBodies()` must stand in a `let` before an `Instructions`
  builder, because a result builder takes no `await`.
- `RenderPipeline.renderMetadata(_:)` stays synchronous, thus `metadata()`,
  `commandListing()` and every other catalog reader keep their signatures.
- A new protocol `ShellRenderPass` carries the suspending transform of pass 2.
  `RenderPass` keeps its synchronous transform for passes 1 and 3.
  `RenderPipeline.shellInjection` and the `shellInjection:` argument of the
  initializer now take `any ShellRenderPass`. `IdentityRenderPass` conforms to
  both protocols, thus it still stands in for any of the three passes.
- `QuarantinedText` gained `mappingOriginalSpans(awaiting:)`, the suspending
  twin of `mappingOriginalSpans(_:)`.
- `run script` gives the same results, with the same fields and the same
  correctives.

### Changed: `search skill` and `list skill` give plain text that names the load command

This change breaks the source of a host that reads `SearchSkillOutput`,
`SearchSkill.execute(in:)`, `ListSkill.execute(in:)`, or one of the removed
types below. A host that gives the `skills` tool to a session, and does not
read the answer, compiles with no change.

**Cause.** In a SWE-bench run, `search skill` gave one JSON object of 9,343
characters: a `matches` array with a `use` object for each skill, the body of
the first match as an escaped JSON string, and a `next` text that did not say
what the load command is. The model did not load a skill, and it did not
follow one.

**What changed.**

- `search skill` gives plain text: the line `Skills that match "<query>":`,
  one line `- <id>: <description>` for each match in rank order, and four
  lines that name the exact load call, `{"op": "use skill", "id": "<id>"}`,
  with an example for the first match. `limit` and the rank order do not
  change.
- The body of a skill is no longer in the search result. There is no `use`
  object, no `next` field, no `total`, and no `skill` field. `use skill` is the
  one way to get a skill.
- A search with no match gives the one line `No skill matches this search.`,
  with no load instruction.
- `list skill` gives the same lines, in catalog order, and the same load
  instruction. A `filter` that matches nothing gives
  `No skill matches this filter.` A `list skill` line no longer shows the
  marketplace source. `SkillMetadata.source` and the `/` command listing still
  have it.
- The second sentence of the tool description is now: "When a task matches a
  skill below, load it: call this tool with {"op": "use skill", "id": "<id>"}.
  The answer is the text of the skill. Do the work the way it says."
- `SearchSkillOutput` is now `CorrectiveOutcome<String>`. `ListSkill.Output` is
  now `String`.
- Removed: `SkillRow`, `SkillUseCall`, `SearchSkillResult`, `ListSkillResult`,
  and `UseSkillResult`. No operation gives these types now.
- The command line prints the JSON of each operation, thus `skills skill search`
  and `skills skill list` print the text as one JSON string.

See [docs/operations.md](docs/operations.md) for the new answers.

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
