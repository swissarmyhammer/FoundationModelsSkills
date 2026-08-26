# Plan: agentskills.io → Foundation Models Skills bridge

A Swift package that loads [agentskills.io](https://agentskills.io/specification) /
[Claude-style](https://code.claude.com/docs/en/slash-commands) skill directories from disk
and exposes them to Apple's
[Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
(WWDC26) through **one fused operation tool** — built on the
[`FoundationModelsOperations`](https://github.com/swissarmyhammer/FoundationModelsOperationTool)
package (the sah "operation" pattern: `op: "verb noun"` dispatch, forgiving resolver,
dual-use CLI) — plus a separate listing surface for command/`/`-matching. Skills load
through **host-supplied layer roots** (#29; conventionally `.skills` directories) using
[`FoundationModelsExtras`](../FoundationModelsExtras/plan.md) — the family's shared
substrate (`DotfolderStack`, `FrontmatterDocument`, `TemplateEngine`). **Primary target:
macOS, on-device.**

---

## 1. Guiding principles

- **A skill is just data behind a tool — no special case.** In an FM session, skills are
  reached through one fused `OperationTool` whose vocabulary is **`search skill` /
  `list skill` / `use skill`**. The framework has no skills concept; we add operations over
  a registry, not a new primitive.
- **Skills are rows, not operations.** Operations are compile-time declarations; skills are
  runtime data that hot-reloads. The op vocabulary is a small fixed set of meta-verbs whose
  `id` parameter names the skill — never one op per skill.
- **Keep the root session lean.** The full catalog is **not** dumped into the root context.
  Discovery is offloaded to a **separate search-agent session**; only an explicitly chosen
  skill's body (plus any preloaded skills) ever enters the root transcript.
- **One registry, many consumers.** A reloadable **`SkillsRegistry`** is the source of truth;
  it powers the fused skills tool, the search agent, the preload injection, the
  user-facing `/` command listing, **and the CLI** — all *views* of one registry.
- **Shared substrate underneath, domain validation on top.** The generic machinery —
  layered dotfolder resolution, frontmatter splitting, Stencil templating — is
  **imported from [`FoundationModelsExtras`](../FoundationModelsExtras/plan.md)**, the
  family's substrate leaf, not built here *(decision #29)*. The downstream
  [`../FoundationModelsAgents`](../FoundationModelsAgents/plan.md) package draws on the
  same substrate directly. Skill discovery, validation, and semantics sit a layer above.
- **macOS-first, on-device.** iOS is a graceful "unavailable" stub.

## 2. Where "skills" actually live in Apple's stack (correction)

- The **core `FoundationModels` framework** (WWDC26) provides `LanguageModelSession`,
  `DynamicProfile`/`Profile`/`Instructions`, the **`Tool`** protocol, multimodal
  `Attachment`, context/token APIs, usage tracking, reasoning levels, server-side providers,
  and built-in tools (`OCRTool`, `BarcodeReaderTool`, Spotlight RAG). It has **no skills
  type**.
- The experimental **`FoundationModelsUtilities`** package ships a `Skills { … }` builder
  (the model activates a skill *by generating a tool call*). **We do not depend on it** — we
  build on `FoundationModelsOperations`, which conforms to the core `Tool` protocol and
  gives us full control over search, the call contract, arguments, preload, and reload.

## 3. Layered architecture

Four layers, bottom to top. The lower two are **imported from
[`FoundationModelsExtras`](../FoundationModelsExtras/plan.md)** — the family's substrate
leaf — not built here *(decision #29)*.

```
┌─ Layer 4  FM adapter (skills) ─────────────────────────────────────────────┐
│   Skill operations — SearchSkill / ListSkill / UseSkill structs fused by   │
│   FoundationModelsOperations.OperationTool into ONE core Tool              │
│   SkillSearchAgent — MetadataSearcher over skill metadata (#26, separate   │
│   Router session + rank-fusion retrieval; never the root session)          │
│   preload injection (rendered bodies → root Instructions)                  │
│   commandListing() — user `/` menu view (separate from the model surface)  │
│   OperationCLIDriver — dual-use CLI from the same op declarations          │
├─ Layer 3  SkillsRegistry  (discovery + domain validation + semantics) ──────┤
│   dir-shaped discovery over the stack (name/SKILL.md, full-replace by id),  │
│   Yams frontmatter decode, agentskills.io + Claude validation, visibility,  │
│   arguments, render pipeline (§5), file watcher, reload → injectable        │
│   metadata, generic call(id:arguments:) — built ON the Extras substrate     │
├─ Layers 1–2  FoundationModelsExtras  (imported substrate) ──────────────────┤
│   DotfolderStack — one way to derive layer roots (host may supply its own); │
│   nearest/locate/enumerate/content, source tracking, path-safety checks     │
│   FrontmatterDocument — textual (frontmatter, body) split; no YAML dep      │
│   TemplateEngine — Stencil facade: _partials/ includes via DotfolderLoader, │
│   trusted/untrusted split, context > env > well-known precedence ladder     │
└──────────────────────────────────────────────────────────────────────────┘
```

- **`FoundationModelsExtras`** supplies the substrate: **`DotfolderStack`** (layered
  locations `defaults < user < project` with nearest-wins resolution, per-item source
  tracking, and path-safety checks — construction does no I/O), **`FrontmatterDocument`**
  (pure textual frontmatter/body split — YAML decoding is deliberately the consumer's),
  and **`TemplateEngine`** (the Stencil facade: layered `_partials/` includes, the
  trusted/untrusted split, the variable-precedence ladder). The old plan built these as
  exported Layers 1–2; that machinery now lives below the whole family, and
  `../FoundationModelsAgents` consumes it from Extras directly *(supersedes the export
  promise in #17/#19)*.
- **What Extras deliberately does not do, we own in Layer 3:** (a) **directory-shaped
  discovery** — Extras' `enumerate` lists flat files; skills are `name/SKILL.md`
  directories, so the registry walks its host-supplied roots itself, later shadowing earlier
  by directory name (full-replace, #3), provenance from the layer that won; (b) **YAML
  decoding** (Yams) over the textual split; (c) the **file watcher** — the stack locates,
  it never watches; we watch every layer root and rebuild (§7); (d) all **skill
  semantics** — validation, visibility, arguments, and the render pipeline's
  `$`-substitution and shell passes (§5).
- **`SkillsRegistry`** (Layer 3, the source of truth) — wraps the `.skills`
  `DotfolderStack`; adds discovery, agentskills.io + Claude validation, the visibility
  model (§6), argument handling (§5), and **reload → injectable metadata** (§7). Exposes a
  generic `call(id:arguments:)`. **Skill validation is strictly above the raw stack.**
- **FM adapter** (Layer 4) — the skill operation structs and their fused `OperationTool`,
  the `SkillSearchAgent`, preload injection, the `commandListing()`, and the CLI driver —
  all reading the registry.

## 4. Identity & naming

- **Directory name = canonical id.** It is the key for stack override, `/name` command
  matching, and the `use skill` op's `id` — never the frontmatter `name`.
- **agentskills.io requires `name`, and it must equal the directory name.** Enforced rules:
  1–64 chars, `[a-z0-9-]` only, no leading/trailing hyphen, no consecutive `--`,
  `name == directoryName`.
- **Claude-style inputs may omit `name`** (a `.claude/commands/foo.md` or a `SKILL.md` without
  `name` defaults to the dir/file name), so `SkillListing.displayName` is optional only for
  those inputs.
- **`description` is required by the spec** (1–1024 chars, non-empty) — it is the disclosure
  contract. The remaining spec fields are parsed and carried as data: `license` (free text)
  and `compatibility` (1–500 chars) land on `SkillListing` with no behavior attached;
  `allowed-tools` (a **space-separated string**, experimental in the spec) is parsed now and
  consumed at M6.
- **Lenient validation** — the posture of the spec's client-implementation guide: name
  irregularities (≠ directory name, > 64 chars, bad characters) → diagnostic, **load
  anyway**; unparseable YAML → skip + diagnostic, after a **quoting-fallback retry** for the
  common cross-client error (an unquoted colon inside `description`). Missing/empty
  `description` → diagnostic + **excluded from the model surface** (it cannot be disclosed);
  we deviate from the guide's skip-entirely rule only to keep description-less Claude
  command files user-invocable. A shadowed id (full-replace winner up the stack) and a
  `SKILL.md` over the spec's recommended 500 lines each draw an advisory diagnostic.
  Validation-parity target: the `skills-ref` reference validator.
- **Extension fields ride `metadata.*` for portability.** Our non-spec fields (`preload`,
  `user-invocable`, `disable-model-invocation`, `arguments`, `argument-hint`) are
  accepted **both** top-level (the Claude convention — canonical for us, #5) **and** under
  `metadata:`, the spec's designated home for client-defined properties — so a skill
  authored for maximum agentskills.io portability keeps its top level pure-spec. Unknown
  top-level keys never block loading (diagnostic only).
- **Skills load from roots the host supplies** *(decision #29, amended 2026-07-28)*: the
  registry takes an ordered list of layer roots, lowest precedence first, and names no
  directory convention of its own. Extras'
  `DotfolderStack(name: "skills", workingDirectory: …)` is a convenience that derives one
  such list — shipped defaults (optional; `SKILLS_DEFAULTS_DIR` repoints it for dev, no
  rebuild) < user `$XDG_CONFIG_HOME/skills/` < project `<cwd>/.skills/` — and hosts that
  want the client guide's cross-client `.agents/skills` layout simply pass those roots
  instead. Precedence is
  last-root-wins, realizing our full-replace rule, with source tracking carrying
  provenance into diagnostics. The spec mandates only what's *inside* a skill directory,
  so every one of these is a conforming host convention. Discovery skips
  `.git`/`node_modules` and bounds scan depth. The winning layer also picks the render
  trust mode (§5), and hosts should still trust-gate untrusted project layers (§8).

## 5. Templating & arguments — the render pipeline

Skills render **once** at list/call time, never re-evaluated mid-transcript (no KV-cache
bust). One ordered pipeline, each pass single-shot and **not re-scanned** by later passes:

1. **Argument + variable substitution** (Claude-compatible):
   - `$ARGUMENTS` — all args as typed; if the body omits it, append `ARGUMENTS: <value>`.
   - `$ARGUMENTS[N]` / `$N` — **0-based** positional (`$0` = first arg); shell-style quoting.
   - `$name` — named arg from the `arguments:` frontmatter (space-separated or YAML list).
   - `${SKILL_DIR}` and friends — special vars (our analog of `${CLAUDE_SKILL_DIR}`).
   - `\$` escapes a literal `$`.
2. **Shell injection** — `` !`command` `` (only at line start / after whitespace) and fenced
   ` ```! ` blocks; run via `/bin/sh`, output inlined as plain text, **not** re-scanned. macOS
   only (§8). **Dynamic at render, static in transcript:** commands re-execute on *every*
   render — each `use skill` dispatch, user-driven `/command`, or CLI `use` — so output
   reflects current state; once returned, it is fixed in the transcript. **Body only** —
   `description`/`metadata` values render at metadata-build/reload/list time, where shell
   execution would fire on every watcher event, so they get passes 1 and 3 only (matches
   Claude). A `disableShellExecution` policy flag, **set at registry construction** so all
   render paths honor it (model, `/command`, CLI), mirrors Claude's
   `disableSkillShellExecution`. *(decision #25)*
3. **Stencil via Extras' `TemplateEngine`** — variables resolve through the precedence
   ladder (explicit context — where skill arguments also land — > environment variables
   as flat keys, e.g. `{{ HOME }}` > well-known values: `working_directory`, `date`,
   `hostname`, `dotfolder_name`) + `{% include "header" %}` partials resolved through the
   stack's layered `_partials/` directories (`DotfolderLoader`, nearest layer wins).
   Render trust maps from the skill's winning layer — defaults → `.trusted`,
   user/project → `.untrusted` (tag/filter whitelist; include-depth 8, so unbounded
   include recursion is impossible by construction; 1 MiB output and 100k-iteration
   budgets). *(decision #29; amends #2's `{{ env.* }}` spelling)*
   **One template per render.** The whole body (or metadata value) renders as one
   Stencil template: text passes 1–2 spliced in is handed to Stencil as an opaque context
   value, never as template text. So the untrusted budgets are per *render*, not per
   splice; a `{% if %}…{% endif %}` block may straddle a `$N` splice; a spliced value can
   never form template syntax; and a splice *inside* a variable, tag, or comment
   (`{{ $1 }}`, `{% if $1 %}`, `{# $1 #}`) is a rendering error, since substituted data
   must never drive template structure.

Templated: `description`, all `metadata` values, and the body. The **directory-name id stays
literal**. Argument frontmatter: `arguments:` (named positional list) + `argument-hint:`
(autocomplete hint), both surfaced in the listing.

**Resolved (re-scanning):** passes are ordered and single-shot; injected shell output is
**never** re-scanned. **Resolved (partials):** partials are **`_partials/*.md` files in
the stack, not skills** — `{% include %}` renders them inside the parent's Stencil pass
with Stencil's standard context semantics. Because pass 1 runs on the skill body
**before** Stencil, `$`-tokens inside a partial file are never argument-substituted, so
partials stay shared, arg-free building blocks. *(decision #16, amended by #29)*

## 6. Visibility model & the two listing surfaces

Adopt Claude's two axes, plus our `preload`:

| Field | User `/` menu | Model surface | In context at startup | Notes |
|---|---|---|---|---|
| *(default)* | listed | searchable + usable | no (body on use) | both audiences |
| `disable-model-invocation: true` | listed | hidden | no | user-only command (e.g. `/deploy`) |
| `user-invocable: false` | hidden | searchable + usable | no | model-only background |
| `preload: true` *(ours)* | listed | searchable + usable | **yes** (body injected) | body always-on in Instructions; re-use is redundant; see §7 |

- **`SkillsRegistry.commandListing()`** → `[SkillListing]` for the user `/` menu, carrying
  **structured, parsed parameters** (§6.1). **We produce data only** — autocomplete, fuzzy
  search, and input validation are the UI's job, out of scope here.
- **Harness delivery channel: Extras' `SlashCommandProviding`** *(decision #29)* — the
  registry conforms: `commands(workingDirectory:)` derives from `commandListing()` (name,
  description, `argumentHint` from §6.1), and `commandUpdates` ticks on every reload (§7).
  Caveat, stated plainly: the `.prompt(template:)` body kind re-renders through the
  harness's engine, which runs none of §5's passes 1–2 (`$`-arguments, shell injection) —
  an invocation-aware prompt body is a recorded Extras coordination item; a host that
  wants full render fidelity calls `registry.call(id:arguments:)` directly (§7.1).
- `partial: true` is **retired** *(#29)*: shared building blocks are `_partials/*.md`
  files in the stack — not skill directories, so they are invisible to discovery by
  construction. Encountering `partial: true` draws a diagnostic and hides the skill from
  every surface (preserving the old intent).
- "Model surface" filtering is applied by the operation implementations: `search skill` /
  `list skill` exclude model-hidden skills; `use skill` refuses them with a corrective
  message.

### 6.1 Parsed parameter model

```swift
struct SkillListing {
  let id: String                  // directory name = the /command
  let displayName: String?        // frontmatter `name`
  let description: String?        // rendered, truncated for the menu
  let license: String?            // spec `license` — data only (§4)
  let compatibility: String?      // spec `compatibility` — data only (§4)
  let parameters: [SkillParameter]
  let acceptsTrailingArguments: Bool   // body uses $ARGUMENTS (free-form tail)
}
struct SkillParameter {
  let name: String                // from `arguments:` or the hint token
  let position: Int               // 0-based, matches $0/$1/$ARGUMENTS[N]
  let required: Bool
  let variadic: Bool              // trailing `...`
  let placeholder: String?        // raw hint text for display
}
```

Parameters merge three sources by position — precedence `arguments:` > `argument-hint:` > body
inference:
- **`arguments:`** — authoritative names for `$name` and order.
- **`argument-hint:`** — display + optionality (`<x>` required, `[x]` optional, trailing `...`
  variadic). **Bare-token rule:** a token with neither bracket form — a bare word (`env`) or a
  malformed placeholder (`[env`, unclosed) — is **optional**. The hint is display text, and only
  the explicit `<x>` form marks a token required; a display-only word must never block `use skill`
  with a missing-argument corrective. A malformed token keeps its raw text verbatim as both
  placeholder and name. This is distinct from a position **no** hint token describes (`arguments:`
  past the hint's arity, or body inference), which stays required — there the source is silent.
  The missing-argument corrective names the structured `SkillParameter.name` (`arguments:` when
  present), never the hint token's inner text.
- **Body inference** — when neither is present, scan the body for `$0`/`$N`/`$ARGUMENTS[N]` and
  synthesize positional params so the listing is never empty.

`acceptsTrailingArguments` is true only when the body **references** `$ARGUMENTS` (a
meaningful free-form tail the UI should prompt for). The §5 auto-append (`ARGUMENTS: <value>`
when `$ARGUMENTS` is absent) is a no-data-loss fallback for stray args and does **not** set the
flag. Diagnostics flag mismatches between sources.

## 7. The operation vocabulary — nouns, verbs & model-facing dynamics

The model-facing surface is **one fused `OperationTool`** (from
`FoundationModelsOperations`) built from three operation structs sharing a
`SkillsToolContext` (registry + search agent). The fused schema is a **flat union**:
a required `op` string enum (`"search skill"`, `"list skill"`, `"use skill"`) plus the union
of all fields as optionals — dispatch validates and returns **corrective messages, never
throws** (upstream's return-don't-throw + retry-cap pattern).

| op | parameters | behavior |
|---|---|---|
| `search skill` | `query` (req), `limit?` (default 5) | Delegates to the **`SkillSearchAgent`** (`MetadataSearcher`, #26) over the **model-visible** catalog → returns ranked matches — id, rendered description, parsed parameter summary (§6.1) — best first, plus `total` so the model knows to raise `limit`. Primary discovery path: the catalog lives in the search agent, never the root. Empty/blank `query` → corrective message. |
| `list skill` | `filter?` (case-insensitive substring over id + description) | The model-visible catalog (full or filtered) on demand — same row shape as `search skill`, catalog order, no session, no ranking, no tokens. For small sets or explicit enumeration. A `filter` matching nothing returns an empty list (not an error) with `total: 0`. |
| `use skill` | `id` (req), `arguments?` (positional strings, §5 quoting) | Dereferences the **live registry at dispatch time** → renders the §5 pipeline with `arguments` → returns the rendered body. Unknown/stale/model-hidden id → corrective message **carrying the current id list** (#22); a missing required argument (§6.1) → corrective message naming it; extra trailing args ride the §5 `ARGUMENTS:` auto-append, never an error. |

**Typed outputs** (upstream `AnyOperation.run` JSON-encodes every `Output: Encodable` —
the Shelltool pattern; corrective messages stay plain strings per the
return-don't-throw contract):

```swift
struct SkillRow: Encodable {          // one catalog row, shared by search + list
  let id: String                      // the use-skill / /command key
  let description: String             // rendered (§5 passes 1+3)
  let parameters: [String]            // §6.1 placeholder summaries, e.g. "<message>", "[env]"
}
struct SearchSkillResult: Encodable { let matches: [SkillRow]; let total: Int }
struct ListSkillResult:   Encodable { let skills:  [SkillRow]; let total: Int }
struct UseSkillResult:    Encodable { let id: String; let body: String }  // body = §5 render
```

- **Noun is singular `skill`**; the forgiving resolver tolerates reversed order
  (`skill list`) and `_`/`-` separators — **not** plural nouns: upstream's resolver
  compares the noun token literally with no singularization, so `skills list` stays
  `Unknown operation` (amended; see decision #21). Verb aliases ride the shared resolver
  table: `find/discover → search`, `call/invoke/get → use`. `run` is deliberately **not**
  a `use` alias — it's reserved for the M6 `run script` operation, since upstream's verb
  rewrite is unconditional per-verb (not per-noun) and a `run → use` entry would rewrite a
  literal `"run script"` query before it ever reached `RunScript`. *(decisions #20–21)*
- **`id` is a plain string, validated at dispatch.** No dynamic id enum: skills hot-reload
  between turns, and Apple's enum-enforcement bug (forums 812501/811620) means the model can
  emit values outside an `anyOf` list anyway. An unknown/stale/model-hidden id returns a
  corrective message carrying the current id list; upstream's retry cap (default 2) stops
  loops. This **supersedes decision #18.** *(decision #22)*
- **Resource nouns are fully specified in §7.3 and built at M6:** `list resource`,
  `read resource`, `run script` join the same fused tool — six ops, inside upstream's
  5–15 guidance; a second `OperationTool` only if the vocabulary grows further.
  *(decision #23, amended: specified now, built at M6)*

**`SkillSearchAgent` — a thin wrapper over `MetadataSearcher<SkillMetadata>`** from
[`../FoundationModelsMetadataRegistry`](../FoundationModelsMetadataRegistry/plan.md)
*(decision #26; supersedes the bespoke search session)*. The registry's **skill metadata**
(id, description, params; not full bodies — rendered as text blocks) seeds the searcher,
which layers hybrid ranked retrieval (BM25 + trigram + cosine → RRF) under an LLM
selection session on a Router model. Benefits: (a) the root session is never clogged with
the whole catalog; (b) selection runs on a cheaper Router-selected model with
fork-per-call prefix reuse, and its ids-only output is xgrammar-constrained to the
current id set; (c) large catalogs are served by `.retrieval` mode (rank fusion, no
session, no tokens) — superseding the earlier Spotlight-RAG idea. Returns candidate ids
plus verbatim metadata blocks the root then feeds to `use skill`.

**Assembly.** The old many-knobbed builder (#15) dissolves: `OperationTool` init takes
`(name:description:context:operations:)`, and the remaining knobs live in three places —
`SkillsRegistry` construction (render policy, e.g. `disableShellExecution` — it must sit
where the pipeline runs so the `/command` and CLI paths honor it too, #25),
`SkillsToolContext` construction (the `MetadataSearcher` configuration — selection model,
mode, signal weights, capacity budget), and upstream `OperationTool` options
(`includesSchemaInInstructions`, retry cap).
Which actions exist = which operation structs you pass. *(supersedes decision #15)*

**Preload.** Skills with `preload: true` have their **rendered bodies injected into the root
session's `Instructions`** at startup, alongside the fused tool — always-on context, no
search/use needed. Use sparingly (every preloaded line is a recurring token cost).

**Reload & metadata injection.** The registry's file watcher (over every stack layer
root — Extras' stack locates, it never watches, #29) fires on add/remove/edit up the
stack → `SkillsRegistry` rebuilds and publishes a **refreshed metadata list** (observable).
On reload we: (a) forward the refreshed metadata to the searcher's **`update(items:)`**
(hash-guarded; incremental re-embed; rebuilds the selection prefix + id grammar); (b) refresh the
**preloaded** bodies in the root; (c) leave the fused tool untouched — its schema is
id-free and its operations dereference the live registry per dispatch, so hot-reload is
invisible to the root session. The registry also exposes an **initial** metadata list at
construction and the generic **`call(id:arguments:)`** used by both the ops and any host code.

### 7.1 How skills reach a session

The **listing (metadata) and a skill's rendered body travel by different channels** — the
full catalog is never dumped into the root session. One `SkillsRegistry`, four consumers:

```
                       ┌──────────── SkillsRegistry (source of truth) ────────────┐
  UI (presentation) ◀──┤ commandListing()  →  [SkillListing] (data only)          │
  search session    ◀──┤ metadata()        →  SkillSearchAgent (re-injected/reload)│
  root session      ◀──┤ preloadedBodies() →  Instructions at startup              │
  CLI (§7.2)        ◀──┤ call(id:arguments:) → one rendered body, on demand        │
                       └──────────────────────────────────────────────────────────┘
```

**What enters the root session:** only (a) `preloadedBodies()` at construction and (b) the
rendered body of each skill explicitly used — one at a time. The catalog/metadata does
**not** enter the root; the only catalog-derived thing in the schema is nothing at all — the
fused tool's schema is the fixed op vocabulary, independent of which skills exist (§7).

**Metadata is shared with an actual `LanguageModelSession` only via the `SkillSearchAgent`** —
deliberately, so the root stays lean and avoids the all-descriptions-in-context token cost.

**A deliberate divergence from the spec's tier-1 disclosure.** The agentskills.io
client-implementation guide's default puts a name+description **catalog in context at
session start** (system prompt or activation-tool description, ~50–100 tokens per skill).
We replace that standing catalog with on-demand discovery — `search skill` / `list skill`
are always in the fused tool's schema, so the model still knows skills exist and how to
find them; it just pays for descriptions only when it asks. Tier 2 (full body on
activation) and tier 3 (resources on demand, M6) match the guide exactly, as does its
filtering rule — model-hidden skills are **absent** from search/list results, never
listed-then-blocked (the `use skill` refusal is only a backstop for ids learned outside
the catalog). A host that wants guide-standard disclosure can inline `registry.metadata()`
into its `Instructions` itself. *(decision #27)*

**Two invocation paths put a rendered body into the transcript:**
- **Model-driven** — the model calls `{op: "search skill", query: …}` → search agent returns
  candidate ids → `{op: "use skill", id: …, arguments: …}` → registry renders → body returned
  as the tool's output.
- **User-driven (`/command`)** — this is where the UI listing connects to a session. The UI
  used `commandListing()` only to present the command and collect arg values; on submit it
  resolves the choice into a registry call and feeds the result in as that turn's input:

```swift
// UI collected: id = "deploy", values = ["production"]
let rendered = try registry.call(id: "deploy", arguments: ["production"])
try await root.respond(to: rendered)     // rendered body enters the transcript
```

(Mirrors Claude: the `/` menu shows descriptions, but invoking a command injects the rendered
`SKILL.md` as a message.) So the **listing informs the UI; the render is what's shared with the
session.**

### 7.2 Dual-use CLI *(new, free from the operation pattern)*

The same operation declarations drive an `OperationCLIDriver` command tree
(`<executable> <noun> <verb> …`), converging on the **exact payload the model sends** —
upstream pins this with round-trip tests. This gives skill authors a way to inspect and
render skills outside any session:

```
skills skill list
skills skill search "commit my changes"
skills skill use --id deploy --arguments production
```

*(Amended: the macro-less fallback CLI leaf (`FallbackOperationCommand`/`FallbackPayloadBuilder`
in `../FoundationModelsOperationTool`) recognizes only `--name value`/`-short` flags — a bare
positional token like `deploy` right after `use` is silently dropped, never populating `id`.
The originally-drafted positional form (`use deploy …`) never actually worked; `--id` is
required. See `SkillsCLITests`' CLI-syntax pins.)*

Help, did-you-mean, and shell completions come from stock ArgumentParser. The CLI respects
the same visibility rules as the user surface (it is a user, not a model).

### 7.3 Resource operations — the M6 vocabulary, at full fidelity

Skills bundle optional `scripts/`, `references/`, and `assets/` directories — the
agentskills.io **tier-3** story. Three further ops expose them **lazily**: enumerated on
demand, read on demand, never eagerly loaded (the client guide's rule). They *build* at
M6 but are specified here to the same standard as the core three. All three gate on the
context's visibility predicate (`SkillsToolContext.visibilityPredicate`) and share the §7
corrective/no-throw contract. *(Recorded resolution: the shipped ops do not hardcode the
model-visible catalog. `SkillsTool.make` defaults the predicate to `isModelVisible`, so the
model surface is the model-visible catalog; `SkillsCLI` supplies the user-surface predicate
-- id membership in `registry.commandListing()` -- so the same ops present the user-facing
surface to the CLI. See README "Visibility".)*

| op | parameters | behavior |
|---|---|---|
| `list resource` | `id` (req) | Enumerates every regular file under the skill's directory except `SKILL.md` — relative path, kind (`script`/`reference`/`asset` from the top-level folder, else `other`), byte size, executable bit — sorted by path, **capped at 100 rows** with `total` reporting the real count (the client guide's cap rule). Hidden files and symlinks resolving outside the skill are skipped. Unknown/model-hidden `id` → corrective message carrying the current id list (#22). |
| `read resource` | `id` (req), `path` (req, skill-relative), `start?` (line, default 1), `end?` (default `start`+499) | Returns the file **verbatim** — resources never pass through the §5 pipeline (no `$args`, no shell, no Stencil). At most **500 lines per call**; `totalLines` tells the model to page via `start`/`end`. **Path confinement:** the path, symlinks resolved, must land inside the skill directory — `..`, absolute paths, and escaping symlinks → corrective message. Non-UTF-8 content → corrective message with the byte size (binary assets are for hosts, not transcripts). |
| `run script` | `id` (req), `path` (req, under `scripts/`), `arguments?` (positional strings), `timeout?` secs (default 60) | Triple gate (§7.3.1) → **exec the file directly** — it must carry the executable bit and a shebang; no interpreter guessing (not executable → corrective naming the fix) — in its **own process group**, cwd = the skill directory, env inherited (parity with §5 shell injection); SIGKILL the group on timeout. Reports status (`completed` / `timed_out` / `failed`), exit code, duration, total captured lines, and the **last-32-line tail** of merged stdout+stderr — the Shelltool result shape. |

**Typed outputs** (same `Output: Encodable` contract as §7):

```swift
struct ResourceRow: Encodable { let path: String; let kind: String; let bytes: Int; let executable: Bool }
struct ListResourceResult: Encodable { let id: String; let resources: [ResourceRow]; let total: Int }
struct ReadResourceResult: Encodable {
  let id: String; let path: String
  let content: String               // verbatim slice — never rendered
  let start: Int; let end: Int; let totalLines: Int
}
struct RunScriptResult: Encodable {
  let id: String; let path: String
  let status: String                // completed | timed_out | failed
  let exitCode: Int?; let durationMs: Int
  let lines: Int                    // total captured (stdout + stderr)
  let output: [String]              // "{n}: {text}" tail, ≤ 32 entries
}
```

#### 7.3.1 Script execution gates & the sandbox posture

`run script` is **triple-gated**, every check at dispatch:

1. **Host policy** — `disableScriptExecution`, set at **registry construction** beside
   `disableShellExecution` (#25), so the model, `/command`, and CLI paths all honor it.
2. **Per-skill grant** — the skill's `allowed-tools` must contain a **`Script(<glob>)`**
   grant matching the requested path (`Script(scripts/*)`; bare `Script` = everything
   under `scripts/`). The spec marks `allowed-tools` experimental with client-defined
   tokens, so `Script(...)` is ours to define; a skill without a grant draws a
   corrective message saying it has not pre-approved script execution.
   `list resource` / `read resource` are passive reads and **ungated**.
3. **Trust** — the §8 trusted-root guidance: hosts should not construct a
   script-enabled registry over an untrusted project root at all.

**Sandbox posture (v1): contain by gates + process control, not by OS sandbox.**
Scripts run as ordinary child processes with the host's privileges — the same trust
model as §5 shell injection, stated with §8's honesty. Rationale: `sandbox-exec` is
deprecated API over a private profile language; an App-Sandboxed host already confines
its children structurally; a CLI host wanting OS-level confinement can wrap the whole
process. Documented consequences, not hidden ones: no filesystem-write restriction
beyond the cwd discipline, no network restriction, full env inheritance (parity with
body shell — scrubbing scripts while `` !`env` `` runs unscrubbed would be theater).
Revisit when Apple ships a supported per-process confinement API. *(decision #28)*

## 8. Platform & security
- **macOS primary** (on-device): full feature set — args, shell injection, env, scripts.
- **iOS: graceful "unavailable on platform"** stub; no shell/script attempted.
- **Untrusted layers render untrusted** *(#29)*: user/project-layer skills take Extras'
  untrusted Stencil path (tag/filter whitelist; include-depth, output-size, and
  iteration budgets); only shipped defaults render trusted. This bounds the *template*
  pass only — shell injection (§5) and scripts (§7.3.1) are separately gated and never
  granted by Stencil.
- **No cache concern** — render-once at list/use; fixed in transcript.
- **Server-side providers see the transcript** — with all env exposed and shell output inlined,
  a rendered skill can carry that off-device if a session routes to a cloud provider.
  Documented; accepted for the on-device-Mac use case. (The search agent sees only metadata,
  not rendered bodies, which limits exposure during discovery.)
- **Trust-gate untrusted project layers** (client-guide recommendation): a project
  `.skills/` from a freshly cloned repo can inject instructions; hosts should load it only
  for trusted folders. The stack's `workingDirectory` is caller-supplied (§4), so the gate
  is the host's — we document it, the Stencil pass already renders such layers untrusted
  (#29), and the diagnostic surface carries the winning layer's provenance so a host can
  show *where* a skill came from.
- **Context-compaction note for hosts:** a used skill's rendered body is durable guidance;
  hosts that summarize or prune transcripts should exempt skill tool outputs (client guide
  step 5). Out of scope for this package; stated so hosts don't silently degrade skills.

## 9. Resolved decisions
1. **Template engine → Stencil, via Extras' `TemplateEngine` facade** (`{{ }}` +
   `{% include %}`; no direct Stencil dependency — the facade owns trust, budgets, and
   `_partials/` resolution). *(Amended by #29.)*
2. **Env → all** of `ProcessInfo.environment` — as **flat keys through Extras'
   precedence ladder** (`{{ HOME }}`; explicit context > env > well-known values), not an
   `env.*` namespace. *(Amended by #29.)*
3. **Override → full replace** (higher layer shadows lower entirely) — realized by the
   stack's layer precedence: nearest wins *(#29)*.
4. **FM integration → a fused `OperationTool`** from `FoundationModelsOperations` on core
   `FoundationModels.Tool`; no `FoundationModelsUtilities` dependency. *(Supersedes the
   bespoke single `SkillsTool`.)*
5. ~~`partial:` → accept both, top-level canonical~~ **Superseded by #29:** partials are
   `_partials/*.md` files in the stack, not skills; `partial: true` frontmatter is
   retired (diagnostic + hidden from every surface). #27's top-level-canonical rule still
   governs the remaining extension fields.
6. **Arguments → Claude-compatible** (`$ARGUMENTS`, `$ARGUMENTS[N]`/`$N` 0-based, `$name`,
   `argument-hint:`).
7. **Architecture → 4 layers**; the generic lower two (`DotfolderStack`,
   `FrontmatterDocument`, `TemplateEngine`) **imported from `FoundationModelsExtras`**
   rather than built here; `../FoundationModelsAgents` consumes them from Extras directly
   (see #17, #19, #29).
8. **Identity → directory name canonical**; agentskills.io `name` required and validated `== id`.
9. **Visibility → `user-invocable` + `disable-model-invocation`**; two listing
   surfaces (command vs model). *(The `partial` axis is retired by #29 — partials are
   `_partials/` files, outside discovery entirely.)*
10. **Parameters → infer from body** when frontmatter is absent; frontmatter refines.
11. **FM entry point → one fused tool** with ops **`search skill` / `list skill` /
    `use skill`**. *(Restates the old search/list/call actions in operation vocabulary.)*
12. **Discovery → `SkillSearchAgent`**, so the root session is not clogged with skill
    metadata; only a chosen skill's body enters the root. *(Amended by #26: no longer a
    bespoke session — a thin wrapper over `MetadataSearcher<SkillMetadata>`.)*
13. **Source of truth → `SkillsRegistry`**: reloadable; publishes an initial + injectable
    refreshed metadata list; generic `call(id:arguments:)`.
14. **Preload → `preload: true`** skills' rendered bodies injected into the root session at
    startup (and refreshed on reload).
15. ~~Builder~~ **Superseded by #20:** assembly is `OperationTool` init + `SkillsToolContext`
    construction; action set = the operation structs passed in.
16. **Partials → `_partials/*.md` files, Stencil include semantics** *(amended by #29)*:
    an included partial renders inside the parent's Stencil pass; `$`-argument
    substitution (§5 pass 1) runs before Stencil and never reaches partial files, so
    partials stay shared, arg-free building blocks.
17. **Packaging → single SwiftPM target.** Layering (§3) is conceptual — by type, not module
    — so FoundationModels is a dependency of the whole package. *(Superseded in part:)*
    `AgentRegistry` does **not** live in this target — it lives in the downstream
    `../FoundationModelsAgents` package. *(Amended by #29:)* this package **exports no
    generic layers** — the substrate (`DotfolderStack`, `FrontmatterDocument`,
    `TemplateEngine`) is `FoundationModelsExtras`' contract, and Agents depends on
    Extras, not on us. **Reaffirmed after #26:** the single target stands — the whole
    package carries the `FoundationModelsMetadataRegistry` → `FoundationModelsRouter`
    dependency and its macOS 27+ floor (Extras shares that floor). No lightweight split
    for downstream consumers; `../FoundationModelsAgents` requires the Router directly
    anyway.
18. ~~Tool arg schema → dynamic id enum~~ **Superseded by #22:** the fused schema is
    upstream's flat union (required `op` enum + optional fields); the skill `id` is a plain
    string validated at dispatch. Rationale: hot-reload safety + Apple's enum-enforcement
    bug (forums 812501/811620) means guided id sampling was never guaranteed anyway.
19. ~~Entry shapes → `FolderStack` supports both~~ **Superseded by #29:** there is no
    `FolderStack`. **Directory-shaped** discovery (`name/SKILL.md`, id = directory name)
    is skill-local, built in Layer 3 over the host-supplied roots (#29); the **file-shaped**
    flat layout is Extras' `enumerate(_:suffix:)`. `../FoundationModelsAgents` builds its
    `AgentRegistry` on Extras directly — its M1–M2 no longer depend on our M1.
20. **Operation pattern → depend on `FoundationModelsOperations`** (SwiftPM). Our three ops
    can hand-conform `OperationDefinition` (upstream's manual path) — the `@Operation` macro
    is optional for so small a vocabulary. We inherit schema fusion, the forgiving resolver,
    return-don't-throw corrective errors, the retry cap, `includesSchemaInInstructions`, and
    the CLI driver. Upstream tasks 2/4/5/6 are prerequisites for our M4.
21. **Vocabulary → noun `skill`, verbs `search` / `list` / `use`.** Aliases:
    `find/discover → search`; `call/invoke/get → use`; reversed/`_`-`-` tolerated by the
    resolver. **`run` is not a `use` alias** — reserved for the M6 `run script` operation
    (upstream's verb rewrite is unconditional per-verb, not per-noun; a `run → use` entry
    would collide with `run script`). **Plural nouns do not resolve** — upstream's resolver
    compares the noun token literally, with no singularization; `skills list` stays
    `Unknown operation`. *(Amended: originally read "call/run/invoke/get → use;
    plural/reversed/`_`-`-` tolerated," which overstated what the shipped resolver does —
    `run` and noun pluralization were never actually reachable; see `SkillsTool.swift`'s
    `verbAliasOverrides` and `SkillOperationsTests`' resolver-matrix pins.)* **Skills are
    rows, not operations** — never one op per skill id.
22. **Skill id → plain string + dispatch validation.** Unknown/stale/model-hidden id returns
    a corrective message listing current ids (upstream pattern); retry cap stops loops.
23. **Resource nouns specified in §7.3, built at M6.** `list resource` / `read resource` /
    `run script` join the fused tool — six ops, within upstream's 5–15 guidance;
    partition into a second `OperationTool` only if the vocabulary grows further.
    *(Amended: originally vocabulary-only; now specified to full fidelity — parameters,
    typed outputs, correctives, gates — ahead of the M6 build.)*
24. **CLI → yes, via `OperationCLIDriver`** (§7.2); same payload as the model path,
    user-surface visibility rules.
25. **Shell injection → body only, re-executed per render.** `` !`command` `` runs fresh on
    every `use skill` / `/command` / CLI render (output then fixed in the transcript);
    `description`/`metadata` never execute shell (they render at metadata-build/reload time).
    `disableShellExecution` is set at **registry** construction so every render path honors
    it — model, user-driven, and CLI alike.
26. **Search → depend on `FoundationModelsMetadataRegistry`.** `SkillSearchAgent` is a thin
    wrapper over `MetadataSearcher<SkillMetadata>`: hybrid retrieval (BM25 + trigram +
    cosine → RRF), Router-backed selection session (fork-per-call prefix reuse, ids-only
    output xgrammar-constrained to the current id enum), verbatim block lookup, and
    `update(items:)` on registry reload. Consequence: the package depends on
    `FoundationModelsRouter` (macOS 27+) — accepted **package-wide** (#17; no target
    split). Layers 1–3 use only core Apple FoundationModels *API*, but they ship in the
    same target and share the floor. Supersedes the Spotlight-RAG backend idea
    in #12; note #22's dispatch-side rationale is unchanged (Apple's enum bug is about the
    *root* session's tool schema — the *search* session runs on Router, where xgrammar
    enum enforcement is real).
27. **agentskills.io compliance posture** (§4, §7.1, §8). Full spec field coverage:
    `name` + `description` required with the spec's exact limits; `license`,
    `compatibility`, `metadata`, and `allowed-tools` parsed (data until consumed).
    **Lenient validation** per the spec's client-implementation guide: name
    irregularities → warn + load; unparseable YAML → skip after a colon-quoting retry;
    missing/empty `description` → excluded from the model surface (kept user-invocable —
    our one deliberate softening of the guide's skip rule); shadowing and >500-line
    advisories; parity target `skills-ref validate`. Extension fields accepted top-level
    **and** under `metadata.*` (the portable spelling — generalizes #5). One documented
    divergence: no standing tier-1 catalog in the root session — `search skill` /
    `list skill` are the disclosure surface, and hosts can inline `registry.metadata()`
    for guide-standard behavior (§7.1).
28. **Script execution → triple gate, no OS sandbox in v1** (§7.3.1). Registry-level
    `disableScriptExecution` (mirrors #25); per-skill **`Script(<glob>)`** grants in
    `allowed-tools` (our token — the field is experimental and client-defined); the §8
    trusted-root guidance. Direct exec of executable+shebang files only (no interpreter
    guessing), own process group, cwd = skill directory, env inherited (parity with §5
    shell — scrubbing scripts while `` !`env` `` runs unscrubbed would be theater),
    default 60 s timeout, Shelltool-shaped result with a 32-line tail. `sandbox-exec`
    is deprecated over a private profile language, so containment is gates + process
    control, documented honestly; revisit when Apple ships a supported per-process
    confinement API. Path confinement (resolved-inside-the-skill-directory) applies to
    all three resource ops.
29. **Loading substrate → `FoundationModelsExtras`. The host supplies the roots.**
    *(Amended 2026-07-28 at `FoundationModelsACPAgent`'s request — see its plan §6.2.1.)*
    **The registry takes its layer roots as a construction parameter** — an ordered list,
    lowest precedence first — and holds no opinion about where skills live. It does not
    name `.skills`, `~`, `.config`, or any dotfolder convention; those are host policy,
    and a package that hardcodes them cannot serve a host that disagrees.

    `DotfolderStack(name: "skills", workingDirectory: …)` remains a **convenience for
    hosts that want it**, deriving shipped defaults (optional; `SKILLS_DEFAULTS_DIR`
    repoints it for dev, no rebuild) < user `$XDG_CONFIG_HOME/skills/` (default
    `~/.config/skills/`) < project `<cwd>/.skills/`. But it is one way to compute roots,
    not the interface — a host with a different layout passes different roots without
    needing this package changed.

    `FoundationModelsACPAgent` passes the roots from `DotfolderStack(name: "skills")`,
    i.e. `$XDG_CONFIG_HOME/skills/` (default `~/.config/skills/`) and `<cwd>/.skills/`.
    Its reasoning is worth recording here because it generalizes: **`skills` is a fixed
    stack name, not that agent's configurable `<name>`.** Skills are an **ecosystem**
    artifact — a "deploy to staging" skill belongs to the user and the repo, not to
    whichever agent reads it — so pinning the name to `skills` gives cross-product
    sharing, where namespacing under a per-product name would force one copy per
    product. No divergence from XDG is involved or needed.

    Either way: nearest-wins realizing full-replace (#3), source tracking carrying
    provenance, path safety built in. `FrontmatterDocument.split` does the textual frontmatter split
    (YAML decoding stays ours, with Yams, per Extras' no-YAML rule); `TemplateEngine` is
    the Stencil facade with the layer→trust mapping (defaults trusted; user/project
    untrusted) and `_partials/` includes. Extras ships **no watcher and no
    directory-shaped discovery** — both stay in Layer 3 (§3). Hosts wanting the client
    guide's `.agents/skills` layout construct the stack's `Layer`s explicitly. The §6
    user surface additionally conforms to Extras' `SlashCommandProviding` (commands from
    `commandListing()`, `commandUpdates` from reload); `.prompt(template:)`'s inability
    to run §5 passes 1–2 is a recorded Extras coordination item — **now filed as Extras
    `c2pad49`**, asking for a body case that lets a provider render and still take a model
    turn (`FoundationModelsACPAgent` plan §6.3 has the full analysis). Amends #1, #2, #3, #5,
    #7, #16, #17, #19 in place.

**All open items resolved — the plan is decision-complete.**

## 10. Public API sketch (illustrative)

```swift
// Roots are the host's choice (#29). The usual way to compute them — and what
// FoundationModelsACPAgent passes — is a `skills` dotfolder stack:
let stack = DotfolderStack(
  name: "skills",                                // ~/.config/skills/ + <cwd>/.skills/
  workingDirectory: cwd,
  defaultsDirectory: shippedSkillsURL            // optional lowest layer; SKILLS_DEFAULTS_DIR overrides
)

// Layer 3 — reloadable registry over the stack:
let registry = try SkillsRegistry(
  stack: stack,                                  // nearest-wins = full-replace by id (#3)
  policy: .init(disableShellExecution: false),   // render policy lives with the pipeline (#25)
  watch: true                                    // watch every layer root; reload add/remove/edit
)

// Layer 4 — three ops over one context, fused into one core Tool:
let context = SkillsToolContext(
  registry: registry,
  searchAgent: SkillSearchAgent(                 // thin wrapper over MetadataSearcher (#26)
    searcher: MetadataSearcher(
      items: registry.metadata().filter(\.isModelVisible),
      selection: .init(model: profile.flash),    // FoundationModelsRouter
      embedder: RoutedEmbedderAdapter(profile.embedding),
      mode: .auto))
)
let skillsTool = OperationTool(
  name: "skills",
  description: "Search, list, and use skills from the local skill library",
  context: context,
  operations: [AnyOperation(SearchSkill.self),   // op: "search skill"
               AnyOperation(ListSkill.self),     // op: "list skill"
               AnyOperation(UseSkill.self)]      // op: "use skill"
)

// Lean root session: one tool + preloaded bodies, NO full catalog inline:
let root = LanguageModelSession(
  tools: [skillsTool],
  instructions: Instructions {
    "…base instructions…"
    registry.preloadedBodies()         // preload: true skills, rendered
  }
)

// Reload: forward metadata to the searcher's update(items:); refresh preloaded bodies;
// the fused tool's schema is id-free and its ops dereference the live registry per dispatch.
registry.onReload { meta in context.searchAgent.update(items: meta) /* + refresh preload */ }

// User-facing command matching (independent of the session):
for skill in registry.commandListing() { /* skill.id, .description, .parameters */ }

// Dual-use CLI from the SAME declarations:
let cli = OperationCLIDriver(tool: skillsTool)
try await cli.run(CommandLine.arguments)  // skills skill use --id deploy --arguments production
```

## 11. Examples (`./Examples`)

Mirrors upstream `FoundationModelsOperations`' `Examples/NotesTool` pattern: a runnable,
dual-use demo plus a **fixture skill library that doubles as test data**, so docs and
tests can't drift. `skills-demo` is an **executable target in the root `Package.swift`**
— not a nested example package — so one `swift build` covers library and demo alike
(matches the Agents plan's §13 convention).

```
Examples/
  skill-library/                    # a three-layer .skills dotfolder stack (#29)
    defaults/base-style/SKILL.md        # plain skill — shadowed by the user layer below
    user/base-style/SKILL.md            # the full-replace override that wins (#3)
    user/_partials/header.md            # an {% include "header" %} target — a file, not a skill (#29)
    project/.skills/commit/SKILL.md     # arguments: + argument-hint: + $0/$ARGUMENTS (§5, §6.1)
    project/.skills/deploy/SKILL.md     # disable-model-invocation: true — user-only /deploy
    project/.skills/git-context/SKILL.md  # preload: true + !`git status` shell injection (#25)
    project/.skills/env-report/SKILL.md   # {{ HOME }} / {{ working_directory }} ladder rendering
    project/.skills/lint/SKILL.md         # user-invocable: false — model-only background
    project/.skills/spec-clean/SKILL.md   # pure-spec frontmatter: license + compatibility +
                                          #   extensions under metadata.* — passes skills-ref (#27)
    project/.skills/release-notes/        # §7.3 resource fixtures (M6): scripts/ + references/
                                          #   + assets/; allowed-tools: "Script(scripts/*)"
  skills-demo/                      # one executable target, dual-use
```

- **`skill-library/`** exercises every §5–§6 feature exactly once — layer override,
  `_partials/` include, arguments + hint, shell injection, env templating, preload, and
  both visibility axes. The demo and tests build the stack with explicit
  `defaultsDirectory`/`userDirectory` fixture URLs (Extras' hermetic seam), so nothing
  ever reads the real home directory. The unit tests load it for golden renders and
  listing snapshots; the demo loads the same directories, so the documented behavior is
  the tested behavior.
- **`skills-demo`** is one binary, three modes (the NotesTool dual-use shape):
  - **default — CLI** (§7.2) over the library: `skills-demo skill list`,
    `skills-demo skill search "commit my changes"`,
    `skills-demo skill use --id commit --arguments "fix parser"`.
  - **`--chat`** — a root `LanguageModelSession` with the fused tool + preloaded
    bodies (gated on model availability); scripted prompts drive the
    `search skill` → `use skill` round trip end to end.
  - **`--watch`** — edit a file under `project/` while running and watch the registry
    reload propagate: searcher `update(items:)`, refreshed preloads, updated `/`
    listing — live.
- The example grows with the milestones — fixtures land at M1 (as test data), watch at
  M2, chat at M4, CLI at M4.5, the full-render fixture skills at M5 — and M7 polishes
  it into the documented sample.

## 12. Phasing
- **M1 — Substrate + discovery.** Depend on `FoundationModelsExtras` (#29); build
  directory-shaped skill discovery over **the roots the host supplies** (#29 — an
  ordered list, lowest precedence first; `DotfolderStack.layers` is one way to produce
  them, not the interface) (`name/SKILL.md`,
  full-replace by directory name, provenance from source tracking); Yams decode over
  `FrontmatterDocument.split`. No templating, watch, or FM. *(`FoundationModelsAgents`
  consumes Extras directly and is no longer blocked on us.)*
- **M2 — Watch + render skeleton.** File watcher over every stack layer root (Extras
  ships none, #29); render pipeline scaffold (passes wired, identity transforms).
- **M3 — `SkillsRegistry`.** agentskills.io + Claude validation — full spec field
  coverage and the lenient rules (#27), `skills-ref` parity check — visibility (including
  the `partial: true` retirement diagnostic, #29), `preload`, `commandListing()`, initial
  + injectable metadata, generic `call`.
- **M4 — Skill operations + search agent.** `SearchSkill`/`ListSkill`/`UseSkill` conforming
  to `OperationDefinition`; fuse via `OperationTool`; `SkillSearchAgent` as a
  `MetadataSearcher` wrapper (#26); preload injection; reload → `update(items:)` — with
  the **explicit hot-reload test case (§13)** as an acceptance criterion, not a follow-up.
  *(Depends on `FoundationModelsOperations` tasks 2/4/5 — protocol, schema fusion,
  dispatch/resolver — and `FoundationModelsMetadataRegistry` M1–M4.)*
- **M4.5 — CLI.** Wire `OperationCLIDriver` over the same ops (§7.2); round-trip payload
  test against the resolver. *(Depends on upstream task 6.)*
- **M5 — Full render.** Arguments, shell injection (macOS), Extras `TemplateEngine`
  wiring — the layer→trust mapping, precedence-ladder variables, `_partials/` includes
  (recursion bounded by the untrusted include-depth budget).
- **M6 — Resource ops.** Build §7.3 as specified: `list resource` / `read resource` /
  `run script` in the fused tool; path-confinement invariant, `Script(<glob>)` grants,
  `disableScriptExecution`, direct-exec runner (process group, cwd = skill dir, timeout).
  *(Vocabulary and semantics already fixed — §7.3, decisions #23/#28.)*
- **M7 — Diagnostics polish + docs; finish the §11 `Examples/` demo** (all three
  `skills-demo` modes against the complete `skill-library/`). *(Superseded:
  `AgentRegistry` moved to `../FoundationModelsAgents` — see decision #17; it consumes
  Extras' substrate directly, #29.)*

## 13. Testing

The unit tier is GPU-free: parsing/validation tables (§4's spec limits and lenient
rules), golden renders and listing snapshots over the §11 fixture library — rendered
through Extras' **real `TemplateEngine`**, never a mock, including a trust case where a
project-layer skill using a non-whitelisted Stencil tag draws the untrusted-rejection
diagnostic (#29) — watcher tests against temp directory stacks, and operation dispatch
against a stub context. M6 adds
the §7.3 cases: **path confinement** (`..`, absolute paths, escaping symlinks — all
corrective), the **three-gate matrix** for `run script` (policy off / no grant /
non-matching glob / granted), exec-bit + shebang refusals, timeout → process-group
SIGKILL, and golden `RunScriptResult` tails against the `release-notes` fixture.

**Hot reload is an explicit, named test case — not incidental coverage.** Because
`FoundationModelsMetadataRegistry` is a **shipped sibling dependency** (checked out at
`../FoundationModelsMetadataRegistry`), the reload tests drive a **real
`MetadataSearcher`** wired through `SkillSearchAgent` — never a mock of the searcher
itself, so the contract we depend on is the contract we test. GPU-free comes from the
sibling's **public seams**: we conform tiny doubles to `TextEmbedding` (a counting fake)
and `AgentSession` (scripted responses), the same pattern as its own `FakeEmbedder` /
`ScriptedAgentSession` — which live in its test target and are not importable, so we
replicate them (~a dozen lines each). The case, end to end over a temp root:

1. **Add** a `SKILL.md` → watcher fires → registry rebuilds → exactly one
   `update(items:)` reaches the searcher; the new id is **immediately** searchable
   keyword-only, with the cosine signal catching up asynchronously — observed as
   `.embedCatchUp(pending:total:)` on the searcher's `onDiagnostic` channel.
2. **Edit** a body → hash-guarded incremental re-embed: only the changed item re-embeds
   (a counting `FakeEmbedder` asserts it); a **no-op touch** produces no re-embed at all.
3. **Remove** a skill → its id disappears from `search skill` / `list skill` results, and
   a stale `use skill` for it draws the corrective message carrying the current id list
   (#22).
4. **Visibility flips on reload** (e.g. adding `disable-model-invocation: true`) →
   the model-visible subset forwarded to `update(items:)` shrinks accordingly.
5. **Preload + listing refresh** — `preloadedBodies()` and `commandListing()` both
   reflect the change; the fused tool's schema is untouched throughout (id-free, §7).

The `--watch` demo mode (§11) is the human-driven twin of this test. A separate gated
integration case (the Router/MetadataRegistry tiny-model pattern) runs the same
add/remove burst against a live selection session, asserting the rebuilt candidate set
after reload.

---

### Sources
- agentskills.io specification — https://agentskills.io/specification
- agentskills.io client-implementation guide (lenient validation, disclosure tiers, `.agents/skills` convention, trust) — https://agentskills.io/client-implementation/adding-skills-support
- skills-ref reference validator — https://github.com/agentskills/agentskills/tree/main/skills-ref
- FoundationModelsOperationTool plan (upstream operation pattern) — https://github.com/swissarmyhammer/FoundationModelsOperationTool
- FoundationModelsExtras plan (substrate: DotfolderStack, TemplateEngine, SlashCommandProviding, #29) — ../FoundationModelsExtras/plan.md
- FoundationModelsAgents plan (downstream consumer) — ../FoundationModelsAgents/plan.md
- FoundationModelsMetadataRegistry plan (search: retrieval + selection, #26) — ../FoundationModelsMetadataRegistry/plan.md
- Claude Code skills & slash-command arguments — https://code.claude.com/docs/en/slash-commands
- What's new in Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/241/
- Build agentic app experiences with Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/242/
- apple/foundation-models-utilities — https://github.com/apple/foundation-models-utilities
