# FoundationModelsSkills

An [agentskills.io](https://agentskills.io)-style skill library for
[FoundationModels](https://developer.apple.com/documentation/foundationmodels): discover, search,
and run `SKILL.md` files from a layered dotfolder stack, exposed as one fused
[`FoundationModelsOperationTool`](../FoundationModelsOperationTool) `Tool` and a dual-use CLI.

A skill is a directory with a `SKILL.md` (YAML frontmatter + Markdown body). `SkillsRegistry`
discovers them across a host-supplied, ordered set of layer roots (nearest wins, full replace by
directory name), renders each body through a three-pass pipeline (`$`-argument substitution, `` !`shell` ``
injection, Stencil templating), and exposes the catalog to a model, a `/command` UI, and a CLI
through the same rendering path.

## Install

Path dependency (this package is not yet published):

```swift
.package(path: "../FoundationModelsSkills")
```

## The fused tool, end to end

The compiling, always-up-to-date version of this example is
[`Examples/skills-demo`](Examples/skills-demo) — the dual-use worked example
(`Examples/skills-demo/SkillsDemoAssembly.swift`/`SkillsDemoMain.swift`), which `swift build` builds
alongside the library and `SkillsDemoTests.swift` exercises as a subprocess. What follows is lifted
directly from it.

```swift
// Roots are the host's choice. The usual way to compute them is a "skills" dotfolder stack:
let stack = DotfolderStack(
    name: "skills",
    workingDirectory: projectDirectory,
    defaultsDirectory: shippedSkillsURL,   // optional lowest layer; SKILLS_DEFAULTS_DIR overrides
    userDirectory: userConfigURL)          // omit to derive $XDG_CONFIG_HOME/skills or ~/.config/skills

// Layer 3 — a reloadable registry over the stack:
let registry = SkillsRegistry(
    stack: stack,                          // nearest-wins = full-replace by id
    policy: RenderPolicy(),                // isShellExecutionDisabled / isScriptExecutionDisabled
    watch: true)                           // watch every layer root; reload on add/remove/edit

// Layer 4 — three (or six, with resource ops) operations over one context, fused into one tool:
let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
let context = SkillsToolContext(registry: registry, searchAgent: SkillSearchAgent(searcher: searcher))
let skillsTool = try SkillsTool.make(context: context)

// Lean root session: one tool + preloaded bodies, NO full catalog inline:
let root = LanguageModelSession(
    tools: [skillsTool],
    instructions: Instructions {
        "…base instructions…"
        registry.preloadedBodies()         // preload: true skills, rendered
    })

// Reload: forward metadata to the searcher's update(items:) -- the caller's responsibility,
// not something either type does automatically:
if let reloads = registry.onReload {
    Task {
        for await metadata in reloads {
            await context.searchAgent.update(items: metadata)
        }
    }
}

// User-facing command matching (independent of the session):
for listing in registry.commandListing() { /* listing.id, .description, .parameters */ }

// Dual-use CLI from the SAME declarations:
let cli = try SkillsCLI.makeDriver(registry: registry)
let result = await cli.run(arguments: CommandLine.arguments.dropFirst().map(String.init))
```

## Op vocabulary

One fused tool, six operations, a flat-union schema (`op` discriminator + every field as
optionals), return-don't-throw with corrective messages on invalid input:

| op | parameters | behavior |
|---|---|---|
| `search skill` | `query` (req), `limit?` | Ranked matches from `SkillSearchAgent` over the model-visible catalog. |
| `list skill` | `filter?` | The model-visible catalog (optionally filtered), catalog order, no ranking. |
| `use skill` | `id` (req), `arguments?` | Renders the §5 pipeline with `arguments`; unknown/hidden `id` returns a corrective carrying the current id list. |
| `list resource` | `id` (req) | Enumerates every file under the skill's directory except `SKILL.md`, capped at 100 rows. |
| `read resource` | `id` (req), `path` (req), `start?`, `end?` | Returns a file verbatim, sliced by line, at most 500 lines/call — never rendered. |
| `run script` | `id` (req), `path` (req, under `scripts/`), `arguments?`, `timeout?` | Execs the file directly (executable bit + shebang required) under the triple gate (host policy, per-skill `allowed-tools: Script(<glob>)` grant, host trust posture), own process group, `SIGKILL` on timeout. |

Verb aliases: `find`/`discover` → `search`; `call`/`invoke`/`get` → `use`. (`run` is claimed by
`run script`, so `run skill` does not resolve to `use skill`.)

## Visibility

| Frontmatter | User `/` menu | Model surface | In context at startup |
|---|---|---|---|
| *(default)* | listed | searchable + usable | no (body on use) |
| `disable-model-invocation: true` | listed | hidden | no |
| `user-invocable: false` | hidden | searchable + usable | no |
| `preload: true` | listed | searchable + usable | **yes** (body injected into `Instructions`) |

`ListSkill`/`UseSkill`/the resource ops gate on `context.visibilityPredicate` — `SkillsTool.make`
defaults it to `isModelVisible`; `SkillsCLI` supplies a different predicate (id membership in
`registry.commandListing()`) so the CLI presents the user-facing surface instead.

## Known deviations

- **Op-level correctives don't count toward upstream's retry cap.** Plan.md §7/decision #22:
  "upstream's retry cap (default 2) stops loops." `OperationTool.call(arguments:)`
  (`../FoundationModelsOperationTool/Sources/Operations/OperationTool.swift`) only tracks
  *resolver-level* failures — unknown op, missing required parameters, unparseable values — via
  `recordCorrective`. Once dispatch actually reaches an operation's own `execute(in:)`, that call
  unconditionally counts as success and resets the counter (`retryState.reset()`), even when the
  op itself returns a `CorrectiveOutcome.corrective(_:)` (e.g. `use skill` with an unknown id,
  `read resource` with an inaccessible path). A model looping on a bad `id` therefore never hits
  the cap. Fixing this properly needs an upstream signal on `AnyOperation.run`'s result (an
  `isCorrective` flag, or an enum distinguishing the two cases) — `OperationTool.Output` is
  presently an opaque `String`, so the fused tool has no way to see which channel an operation's
  own JSON came from. That's a protocol-level change to `FoundationModelsOperationTool`, a
  separate package other consumers of this pattern also depend on, out of this package's scope to
  land unilaterally. Not yet coordinated upstream; tracked here rather than silently left
  undocumented. `SkillOperationsTests.repeatedUnknownIDUseSkillDispatchesAreNeverCappedByUpstreamsRetryLimit`
  pins the current (uncapped) behavior so a future upstream fix is noticed here as a test failure,
  not silently.

## Security posture

- **No OS sandbox in v1.** `` !`shell` `` injection (§5) and `run script` (§7.3) run as ordinary
  child processes with the host's own privileges — full environment inheritance, no filesystem or
  network restriction beyond the script's own cwd discipline. `sandbox-exec` is deprecated API over
  a private profile language; containment here is gates (host policy + per-skill `allowed-tools`
  grants) and process control (own process group, timeout `SIGKILL`), not an OS sandbox. Revisit
  when Apple ships a supported per-process confinement API.
- **Untrusted layers render untrusted.** Only the layer a host tags `.defaults` (shipped,
  consumer-controlled content) renders Stencil-trusted; every user/project layer renders through
  Extras' untrusted path (tag/filter whitelist, include-depth/output-size/iteration budgets). This
  bounds the *template* pass only — shell injection and scripts are separately gated and never
  granted by Stencil trust.
- **Server-side providers see the transcript.** A rendered skill body — with all environment
  variables exposed and shell output inlined — travels off-device if a session routes to a cloud
  provider. The search agent sees only metadata, not rendered bodies, which limits exposure during
  discovery; a used skill's full rendered body is a deliberate, accepted trade-off for the
  on-device-Mac use case.
- **Trust-gate untrusted project layers yourself.** A project `.skills/` from a freshly cloned repo
  can inject instructions into a session. `SkillsRegistry` takes its layer roots as a plain,
  caller-supplied list — it has no opinion about which directories are safe to load — so a host
  should only construct a registry (especially a script-enabled one) over roots it trusts. Every
  `SkillDiagnostic` carries the winning layer's provenance (`SkillDiagnostic.Provenance.root`) so a
  host can show *where* a skill came from.

**Context-compaction note for hosts:** a used skill's rendered body is durable guidance a session
depends on for the rest of the conversation. A host that summarizes or prunes its own transcript
should exempt skill tool outputs from that pruning — this package has no opinion on transcript
management, but silently dropping a skill's body mid-conversation will silently degrade its
behavior.

## Platform posture

- **macOS is the primary, fully-supported platform**: argument substitution, shell injection,
  environment/Stencil templating, and scripts all work.
- **iOS is unsupported, not stubbed.** A graceful "unavailable on platform" runtime stub is only
  possible when every dependency in the graph declares an iOS floor — two of this package's three
  sibling dependencies (`FoundationModelsExtras`, `FoundationModelsMetadataRegistry`) are macOS-only,
  so no iOS build of this package is possible at all. See the doc comment on the
  `FoundationModelsSkills` namespace enum (`Sources/FoundationModelsSkills/FoundationModelsSkills.swift`)
  for the full accounting of which dependency forces this.

## Development

- **Sibling dependencies are remote, not local `path:`.** `FoundationModelsExtras`,
  `FoundationModelsOperationTool`, and `FoundationModelsMetadataRegistry` are all pinned to
  `git@github.com:swissarmyhammer/<name>.git` (`main` branch) in `Package.swift`, matching the
  family convention `FoundationModelsRouter`/`FoundationModelsMetadataRegistry` already use. A
  local `path:` dependency here previously produced a SwiftPM "Conflicting identity" warning for
  `FoundationModelsOperationTool` — this package pulled it in twice, once by path and once
  transitively (via `FoundationModelsMetadataRegistry -> FoundationModelsRouter`) by URL — which
  SwiftPM states "will be escalated to an error in future versions." Wiring every sibling remotely
  resolves the identity to a single reference, and matches the family's shared `swift-ci.yaml`
  reusable workflow, which only checks out the calling repo (a `path:` dependency on an
  uncommitted sibling checkout would not exist there).
- **The mlx `Cmlx.bundle` "missing creator for mutated node" build warning is known toolchain
  noise**, not something this package's code or manifest causes — it comes from `mlx-swift`'s own
  bundle target (pulled in transitively via `FoundationModelsMetadataRegistry ->
  FoundationModelsRouter -> mlx-swift-lm -> mlx-swift`) and appears on every `swift build`/`swift
  test` regardless of what changed here. Not chased; upstream toolchain/mlx-swift concern.

## Documentation

Design rationale — the layered architecture, every resolved decision, and the full render-pipeline
and resource-operation specification — is in [`plan.md`](plan.md). [`Examples/skill-library`](Examples/skill-library)
is a three-layer fixture stack exercising every templating/visibility feature once; the unit tests
load it for golden renders, and `Examples/skills-demo` loads the same directories, so the documented
behavior is the tested behavior.
