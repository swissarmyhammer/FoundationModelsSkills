# Plan: agentskills.io → Foundation Models Skills bridge

A Swift package that loads [agentskills.io](https://agentskills.io/specification) /
[Claude-style](https://code.claude.com/docs/en/slash-commands) skill directories from disk
and exposes them to Apple's
[Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
(WWDC26) through **one fused operation tool** — built on the
[`FoundationModelsOperations`](https://github.com/swissarmyhammer/FoundationModelsOperationTool)
package (the sah "operation" pattern: `op: "verb noun"` dispatch, forgiving resolver,
dual-use CLI) — plus a separate listing surface for command/`/`-matching. Built on a
generic, reusable stacked-folder layer. **Primary target: macOS, on-device.**

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
- **Generic stack underneath, domain validation on top.** The folder-stacking machinery
  (override, render, list, watch) knows nothing about skills, so the **same stack also serves
  agents** — the downstream [`../FoundationModelsAgents`](../FoundationModelsAgents/plan.md)
  package depends on this one and builds its `AgentRegistry` on these layers. Skill
  validation sits a layer above it.
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

Four layers, bottom to top. Lower layers are domain-agnostic and reusable.

```
┌─ Layer 4  FM adapter (skills) ─────────────────────────────────────────────┐
│   Skill operations — SearchSkill / ListSkill / UseSkill structs fused by   │
│   FoundationModelsOperations.OperationTool into ONE core Tool              │
│   SkillSearchAgent — MetadataSearcher over skill metadata (#26, separate   │
│   Router session + rank-fusion retrieval; never the root session)          │
│   preload injection (rendered bodies → root Instructions)                  │
│   commandListing() — user `/` menu view (separate from the model surface)  │
│   OperationCLIDriver — dual-use CLI from the same op declarations          │
├─ Layer 3  SkillsRegistry  (domain validation + semantics) ──────────────────┤
│   agentskills.io + Claude validation, visibility, arguments, partial,       │
│   reload → injectable metadata, generic call(id:arguments:) — built ON L2   │
├─ Layer 2  FolderStack  (generic, reusable) ─────────────────────────────────┤
│   ordered roots; named entries; FULL-REPLACE override by name; render       │
│   pipeline; list(); entry(name:); file-watch add/remove/reload up the stack │
│   Generic over an EntryKind — dir-shaped (skill) or file-shaped (agent)     │
├─ Layer 1  FrontmatterDocument  (generic) ───────────────────────────────────┤
│   parse one .md → (YAML frontmatter, markdown body); serialize back         │
└──────────────────────────────────────────────────────────────────────────┘
```

- **`FrontmatterDocument`** — pure parse/serialize of a single markdown file into typed
  frontmatter + body. No domain knowledge.
- **`FolderStack`** — the "stack of folders of named folders of markdown+frontmatter":
  ordered roots (low→high precedence), discovery of named entries, **full-replace override by
  name** up the stack, the **render pipeline**, `list()`/`entry(name:)`, and a **file watcher**
  that applies add/remove/reload across every layer. Generic over an `EntryKind` so it hosts
  skills *or* agents — and the `EntryKind` decides the **entry shape**: **directory-shaped**
  (`name/SKILL.md`, id = directory name) or **file-shaped** (a flat `*.md` discovered
  recursively, id from frontmatter `name` — the Claude agents layout).
  `FrontmatterDocument` and `FolderStack` are **exported public API**, not internal
  machinery: `../FoundationModelsAgents` imports them for its `AgentRegistry`.
- **`SkillsRegistry`** (Layer 3, the source of truth) — wraps a `FolderStack<Skill>`; adds
  agentskills.io + Claude validation, the visibility model (§6), argument handling (§5),
  `partial`/include semantics, and **reload → injectable metadata** (§7). Exposes a generic
  `call(id:arguments:)`. **Skill validation is strictly above the raw stack.**
- **FM adapter** (Layer 4) — the skill operation structs and their fused `OperationTool`,
  the `SkillSearchAgent`, preload injection, the `commandListing()`, and the CLI driver —
  all reading the registry.

## 4. Identity & naming

- **Directory name = canonical id.** It is the key for stack override, `{% include %}`
  partials, `/name` command matching, and the `use skill` op's `id` — never the frontmatter
  `name`.
- **agentskills.io requires `name`, and it must equal the directory name.** Enforced rules:
  1–64 chars, `[a-z0-9-]` only, no leading/trailing hyphen, no consecutive `--`,
  `name == directoryName`.
- **Claude-style inputs may omit `name`** (a `.claude/commands/foo.md` or a `SKILL.md` without
  `name` defaults to the dir/file name), so `SkillListing.displayName` is optional only for
  those inputs.

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
3. **Stencil** — `{{ env.* }}` (all of `ProcessInfo.environment`) + `{% include "other-skill" %}`
   partials resolved against the merged registry (including `partial:` skills), rendered
   recursively with **cycle detection**.

Templated: `description`, all `metadata` values, and the body. The **directory-name id stays
literal**. Argument frontmatter: `arguments:` (named positional list) + `argument-hint:`
(autocomplete hint), both surfaced in the listing.

**Resolved (re-scanning):** passes are ordered and single-shot; injected shell output is
**never** re-scanned. **Resolved (partials):** an `{% include %}`d partial renders **standalone**
through its own pipeline — env + its own `$`-tokens, but **not** the parent's arguments
(partials are shared, arg-free building blocks). *(decision #16)*

## 6. Visibility model & the two listing surfaces

Adopt Claude's two axes, plus our `partial` and `preload`:

| Field | User `/` menu | Model surface | In context at startup | Notes |
|---|---|---|---|---|
| *(default)* | listed | searchable + usable | no (body on use) | both audiences |
| `disable-model-invocation: true` | listed | hidden | no | user-only command (e.g. `/deploy`) |
| `user-invocable: false` | hidden | searchable + usable | no | model-only background |
| `partial: true` *(ours)* | hidden | hidden | no | `{% include %}` target only; never callable |
| `preload: true` *(ours)* | listed | searchable + usable | **yes** (body injected) | body always-on in Instructions; re-use is redundant; see §7 |

- **`SkillsRegistry.commandListing()`** → `[SkillListing]` for the user `/` menu, carrying
  **structured, parsed parameters** (§6.1). **We produce data only** — autocomplete, fuzzy
  search, and input validation are the UI's job, out of scope here.
- `partial:` accepts **top-level canonical** else `metadata.partial: "true"`.
- "Model surface" filtering is applied by the operation implementations: `search skill` /
  `list skill` exclude model-hidden skills; `use skill` refuses them with a corrective
  message.

### 6.1 Parsed parameter model

```swift
struct SkillListing {
  let id: String                  // directory name = the /command
  let displayName: String?        // frontmatter `name`
  let description: String?        // rendered, truncated for the menu
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
  variadic).
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
| `search skill` | `query`, `limit?` | delegates to the **`SkillSearchAgent`** and returns ranked matches (id + description + parsed params). Primary discovery path; keeps the root context lean because the catalog lives in the search agent, not the root. |
| `list skill` | `filter?` | returns the catalog (full or filtered) on demand, for small sets or explicit enumeration. |
| `use skill` | `id`, `arguments?` | renders the chosen skill (pipeline §5) and returns its body as tool output. Dereferences the **live registry at dispatch time**. |

- **Noun is singular `skill`**; the forgiving resolver tolerates plurals, reversed order
  (`skill list`), and `_`/`-` separators. Verb aliases ride the shared resolver table:
  `find/discover → search`, `call/run/invoke/get → use`. *(decisions #20–21)*
- **`id` is a plain string, validated at dispatch.** No dynamic id enum: skills hot-reload
  between turns, and Apple's enum-enforcement bug (forums 812501/811620) means the model can
  emit values outside an `anyOf` list anyway. An unknown/stale/model-hidden id returns a
  corrective message carrying the current id list; upstream's retry cap (default 2) stops
  loops. This **supersedes decision #18.** *(decision #22)*
- **M6 resources are future nouns, not parameters:** `list resource`, `read resource`,
  `run script` join the same fused tool (or a second `OperationTool` if the op count grows
  past upstream's 5–15 guidance). Vocabulary deferred to M6. *(decision #23)*

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

**Reload & metadata injection.** The `FolderStack` watcher fires on add/remove/edit up the
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
skills skill use deploy --arguments production
```

Help, did-you-mean, and shell completions come from stock ArgumentParser. The CLI respects
the same visibility rules as the user surface (it is a user, not a model).

## 8. Platform & security
- **macOS primary** (on-device): full feature set — args, shell injection, env, scripts.
- **iOS: graceful "unavailable on platform"** stub; no shell/script attempted.
- **No cache concern** — render-once at list/use; fixed in transcript.
- **Server-side providers see the transcript** — with all env exposed and shell output inlined,
  a rendered skill can carry that off-device if a session routes to a cloud provider.
  Documented; accepted for the on-device-Mac use case. (The search agent sees only metadata,
  not rendered bodies, which limits exposure during discovery.)

## 9. Resolved decisions
1. **Template engine → Stencil** (`{{ }}` + `{% include %}`).
2. **Env → all** of `ProcessInfo.environment` as `{{ env.* }}`.
3. **Override → full replace** (higher layer shadows lower entirely).
4. **FM integration → a fused `OperationTool`** from `FoundationModelsOperations` on core
   `FoundationModels.Tool`; no `FoundationModelsUtilities` dependency. *(Supersedes the
   bespoke single `SkillsTool`.)*
5. **`partial:` → accept both, top-level canonical.**
6. **Arguments → Claude-compatible** (`$ARGUMENTS`, `$ARGUMENTS[N]`/`$N` 0-based, `$name`,
   `argument-hint:`).
7. **Architecture → 4 layers**; generic `FrontmatterDocument` + `FolderStack` reused for
   agents by the downstream `../FoundationModelsAgents` package (see #17, #19).
8. **Identity → directory name canonical**; agentskills.io `name` required and validated `== id`.
9. **Visibility → `user-invocable` + `disable-model-invocation` + `partial`**; two listing
   surfaces (command vs model).
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
16. **Partials → render standalone** (env + own `$`-tokens; not the parent's arguments).
17. **Packaging → single SwiftPM target.** Layering (§3) is conceptual — by type, not module
    — so FoundationModels is a dependency of the whole package. *(Superseded in part:)*
    `AgentRegistry` does **not** live in this target — it lives in the downstream
    `../FoundationModelsAgents` package, which depends on this one. Layers 1–2
    (`FrontmatterDocument`, `FolderStack`) are therefore **exported public API**, part of
    this package's contract. **Reaffirmed after #26:** the single target stands — the
    whole package, exported Layers 1–2 included, carries the
    `FoundationModelsMetadataRegistry` → `FoundationModelsRouter` dependency and its
    macOS 27+ floor. No lightweight split for downstream consumers;
    `../FoundationModelsAgents` requires the Router directly anyway.
18. ~~Tool arg schema → dynamic id enum~~ **Superseded by #22:** the fused schema is
    upstream's flat union (required `op` enum + optional fields); the skill `id` is a plain
    string validated at dispatch. Rationale: hot-reload safety + Apple's enum-enforcement
    bug (forums 812501/811620) means guided id sampling was never guaranteed anyway.
19. **Entry shapes → `FolderStack` supports both.** A skill is a **directory-shaped** entry
    (`name/SKILL.md`, id = directory name); a Claude-style agent is a **file-shaped** entry
    (a flat `*.md` discovered recursively, id from frontmatter `name`). The `EntryKind`
    decides shape, discovery, and identity — required by `../FoundationModelsAgents`, whose
    M1–M2 depend on this landing in our M1.
20. **Operation pattern → depend on `FoundationModelsOperations`** (SwiftPM). Our three ops
    can hand-conform `OperationDefinition` (upstream's manual path) — the `@Operation` macro
    is optional for so small a vocabulary. We inherit schema fusion, the forgiving resolver,
    return-don't-throw corrective errors, the retry cap, `includesSchemaInInstructions`, and
    the CLI driver. Upstream tasks 2/4/5/6 are prerequisites for our M4.
21. **Vocabulary → noun `skill`, verbs `search` / `list` / `use`.** Aliases:
    `find/discover → search`; `call/run/invoke/get → use`; plural/reversed/`_`-`-` tolerated
    by the resolver. **Skills are rows, not operations** — never one op per skill id.
22. **Skill id → plain string + dispatch validation.** Unknown/stale/model-hidden id returns
    a corrective message listing current ids (upstream pattern); retry cap stops loops.
23. **Resource nouns deferred to M6.** `list resource` / `read resource` / `run script` join
    the fused tool then; partition into a second `OperationTool` only if the op count
    outgrows upstream's 5–15 guidance.
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

**All open items resolved — the plan is decision-complete.**

## 10. Public API sketch (illustrative)

```swift
// Layers 1–3 — generic stack + reloadable registry:
let registry = try SkillsRegistry(
  roots: [enterpriseURL, userURL, projectURL],   // low → high; full-replace by id
  env: .all,
  policy: .init(disableShellExecution: false),   // render policy lives with the pipeline (#25)
  watch: true                                    // reload add/remove/edit up the stack
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
try await cli.run(CommandLine.arguments)  // skills skill use deploy --arguments production
```

## 11. Examples (`./Examples`)

Mirrors upstream `FoundationModelsOperations`' `Examples/NotesTool` pattern: a runnable,
dual-use demo plus a **fixture skill library that doubles as test data**, so docs and
tests can't drift.

```
Examples/
  skill-library/                    # a three-root stack (enterprise → user → project)
    enterprise/base-style/SKILL.md      # plain skill — shadowed by the user root below
    user/base-style/SKILL.md            # the full-replace override that wins (#3)
    user/header/SKILL.md                # partial: true — an {% include "header" %} target
    project/commit/SKILL.md             # arguments: + argument-hint: + $0/$ARGUMENTS (§5, §6.1)
    project/deploy/SKILL.md             # disable-model-invocation: true — user-only /deploy
    project/git-context/SKILL.md        # preload: true + !`git status` shell injection (#25)
    project/env-report/SKILL.md         # {{ env.* }} Stencil rendering
    project/lint/SKILL.md               # user-invocable: false — model-only background
  skills-demo/                      # one executable target, dual-use
```

- **`skill-library/`** exercises every §5–§6 feature exactly once — stack override,
  partial + include, arguments + hint, shell injection, env templating, preload, and
  both visibility axes. The unit tests load it for golden renders and listing
  snapshots; the demo loads the same directories, so the documented behavior is the
  tested behavior.
- **`skills-demo`** is one binary, three modes (the NotesTool dual-use shape):
  - **default — CLI** (§7.2) over the library: `skills-demo skill list`,
    `skills-demo skill search "commit my changes"`,
    `skills-demo skill use commit --arguments "fix parser"`.
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
- **M1 — Layers 1–2.** `FrontmatterDocument`; `FolderStack` (discovery, full-replace override,
  provenance, `list()`/`entry()`, **both entry shapes** — directory- and file-shaped, #19),
  all public. No templating, watch, or FM. *(Unblocks `FoundationModelsAgents` M1–M2.)*
- **M2 — Watch + render skeleton.** File watcher (add/remove/reload up the stack); render
  pipeline scaffold (passes wired, identity transforms).
- **M3 — `SkillsRegistry`.** agentskills.io + Claude validation, visibility, `partial`,
  `preload`, `commandListing()`, initial + injectable metadata, generic `call`.
- **M4 — Skill operations + search agent.** `SearchSkill`/`ListSkill`/`UseSkill` conforming
  to `OperationDefinition`; fuse via `OperationTool`; `SkillSearchAgent` as a
  `MetadataSearcher` wrapper (#26); preload injection; reload → `update(items:)`.
  *(Depends on `FoundationModelsOperations` tasks 2/4/5 — protocol, schema fusion,
  dispatch/resolver — and `FoundationModelsMetadataRegistry` M1–M4.)*
- **M4.5 — CLI.** Wire `OperationCLIDriver` over the same ops (§7.2); round-trip payload
  test against the resolver. *(Depends on upstream task 6.)*
- **M5 — Full render.** Arguments, shell injection (macOS), Stencil env + `{% include %}`
  partials + cycle detection.
- **M6 — Lazy resource tools.** `references/`/`assets/`/`scripts/` as new nouns —
  `list resource` / `read resource` / `run script` — in the fused tool (or a second
  `OperationTool` per #23), gated by `allowed-tools`; macOS sandboxing.
- **M7 — Diagnostics polish + docs; finish the §11 `Examples/` demo** (all three
  `skills-demo` modes against the complete `skill-library/`). *(Superseded:
  `AgentRegistry` moved to `../FoundationModelsAgents` — see decision #17. Its M1–M2
  consume our public Layers 1–2.)*

---

### Sources
- agentskills.io specification — https://agentskills.io/specification
- FoundationModelsOperationTool plan (upstream operation pattern) — https://github.com/swissarmyhammer/FoundationModelsOperationTool
- FoundationModelsAgents plan (downstream consumer) — ../FoundationModelsAgents/plan.md
- FoundationModelsMetadataRegistry plan (search: retrieval + selection, #26) — ../FoundationModelsMetadataRegistry/plan.md
- Claude Code skills & slash-command arguments — https://code.claude.com/docs/en/slash-commands
- What's new in Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/241/
- Build agentic app experiences with Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/242/
- apple/foundation-models-utilities — https://github.com/apple/foundation-models-utilities
