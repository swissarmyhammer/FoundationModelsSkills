# Plan: agentskills.io → Foundation Models Skills bridge

A Swift package that loads [agentskills.io](https://agentskills.io/specification) /
[Claude-style](https://code.claude.com/docs/en/slash-commands) skill directories from disk
and exposes them to Apple's
[Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
(WWDC26) through **one tool** — plus a separate listing surface for command/`/`-matching.
Built on a generic, reusable stacked-folder layer. **Primary target: macOS, on-device.**

---

## 1. Guiding principles

- **A skill is just a tool — no special case.** In an FM session, skills are reached through
  one `FoundationModels.Tool` — `SkillsTool` (**search / list / call**). The framework has no
  skills concept; we add a *tool*, not a new primitive.
- **Keep the root session lean.** The full catalog is **not** dumped into the root context.
  Discovery is offloaded to a **separate search-agent session**; only an explicitly chosen
  skill's body (plus any preloaded skills) ever enters the root transcript. *(new)*
- **One registry, many consumers.** A reloadable **`SkillsRegistry`** is the source of truth;
  it powers the root `SkillsTool`, the search agent, the preload injection, and the
  user-facing `/` command listing — all *views* of one registry. *(new)*
- **Generic stack underneath, domain validation on top.** The folder-stacking machinery
  (override, render, list, watch) knows nothing about skills, so the **same stack also serves
  agents**. Skill validation sits a layer above it.
- **macOS-first, on-device.** iOS is a graceful "unavailable" stub.

## 2. Where "skills" actually live in Apple's stack (correction)

- The **core `FoundationModels` framework** (WWDC26) provides `LanguageModelSession`,
  `DynamicProfile`/`Profile`/`Instructions`, the **`Tool`** protocol, multimodal
  `Attachment`, context/token APIs, usage tracking, reasoning levels, server-side providers,
  and built-in tools (`OCRTool`, `BarcodeReaderTool`, Spotlight RAG). It has **no skills
  type**.
- The experimental **`FoundationModelsUtilities`** package ships a `Skills { … }` builder
  (the model activates a skill *by generating a tool call*). **We do not depend on it** — we
  roll our own tool on the core `Tool` protocol for full control over search, the call
  contract, arguments, preload, and reload.

## 3. Layered architecture

Four layers, bottom to top. Lower layers are domain-agnostic and reusable.

```
┌─ Layer 4  FM adapter (skills) ─────────────────────────────────────────────┐
│   SkillsTool — one core FoundationModels.Tool: search / list / call         │
│   SkillSearchAgent — a SEPARATE LanguageModelSession over skill metadata    │
│   preload injection (rendered bodies → root Instructions)                   │
│   commandListing() — user `/` menu view (separate from the model surface)   │
├─ Layer 3  SkillsRegistry  /  AgentRegistry  (domain validation + semantics) ┤
│   agentskills.io + Claude validation, visibility, arguments, partial,       │
│   reload → injectable metadata, generic call(id:arguments:) — built ON L2   │
├─ Layer 2  FolderStack  (generic, reusable) ─────────────────────────────────┤
│   ordered roots; named entries; FULL-REPLACE override by name; render       │
│   pipeline; list(); entry(name:); file-watch add/remove/reload up the stack │
│   Generic over an EntryKind (skill, agent, …)                               │
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
  skills *or* agents.
- **`SkillsRegistry`** (Layer 3, the source of truth) — wraps a `FolderStack<Skill>`; adds
  agentskills.io + Claude validation, the visibility model (§6), argument handling (§5),
  `partial`/include semantics, and **reload → injectable metadata** (§7). Exposes a generic
  `call(id:arguments:)`. **Skill validation is strictly above the raw stack.**
- **FM adapter** (Layer 4) — `SkillsTool`, the `SkillSearchAgent`, preload injection, and the
  `commandListing()`, all reading the registry.

## 4. Identity & naming

- **Directory name = canonical id.** It is the key for stack override, `{% include %}`
  partials, `/name` command matching, and `SkillsTool.call(id:)` — never the frontmatter `name`.
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
   only (§8). A `disableShellExecution` policy flag mirrors Claude's `disableSkillShellExecution`.
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
| *(default)* | listed | searchable + callable | no (body on call) | both audiences |
| `disable-model-invocation: true` | listed | hidden | no | user-only command (e.g. `/deploy`) |
| `user-invocable: false` | hidden | searchable + callable | no | model-only background |
| `partial: true` *(ours)* | hidden | hidden | no | `{% include %}` target only; never callable |
| `preload: true` *(ours)* | listed | searchable + callable | **yes** (body injected) | body always-on in Instructions; re-calling is redundant; see §7 |

- **`SkillsRegistry.commandListing()`** → `[SkillListing]` for the user `/` menu, carrying
  **structured, parsed parameters** (§6.1). **We produce data only** — autocomplete, fuzzy
  search, and input validation are the UI's job, out of scope here.
- `partial:` accepts **top-level canonical** else `metadata.partial: "true"`.

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

## 7. Discovery, preload & reload — the model-facing dynamics *(new)*

The single **`SkillsTool`** (the root session's entry point) has three actions:
- **`search(query)`** → delegates to the **`SkillSearchAgent`** and returns ranked matches
  (id + description + parsed params). This is the primary discovery path; it keeps the root
  context lean because the catalog lives in the search agent, not the root.
- **`list`** → returns the catalog (full or filtered) on demand, for small sets or explicit
  enumeration.
- **`call(id, arguments)`** → renders the chosen skill (pipeline §5) and returns its body as
  tool output. Dereferences the **live registry at call time**, validates `id`, and on an
  unknown/stale id returns the current list — so hot-reload stays correct even though FM
  snapshots tool definitions per turn. The id **is** constrained to a runtime enum: the `Tool`
  protocol's `parameters: GenerationSchema` is an instance property a conforming type
  implements itself (not fixed by a `@Generable Arguments`), so `SkillsTool` returns a schema
  built per-instance from the current id set via `DynamicGenerationSchema`, with
  `Arguments = GeneratedContent`. The enum reflects ids at session start; call-time validation
  is the backstop for ids that go stale between turns. *(Confirm against the shipping
  FoundationModels SDK — WWDC26 API. Decision #18.)*

**`SkillSearchAgent` — a separate `LanguageModelSession`.** It is seeded with the registry's
**skill metadata** (id, description, params; not full bodies) and searches it by intent on
behalf of the root agent. Benefits: (a) the root session is never clogged with the whole
catalog; (b) it can run a cheaper model / Private Cloud Compute; (c) it can be backed by
semantic search (Spotlight RAG) instead of pure LLM matching for large catalogs. Returns
candidate ids the root then `call`s.

**Builder.** The `SkillsTool` (and the search-agent session it owns) is assembled through a
**builder** — `SkillsTool.builder(registry:)` — because the wiring has many optional knobs:
which actions to enable (search/list/call), the search agent's model/reasoning level and its
search backend (LLM vs Spotlight RAG), the id-enum constraint toggle, and the
`disableShellExecution` policy. `build()` returns a ready `Tool` plus the live search session.
*(decision #15)*

**Preload.** Skills with `preload: true` have their **rendered bodies injected into the root
session's `Instructions`** at startup, alongside the `SkillsTool` — always-on context, no
search/call needed. Use sparingly (every preloaded line is a recurring token cost).

**Reload & metadata injection.** The `FolderStack` watcher fires on add/remove/edit up the
stack → `SkillsRegistry` rebuilds and publishes a **refreshed metadata list** (observable).
On reload we: (a) **re-inject** the new metadata into the `SkillSearchAgent`; (b) refresh the
**preloaded** bodies in the root; (c) leave the root `SkillsTool` untouched (it dereferences
the live registry per call). The registry also exposes an **initial** metadata list at
construction and the generic **`call(id:arguments:)`** used by both the tool and any host code.

## 8. Platform & security
- **macOS primary** (on-device): full feature set — args, shell injection, env, scripts.
- **iOS: graceful "unavailable on platform"** stub; no shell/script attempted.
- **No cache concern** — render-once at list/call; fixed in transcript.
- **Server-side providers see the transcript** — with all env exposed and shell output inlined,
  a rendered skill can carry that off-device if a session routes to a cloud provider.
  Documented; accepted for the on-device-Mac use case. (The search agent sees only metadata,
  not rendered bodies, which limits exposure during discovery.)

## 9. Resolved decisions
1. **Template engine → Stencil** (`{{ }}` + `{% include %}`).
2. **Env → all** of `ProcessInfo.environment` as `{{ env.* }}`.
3. **Override → full replace** (higher layer shadows lower entirely).
4. **FM integration → our own single `SkillsTool`** on core `FoundationModels.Tool`; no
   `FoundationModelsUtilities` dependency.
5. **`partial:` → accept both, top-level canonical.**
6. **Arguments → Claude-compatible** (`$ARGUMENTS`, `$ARGUMENTS[N]`/`$N` 0-based, `$name`,
   `argument-hint:`).
7. **Architecture → 4 layers**; generic `FrontmatterDocument` + `FolderStack` reused for agents.
8. **Identity → directory name canonical**; agentskills.io `name` required and validated `== id`.
9. **Visibility → `user-invocable` + `disable-model-invocation` + `partial`**; two listing
   surfaces (command vs model).
10. **Parameters → infer from body** when frontmatter is absent; frontmatter refines.
11. **FM entry point → one `SkillsTool`** with **search / list / call** actions.
12. **Discovery → a separate `SkillSearchAgent` session**, so the root session is not clogged
    with skill metadata; only a chosen skill's body enters the root.
13. **Source of truth → `SkillsRegistry`**: reloadable; publishes an initial + injectable
    refreshed metadata list; generic `call(id:arguments:)`.
14. **Preload → `preload: true`** skills' rendered bodies injected into the root session at
    startup (and refreshed on reload).
15. **Builder → `SkillsTool.builder(registry:)`** assembles the tool + its search-agent
    session (actions, search model/reasoning/backend, id-enum constraint, shell policy).
16. **Partials → render standalone** (env + own `$`-tokens; not the parent's arguments).
17. **Packaging → single SwiftPM target.** Layering (§3) is conceptual — by type, not module
    — so FoundationModels is a dependency of the whole package and the future `AgentRegistry`
    lives in the same target.
18. **Tool arg schema → dynamic.** `Tool.parameters: GenerationSchema` is an instance property
    a conformer implements itself (not fixed by a `@Generable Arguments`), so `SkillsTool`
    returns a per-instance schema built from the current id set (`DynamicGenerationSchema`,
    `Arguments` = `GeneratedContent`). Call-time validation backstops between-turn staleness.
    *(Confirm against the shipping WWDC26 SDK.)*

**All open items resolved — the plan is decision-complete.**

## 10. Public API sketch (illustrative)

```swift
// Layers 1–3 — generic stack + reloadable registry:
let registry = try SkillsRegistry(
  roots: [enterpriseURL, userURL, projectURL],   // low → high; full-replace by id
  env: .all,
  watch: true                                    // reload add/remove/edit up the stack
)

// Layer 4 — builder assembles the SkillsTool + its search-agent session:
let skillsTool = SkillsTool.builder(registry: registry)
  .actions([.search, .list, .call])
  .searchAgent { $0.model(.privateCloudCompute).reasoning(.light).backend(.spotlight) }
  .constrainIdsToEnum(true)            // dynamic GenerationSchema enum of current ids
  .build()                             // → (tool: Tool, search: SkillSearchAgent)

// Lean root session: one tool + preloaded bodies, NO full catalog inline:
let root = LanguageModelSession(
  tools: [skillsTool.tool],
  instructions: Instructions {
    "…base instructions…"
    registry.preloadedBodies()         // preload: true skills, rendered
  }
)

// Reload: re-inject metadata into the search agent; refresh preloaded bodies; root tool
// already dereferences the live registry per call.
registry.onReload { meta in skillsTool.search.update(metadata: meta) /* + refresh preload */ }

// User-facing command matching (independent of the session):
for skill in registry.commandListing() { /* skill.id, .description, .parameters */ }
```

## 11. Phasing
- **M1 — Layers 1–2.** `FrontmatterDocument`; `FolderStack` (discovery, full-replace override,
  provenance, `list()`/`entry()`). No templating, watch, or FM.
- **M2 — Watch + render skeleton.** File watcher (add/remove/reload up the stack); render
  pipeline scaffold (passes wired, identity transforms).
- **M3 — `SkillsRegistry`.** agentskills.io + Claude validation, visibility, `partial`,
  `preload`, `commandListing()`, initial + injectable metadata, generic `call`.
- **M4 — `SkillsTool` + search agent.** `SkillsTool` (search/list/call) on core
  `FoundationModels.Tool`; `SkillSearchAgent` session; preload injection; reload re-injection.
- **M5 — Full render.** Arguments, shell injection (macOS), Stencil env + `{% include %}`
  partials + cycle detection.
- **M6 — Lazy resource tools.** `references/`/`assets/`/`scripts/` as on-demand tools gated by
  `allowed-tools`; macOS sandboxing.
- **M7 — `AgentRegistry` on the same `FolderStack`** + diagnostics polish + docs/examples.

---

### Sources
- agentskills.io specification — https://agentskills.io/specification
- Claude Code skills & slash-command arguments — https://code.claude.com/docs/en/slash-commands
- What's new in Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/241/
- Build agentic app experiences with Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/242/
- apple/foundation-models-utilities — https://github.com/apple/foundation-models-utilities
