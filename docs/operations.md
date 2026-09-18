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
When a task matches a skill below, you must load that skill with `use skill` and follow its instructions before you do the work.

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
| `search skill` | `query` (req), `limit?` | Finds the skills for the kind of work that the model will do next. Search by the kind of work, not by the topic of the task. Returns ranked matches from `SkillSearchAgent` over the model-visible catalog. Each match carries the `use` call that loads it, and the result tells the model to use a skill that applies. See [The `search skill` result](#the-search-skill-result). |
| `list skill` | `filter?` | Lists each skill with its description: the model-visible catalog (with an optional filter), in catalog order, with no ranking. |
| `use skill` | `id` (req), `arguments?` | Loads the instructions of a skill for the model to follow: renders the pipeline (plan.md §5) with `arguments`. An unknown or hidden `id` returns a corrective message that contains the current id list. |
| `list resource` | `id` (req) | Lists each file in the skill's directory except `SKILL.md`. The list stops at 100 rows. |
| `read resource` | `id` (req), `path` (req), `start?`, `end?` | Returns a file verbatim, in a line window: 500 lines maximum and 1,000,000 content bytes maximum for each call. The tool never renders the file. It streams the file in 64 KiB parts and never loads the full file. `totalLines` is exact. See [development.md](development.md) for the exact byte-budget rules. |
| `run script` | `id` (req), `path` (req, in `scripts/`), `arguments?`, `timeout?` | Runs the file directly. The file must have the executable bit and a shebang. Three gates apply: the host policy, the skill's `allowed-tools: Script(<glob>)` grant, and the host trust posture. The process runs in its own process group. A timeout sends `SIGKILL`. |

## The `search skill` result

A list of matches alone is a menu. A model can read it as information and
continue with no skill. Thus the result tells the model what to do, and how.

- Each match has a `use` field. It holds the exact arguments of the `skills`
  call that loads that skill. The model can send it back as it is.
- A result with at least one match has a `next` field: one plain instruction.
- A result with no match has no `next` field. It never tells the model to load
  a skill that is not there.

When the retrieval tier gives the matches (a host with no model, or the
retrieval fallback after a selection answer that did not decode), the result
holds the list only:

```json
{
  "matches": [
    {
      "description": "Understand how unfamiliar code works before planning or changing it.",
      "id": "explore",
      "parameters": [],
      "use": { "id": "explore", "op": "use skill" }
    }
  ],
  "next": "If a skill in this list applies to your task, you must use it. Load it now with its `use` call, and follow its instructions before you continue with the task.",
  "total": 1
}
```

When the selection tier chose the first match, the result also has a `skill`
field. It holds the rendered body of that one skill, from the same render path
as `use skill` with no argument. Then `next` changes:

```json
{
  "matches": [
    {
      "description": "Understand how unfamiliar code works before planning or changing it.",
      "id": "explore",
      "parameters": [],
      "use": { "id": "explore", "op": "use skill" }
    }
  ],
  "next": "The first skill is loaded below. If it applies to your task, you must follow it. If a different skill applies, load it with its `use` call.",
  "skill": { "body": "…the rendered body of explore…", "id": "explore" },
  "total": 1
}
```

Only the first match gets a body, to keep the result small. A first match with
a required argument gets no body, because `use skill` with no argument gives a
corrective for it. A body that does not render also gives no body: the failure
goes to the log, and the search result stays a success. In both cases `next` is
the instruction to load a skill.

The tool encodes the JSON with sorted keys, thus `skill` comes after `next`.
A `list skill` row has no `use` field, and a `list skill` result has no `next`
field.

## Marketplaces

The model surface holds no marketplace operation. A marketplace skill is an
ordinary row of the same catalog, thus `search skill`, `list skill`, and `use
skill` show it with no change. A `list skill` row can name the marketplace that
the skill came from, for example `swissarmyhammer-skills@1.2.0`. The model
cannot add, remove, pin, or update a marketplace: that work belongs to the host
and to the `skills marketplace` commands. See
[marketplaces.md](marketplaces.md).

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
