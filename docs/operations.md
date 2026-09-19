# Operations

The `skills` tool is one fused tool with six operations. The schema is a
flat union: an `op` discriminator plus every field as an optional. The `id`
field is an enum of the visible skill ids. An invalid input does not throw.
The tool returns a corrective message that tells the model how to correct the
call.

## The tool description and the `id` enum

A model reads the name, the description, and the schema of a tool before it
plans. Thus `SkillsTool.make` puts the catalog in the description and in the
schema. It reads `registry.metadata()` one time, keeps the skills that the
visibility predicate accepts, and keeps the catalog order.

The description has two fixed sentences, then one line for each skill:

```text
Skills are procedures for kinds of work. Each one tells you how to do the work and which tools to use.
When a task matches a skill below, load it: call this tool with {"op": "use skill", "id": "<id>"}. The answer is the text of the skill. Do the work the way it says.

- explore: Understand how unfamiliar code works before planning or changing it.
- code-context: Find symbols, callers, and the blast radius of a change.
```

The list has a limit, `catalogCharacterLimit`. The default is 8,000
characters (`SkillsTool.defaultCatalogCharacterLimit`). The fixed sentences
do not count against it and are never cut. The tool tries these steps in
order, and stops at the first one that fits:

1. Each skill with its full description.
2. Each description shortened to 200 characters, with the same truncation as
   the user `/` menu.
3. The ids only, on one comma-separated line.
4. As many ids as fit, then the line
   ``<N> more skills are not listed. Find them with `search skill`.``

When no skill is visible, the description is `Skills are procedures for kinds
of work.` and the line `No skills are installed now.`

The `id` field of the schema is an enum of the visible ids, thus the model
cannot invent an id. When no skill is visible, `id` stays a plain string,
because an empty enum accepts no value. The `id` field has the description
`The id of the skill to load.` The schema root has no description, thus the
catalog is not in the prompt two times.

### Hot reload

A tool description and a schema are fixed when a session is made. A hot
reload does not rebuild the tool:

- `search skill` and `list skill` find a skill that a hot reload adds.
- The description of the tool does not show that skill, and the `id` enum
  does not hold its id. Thus the model cannot load it with `use skill` in the
  current session.
- The next session gets a new tool, thus the skill is in its description and
  in its `id` enum.

## The operations

