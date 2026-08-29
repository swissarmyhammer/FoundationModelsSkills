# Operations

The `skills` tool is one fused tool with six operations. The schema is a
flat union: an `op` discriminator plus every field as an optional. An
invalid input does not throw. The tool returns a corrective message that
tells the model how to correct the call.

| op | parameters | behavior |
|---|---|---|
| `search skill` | `query` (req), `limit?` | Returns ranked matches from `SkillSearchAgent` over the model-visible catalog. |
| `list skill` | `filter?` | Returns the model-visible catalog (with an optional filter), in catalog order, with no ranking. |
| `use skill` | `id` (req), `arguments?` | Renders the pipeline (plan.md §5) with `arguments`. An unknown or hidden `id` returns a corrective message that contains the current id list. |
| `list resource` | `id` (req) | Lists each file in the skill's directory except `SKILL.md`. The list stops at 100 rows. |
| `read resource` | `id` (req), `path` (req), `start?`, `end?` | Returns a file verbatim, in a line window: 500 lines maximum and 1,000,000 content bytes maximum for each call. The tool never renders the file. It streams the file in 64 KiB parts and never loads the full file. `totalLines` is exact. See [development.md](development.md) for the exact byte-budget rules. |
| `run script` | `id` (req), `path` (req, in `scripts/`), `arguments?`, `timeout?` | Runs the file directly. The file must have the executable bit and a shebang. Three gates apply: the host policy, the skill's `allowed-tools: Script(<glob>)` grant, and the host trust posture. The process runs in its own process group. A timeout sends `SIGKILL`. |

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