| op | parameters | behavior |
|---|---|---|
| `search skill` | `query` (req), `limit?` | Finds the skills for the kind of work that the model will do next. Search by the kind of work, not by the topic of the task. The answer is plain text: one line for each match from `SkillSearchAgent` over the model-visible catalog, in rank order, and the instruction that names the exact `use skill` call. See [The `search skill` and `list skill` answers](#the-search-skill-and-list-skill-answers). |
| `list skill` | `filter?` | Lists each skill with its description: the model-visible catalog (with an optional filter), in catalog order, with no ranking. The answer is the same plain lines and the same instruction as `search skill`. |
| `use skill` | `id` (req), `arguments?` | Loads the instructions of a skill for the model to follow: renders the pipeline (plan.md §5) with `arguments`. The answer is the rendered body as plain text. An unknown or hidden `id` returns a corrective sentence that contains the current id list. See [The `use skill` answer](#the-use-skill-answer). |
| `list resource` | `id` (req) | Lists each file in the skill's directory except `SKILL.md`. The list stops at 100 rows. |
| `read resource` | `id` (req), `path` (req), `start?`, `end?` | Returns a file verbatim, in a line window: 500 lines maximum and 1,000,000 content bytes maximum for each call. The tool never renders the file. It streams the file in 64 KiB parts and never loads the full file. `totalLines` is exact. See [development.md](development.md) for the exact byte-budget rules. |
| `run script` | `id` (req), `path` (req, in `scripts/`), `arguments?`, `timeout?` | Runs the file directly. The file must have the executable bit and a shebang. Three gates apply: the host policy, the skill's `allowed-tools: Script(<glob>)` grant, and the host trust posture. The process runs in its own process group. A timeout sends `SIGKILL`. |

## The `use skill` answer

The model reads the answer of `use skill` as the procedure to follow. Thus
the answer is the rendered body of the skill, and nothing else. It is plain
text: no JSON object, no `body` key, no `id` key, and no escape sequences.
The tool adds no tag, marker, or wrapper.

For the call `{"op": "use skill", "id": "explore"}`, the answer is the text of
the skill, with its line breaks, as the render pipeline gives it:

```text
…the rendered body of explore, line for line…
```

Before, the answer was a JSON object:
`{"body": "…the rendered body, with \n escapes…", "id": "explore"}`.

An error is a plain sentence too. It says what is wrong. For an unknown or
hidden id, it names the ids that the model can use:

```text
The skill id `totally-made-up` is not currently usable. Currently usable ids: commit, env-report, lint.
```

A missing required argument of the skill gives:

```text
Missing required argument `message` for this skill.
```

The resource operations keep their JSON answers. The command line
(`SkillsCLI`) prints the JSON of each operation, thus `skills skill search`,
`skills skill list`, and `skills skill use` print the text as one JSON string.

## The `search skill` and `list skill` answers

A list of matches alone is a menu. A model can read it as information and
continue with no skill. Thus the answer names the exact call that loads a
skill, and tells the model to load a skill that fits its task. The answer is
plain text: no JSON object, no `use` field, no `next` field, and no body of a
skill. `use skill` is the one way to get a skill. The tool adds no tag, marker,
or wrapper.

For the call `{"op": "search skill", "query": "explore codebase and find symbol"}`,
the answer is:

```text
Skills that match "explore codebase and find symbol":

- explore: Understand how unfamiliar code works before planning or changing it.
- code-context: Find symbols, callers, and the blast radius of a change.
- lsp: Diagnose the language servers of the workspace.

To load a skill, call the `skills` tool with {"op": "use skill", "id": "<id>"}.
For example: {"op": "use skill", "id": "explore"}
The answer is the text of the skill: the steps of the work and the tools to use.
If a skill in this list fits your task, load it now, and do the work the way it says.
```

- The first line names the query of the call.
- Each match is on one line, `- <id>: <description>`, in rank order. `limit`
  sets the most lines. A description on more than one line becomes one line.
- The example call loads the first match.

A search with no match gives one line, with no load instruction. Thus the
answer never tells the model to load a skill that is not there:

```text
No skill matches this search.
```

`list skill` gives the same lines and the same four instruction lines, in
catalog order, with no first line. For the call `{"op": "list skill"}`, the
answer is:

```text
- code-context: Find symbols, callers, and the blast radius of a change.
- explore: Understand how unfamiliar code works before planning or changing it.

To load a skill, call the `skills` tool with {"op": "use skill", "id": "<id>"}.
For example: {"op": "use skill", "id": "code-context"}
The answer is the text of the skill: the steps of the work and the tools to use.
If a skill in this list fits your task, load it now, and do the work the way it says.
```

A `filter` that matches no skill gives the one line
`No skill matches this filter.` With no visible skill, `search skill` and
`list skill` give `No skills are available.`

Before, the answer was a JSON object with `matches`, `total`, a `use` object
for each match, a `next` field, and, when the selection tier chose the first
match, the rendered body of that match in a `skill` field.

## Marketplaces

The model surface holds no marketplace operation. A marketplace skill is an
ordinary skill of the same catalog, thus `search skill`, `list skill`, and `use
skill` show it with no change. A `search skill` or `list skill` line gives the
id and the description only. The `/` command listing
(`registry.commandListing()`) names the marketplace that the skill came from,
for example `swissarmyhammer-skills@1.2.0`. The model cannot add, remove, pin,
or update a marketplace: that work belongs to the host and to the
`skills marketplace` commands. See [marketplaces.md](marketplaces.md).

## Verb aliases

`find` and `discover` resolve to `search`. `call`, `invoke`, and `get`
resolve to `use`. The `run` verb belongs to `run script`, thus `run skill`
does not resolve to `use skill`.

## Visibility

| Frontmatter | User `/` menu | Model surface | In context at start |
|---|---|---|---|
| *(default)* | listed | searchable + usable | no (body on use) |
| `disable-model-invocation: true` | listed | hidden | no |
| `user-invocable: false` | hidden | searchable + usable | no |
| `preload: true` | listed | searchable + usable | **yes** (body injected into `Instructions`) |

`ListSkill`, `UseSkill`, and the resource operations obey
`context.visibilityPredicate`. `SkillsTool.make` sets it to
`isModelVisible` as the default. `SkillsCLI` supplies a different
predicate: id membership in `registry.commandListing()`. Thus the CLI
shows the user-facing surface.
