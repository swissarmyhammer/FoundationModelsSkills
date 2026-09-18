# Plan: skill marketplaces

**Status: Part B is implemented.** The package holds the store, the cache, the layers, the
checks and the updates, the pins, the grants, and the `skills marketplace` commands. Read
[`docs/marketplaces.md`](docs/marketplaces.md) for the host guide of the behavior that
shipped, and [`docs/security.md`](docs/security.md) for the security posture. This page stays
the design record. Part A, the `../skills` repository, is not made yet.

This plan adds remote skill marketplaces to `FoundationModelsSkills`. It has two parts:

- **Part A — a new `../skills` repository.** This repository is a skill marketplace in the
  Claude / OpenAI / agentskills.io format. It holds a **copy** of the skills in
  `../swissarmyhammer/builtin`. sah does not change.
- **Part B — marketplace support in this package.** A host gives an ordered list of
  marketplace URLs. The package fetches each marketplace, keeps it in a cache, checks it for
  updates, and updates it automatically. Each marketplace becomes a skill layer **below** the
  local skill folder stack. Thus a local skill with the same name always wins.

This plan does not make kanban tasks yet. The phases in §12 are the input for those tasks.

---

## 1. Goals and non-goals

**Goals**

1. Make one marketplace repository (`swissarmyhammer/skills`) that holds a copy of the sah
   skills.
2. Let a host give a list of marketplace URLs. The list is read left to right, and the last
   URL wins.
3. Put every marketplace layer below the local stack (`defaults < user < project`). A local
   skill shadows a marketplace skill of the same name.
4. Keep a local cache of each marketplace in `~/.cache`, as the family does for models. The
   registry must work offline from that cache.
5. Check each marketplace for updates, and update it automatically. Let the host turn this off.
6. Keep the Stencil templates. This package renders them. A plain agentskills.io client does
   not have to render these skills correctly.

**Non-goals (v1)**

- **We do not change sah.** The copy in `../skills` and the original in
  `../swissarmyhammer/builtin` are independent.
- **Agents are later.** v1 copies skills only.
- The model does not add, remove, or update marketplaces. Marketplace control is a host and
  CLI function only. A model that can add a remote source can inject instructions.
- The package does not install Claude Code plugins, MCP servers, or hooks. It reads only
  skills from a marketplace.
- We do not publish a pre-rendered copy of the skills for plain clients in v1 (see §11, Later).
- We do not support `npm` or `command` sources.
- **No hard-coded times.** The package has no built-in check interval, start delay, or age
  limit. A time value exists only when the host gives one (§8.2).

## 2. Research summary

The full research is in the session record. This section keeps only the facts that change
the design.

| Ecosystem | Catalog file | Sources | Cache | Updates | Name collisions |
|---|---|---|---|---|---|
| **Claude Code** | `.claude-plugin/marketplace.json` (plugins → skills) | relative path, `github`, `url` (git), `git-subdir`, `npm`, `archive`, `command`; `sha` wins over `ref` | `~/.claude/plugins/marketplaces/<name>/` (clone), `cache/<mkt>/<plugin>/<version>/` (one folder per version), `known_marketplaces.json` | background, after a random delay; the running session keeps its loaded version; keep the last good cache on failure (optional); orphans deleted after some days | skills are namespaced `plugin:skill`, so they never collide |
| **Claude API / claude.ai** | none (upload) | zip or files | server side | each version is a full snapshot; `latest` or a pinned version id | not applicable |
| **agentskills.io** | none in the spec; the draft Cloudflare RFC adds `/.well-known/agent-skills/index.json` with a `sha256` digest for each skill | well-known URL | session cache; the digest is the change key | compare digests | project overrides user; log a warning for each shadowed skill |
| **OpenAI Codex** | `.agents/plugins/marketplace.json`; `.codex-plugin/plugin.json`; it also reads `.claude-plugin/marketplace.json` | `local`, `git-subdir`, `url`, `npm` | `~/.codex/plugins/cache/<mkt>/<plugin>/<version>/` | `codex plugin marketplace upgrade` | the first marketplace wins; skills of the same name are not merged (both show) |
| **`npx skills` (Vercel)** | repo scan, `marketplace.json`, well-known | `owner/repo`, tree URLs, git, local | symlinks into `.agents/skills`; lock file with the GitHub **tree SHA** of each skill folder | `check` / `update` compare tree SHAs | the shallower `SKILL.md` wins |
| **GitHub `gh skill`** | repo scan; Copilot also reads `.claude-plugin/marketplace.json` | `owner/repo[@tag\|sha]` | writes provenance (`github-repo`, `github-ref`, `github-tree-sha`, `github-pinned`) into the frontmatter | `update` compares tree SHAs and skips pinned skills | not applicable |

**What the Claude Code cache on this machine shows** (`~/.claude/plugins/`):

- The official catalog uses `git-subdir` sources pinned with both `ref` and a 40-hex `sha`.
- The catalog has a `renames` map (old name → new name).
- Each version folder has an `.in_use/` marker. The cleanup step does not delete a version
  while a session uses it.
- `blocklist.json` is a remote kill switch. It lists a plugin, a reason, and a message.
- `plugin-catalog-cache.json` records the token cost of each skill (`always_on` and
  `on_invoke`) for each model.

**Conclusions for this design**

1. `.claude-plugin/marketplace.json` is the de-facto standard. Claude Code, Codex, and Copilot
   all read it. Our repository publishes it, and our client reads it first.
2. Every other client namespaces or duplicates remote skills. **We do not do that.** The
   requirement is that a local skill shadows a remote skill of the same name. Thus remote
   skills use bare names, and the stack decides the winner. We keep the shadow diagnostic that
   the agentskills.io client guide recommends.
3. Pin by commit SHA. Detect changes with a cheap remote query (a remote ref listing, an HTTP
   ETag, a digest) before any download.
4. Never let an update break the registry. Keep the last good version. Swap versions
   atomically.

## 3. Part A — the `../skills` marketplace repository

### 3.1 Identity

- Path: `../skills` (`/Users/wballard/github/swissarmyhammer/skills`).
- Remote: `git@github.com:swissarmyhammer/skills.git`.
- Marketplace name: `swissarmyhammer-skills`. Do not use a reserved name such as
  `agent-skills` or `anthropic-agent-skills`.
- License: `MIT OR Apache-2.0`. This is the license that the sah skills already declare.

### 3.2 Layout

```
skills/                                   repository root
├── .claude-plugin/
│   └── marketplace.json                  primary catalog (Claude, Codex, Copilot read it)
├── .agents/plugins/
│   └── marketplace.json                  Codex mirror, generated from the primary catalog
├── .well-known/agent-skills/
│   └── index.json                        agentskills discovery index, generated, with digests
├── skills/                               ONE layer root: every skill is a direct child
│   ├── _partials/                        Stencil partials for this marketplace
│   │   ├── sah-task-standards.md
│   │   └── ...
│   ├── commit/SKILL.md
│   ├── tdd/
│   │   ├── SKILL.md
│   │   └── writing-good-tests.md
│   └── ...
├── scripts/
│   ├── generate-catalogs                 writes the catalogs and index.json from skills/
│   └── release                           sets metadata.version, tags vX.Y.Z
├── .github/workflows/ci.yml
├── LICENSE-MIT, LICENSE-APACHE
└── README.md
```

**Decision:** all skills are direct children of one `skills/` folder, and `_partials/` is in
that folder too. Thus `skills/` is a valid layer root for this package with no change to
discovery. Discovery reads only `root/<name>/SKILL.md` and skips a folder that has no
`SKILL.md`, so `_partials/` never shows as a skill.

### 3.3 Catalog

The Claude catalog format puts skills inside "plugins". A plugin is only a named list of
skills. We use **one plugin** that lists every skill. This follows the `anthropics/skills`
pattern: `"source": "./"`, `"strict": false`, and an explicit `skills` array. No
`plugin.json` is necessary.

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "swissarmyhammer-skills",
  "owner": { "name": "swissarmyhammer" },
  "metadata": { "description": "Engineering workflow skills from swissarmyhammer.", "version": "1.0.0" },
  "plugins": [
    { "name": "swissarmyhammer", "source": "./", "strict": false,
      "description": "All swissarmyhammer skills.",
      "skills": ["./skills/check-sah", "./skills/ci", "./skills/code-context", "./skills/commit",
                 "...one entry for each skill folder..."] }
  ]
}
```

`scripts/generate-catalogs` writes the `skills` array from the folders in `skills/`. Nobody
edits the array by hand.

### 3.4 The copy from `../swissarmyhammer/builtin`

This is a **copy**. We do not move or delete anything in sah.

**What we copy**

| Source in sah | Target in `../skills` | Note |
|---|---|---|
| `builtin/skills/*` (24 skills) | `skills/<name>/` | all 24 skills, with `references/` and other files |
| `builtin/_partials/*.md` (the 8 partials that skills include) | `skills/_partials/` | renamed with a `sah-` prefix (§3.5) |

**What we do not copy**

- `builtin/_partials/project-types/*`. No skill includes these files.
- `builtin/agents/*`. Agents are later.
- `builtin/validators/*`. Only the sah review engine can run them.
- `lsp/`, `models/`, `file_groups/`, `statusline/`, and `*/config.yaml`. These are
  configuration for the sah binary, not marketplace content.

**Template conversion (Liquid → Stencil)**

The survey found that the copied files use only four template constructs:

| Construct | Count | Action |
|---|---|---|
| `{% include "_partials/<name>" %}` | 31 | Keep. The Stencil syntax is the same. `DotfolderLoader` resolves it. Change the name to the `sah-` prefixed name. |
| `{% if %}` … `{% endif %}` | 2 | Keep. The untrusted whitelist permits `if`. |
| `{{version}}` in `metadata.version` | 24 | Replace with a literal version. `scripts/release` writes it. |
| `{{ arguments }}` / `{{arguments}}` in `ci`, `map` | 2 | Replace `{% if arguments %}…{{arguments}}…{% endif %}` with this package's `$ARGUMENTS` form. |

The files use no filters and no whitespace control. Thus every converted file passes the
untrusted Stencil path (tags `if`/`for`/`include` only, zero filters). Marketplace layers
always render untrusted (§6.6), so this is a hard requirement. CI checks it (§3.6).

**Frontmatter**

- Keep the spec fields: `name`, `description`, `license`, `compatibility`, `metadata`.
- Keep the Claude and sah extension fields as they are: `agent:`, `context:`, `background:`,
  `hooks:`. This package records unknown keys as advisory diagnostics and loads the skill.
- `compatibility` names the sah MCP tools that a skill needs. Most skills already have it.
  Keep it.

### 3.5 Partial names

Partials resolve through the layer stack, and the nearest layer wins. Two marketplaces can
each ship `_partials/header.md`. §6.5 prevents a cross-marketplace include in the client. The
repository also uses a convention: every partial name starts with the marketplace prefix
(`sah-`). This makes a collision with a third-party marketplace unlikely, and a local
override stays intentional.

### 3.6 Repository CI

1. **Validate** each skill with this package's validator (via the `skills` CLI). Error on a
   `name` that is not the same as the folder name, a missing `description`, or a partial that
   does not resolve.
2. **Render** each skill through the Extras `TemplateEngine` in `.untrusted` mode, with this
   repository as the only layer. Error on any render failure.
3. **Catalog sync.** Run `scripts/generate-catalogs` and fail if the output differs from the
   committed files.
4. **Version.** A release tag `vX.Y.Z` must be equal to `metadata.version` in the catalog.

## 4. Part B — the layer model

### 4.1 Precedence

Today the host gives an ordered list of layer roots, lowest precedence first. The last root
wins (plan.md decision #29). The marketplace URLs go at the start of that list, left to right,
and the existing stack follows:

```
lowest ──────────────────────────────────────────────────────────────▶ highest (wins)
url[0]  <  url[1]  <  …  <  url[n]  <  defaults  <  user  <  project
└──────── marketplaces, cached, untrusted ───────┘ └──── local stack ────┘
```

- **Left to right, last wins.** One rule covers the full stack.
- **Local wins.** A skill in `defaults`, `user`, or `project` shadows a marketplace skill of
  the same name. The shadowed skill stays in `DiscoveredSkill.shadowedCandidates`, and the
  existing advisory diagnostic names the marketplace that lost.
- **Inside one marketplace**, skill names must be unique. If two plugins list the same skill,
  the client records a diagnostic, and the plugin that is later in the catalog wins.
- **Full replace.** The winner replaces the full skill folder. There is no merge (decision #3).

### 4.2 One marketplace = one layer root

The store (§6) materializes each marketplace into one flat folder:
`<cache>/<id>/snapshots/<sha>/`. That folder has `<skill>/SKILL.md` for each selected skill,
and `_partials/`. The layer root that the registry sees is the stable path
`<cache>/<id>/current`. The store swaps `current` from one snapshot to the next atomically
(§7.3).

This design needs no change to `SkillDiscovery`. Discovery skips a missing root, so a
marketplace that is not fetched yet is an empty layer and not an error.

### 4.3 Layer source tag

`DotfolderStack.Source` in Extras has `defaults`, `user`, and `project`. Trust depends on this
tag: only `.defaults` renders trusted (`StencilPass.resolvedTrust`).

**Decision:** add a `case marketplace` to `DotfolderStack.Source` in `FoundationModelsExtras`.

- A marketplace layer must never render trusted. A new case makes that clear. If we reuse
  `.user`, the trust is correct but the provenance is wrong.
- `StencilPass.resolvedTrust` does not change: every source except `.defaults` is untrusted.
- This is a change in a sibling package. It must merge in Extras before Part B can use it.

## 5. Marketplace sources

### 5.1 Source forms (v1)

| Form | Example | Fetch |
|---|---|---|
| git SSH | `git@github.com:swissarmyhammer/skills.git` | **not supported**: the libgit2 build has no SSH transport, and the URL gives `unsupported URL protocol` |
| git HTTPS | `https://github.com/swissarmyhammer/skills.git` | libgit2, HTTPS transport |
| GitHub shorthand | `github:swissarmyhammer/skills` | expands to the HTTPS git URL |
| ref and pin | `…skills.git#v1.2.0`, or the `ref:` and `sha:` fields | `sha` wins over `ref` |
| subfolder | the `path:` field | reads only that path from the commit tree |
| local folder | `file:///Users/me/github/swissarmyhammer/skills` | no copy; the folder is read directly and watched like a local layer |

**Decision: use libgit2 through a SwiftPM package. Do not start the `git` binary.**

We compared the Swift options (September 2026):

| Package | Result |
|---|---|
| [`danielctull-forks/swift-libgit2`](https://github.com/danielctull-forks/swift-libgit2) | **Selected.** libgit2 1.9.x built from source as a SwiftPM target (tags to `1.9.7`, last commit 2026-08-20). swift-tools 6.2. Product `libgit2`. HTTPS through SecureTransport. No SSH transport: the manifest sets `GIT_SSH_EXEC` with an empty trait list, and SwiftPM never applies such a setting. An optional `libssh2` trait exists; we do not enable it. |
| [`ibrahimcetin/libgit2`](https://github.com/ibrahimcetin/libgit2) | Same build approach (libgit2 1.9.2, `GIT_SSH_EXEC`, SecureTransport). Less recent (2025-11). This is the fallback if the selected package stops. |
| [SwiftGitX](https://github.com/ibrahimcetin/SwiftGitX) | Rejected as the API layer. Its `fetch` calls `git_remote_fetch(remote, nil, nil, nil)`: no depth, no credentials, no progress. It has no remote ref listing. |
| [swift-git](https://github.com/danielctull/swift-git) | Rejected as the API layer. It has `clone` but no fetch options, no remote ref listing, and no credential callbacks. |
| [SwiftGit2](https://github.com/SwiftGit2/SwiftGit2), [libgit2-apple](https://github.com/mfcollins3/libgit2-apple) | Rejected. Old libgit2 (1.5 or earlier), or little maintenance. |

Thus the package depends on the libgit2 SwiftPM target directly and has a small **internal**
Swift wrapper, `GitTransport`, over the few C calls that the store needs:

| Need | libgit2 call |
|---|---|
| check for an update (the `ls-remote` equivalent) | `git_remote_create_detached` → `git_remote_connect` (fetch direction) → `git_remote_ls` |
| shallow fetch of one commit | `git_repository_init` (bare) → `git_remote_create_anonymous` → `git_remote_fetch` with `git_fetch_options.depth = 1` |
| read the catalog and skill files | `git_commit_lookup` → `git_commit_tree` → `git_tree_entry_bypath` → `git_blob_rawcontent` |
| cancel | the `transfer_progress` and `sideband_progress` callbacks return a non-zero value when the Swift `Task` is cancelled |

Rules:

- **Pin exactly.** `.package(url: "https://github.com/danielctull-forks/swift-libgit2.git",
  exact: "1.9.7")`. This agrees with the `Yams` pin in `Package.swift`.
- **`GitTransport` is internal and is a protocol.** The store gets a `GitTransport` value. Tests
  use a counting double (§13). If we must change the libgit2 package, only the concrete type
  changes.
- **SSH is not supported.** The first plan was the libgit2 exec transport (`GIT_SSH_EXEC`),
  which runs the system OpenSSH. `swift-libgit2` 1.9.7 does not build that transport on
  macOS: `git_libgit2_features()` has the `GIT_FEATURE_SSH` bit at `0`, and
  `git_remote_connect` on an SSH URL gives `unsupported URL protocol` before it starts a
  process. The user decided on 2026-09-18: no fork of `swift-libgit2`, no `libssh2` trait.
  Use the HTTPS form of a repository. The parser still accepts the scp-like SSH form.
- **HTTPS.** SecureTransport uses the system trust store. libgit2 does not run git credential
  helpers. For a private HTTPS source, the host gives
  `MarketplacePolicy.credentials: (URL) async -> MarketplaceCredential?` (a user name and
  token). The `credentials` callback of libgit2 calls it. The value goes only to the origin of
  that source.
- **What libgit2 does not do** (all good for this use): it runs no hooks, it does not fetch
  submodules, and it does not run LFS filters. A skill file that is an LFS pointer gets a
  diagnostic.
- **Cancellation and timeout.** `stop()` cancels the task, and the progress callback stops
  libgit2. The host can also give a `fetchTimeout`. There is no built-in timeout.
- **Build cost.** libgit2 compiles from C source one time for each clean build. This is the
  cost of no binary artifact and no system dependency.

**Later forms** (§11): an HTTPS `marketplace.json` URL, the well-known `index.json`, and an
`archive` (`.tar.gz`/`.zip`) with `sha256`.

### 5.2 Catalog formats that the client reads

The client looks for these in order, and uses the first that it finds:

1. `.claude-plugin/marketplace.json`. It collects the skills of each plugin from the plugin's
   `skills` array. If the array is not there, it uses `<plugin source>/skills/*/SKILL.md`.
   v1 supports relative plugin sources only. A plugin with a remote source (`github`,
   `git-subdir`, `url`) gets a diagnostic, and the client skips it.
2. `.agents/plugins/marketplace.json` (Codex). The same rules apply.
3. No catalog: a scan of the repository. It reads `skills/*/SKILL.md`, then a root
   `SKILL.md`, to a maximum depth of 3. The shallower `SKILL.md` wins.

The client also reads `renames` from a Claude catalog. If a host selection names a renamed
skill, the client uses the new name and records a diagnostic. `null` means that the skill
was removed.

### 5.3 Marketplace identity

- Before a fetch, the store knows only the source. Thus it uses a **pre-fetch key**. The
  pre-fetch key is the alias, if the host gives one. If there is no alias, the pre-fetch key
  is the last path component of the repository, without `.git`.
- Validation uses the pre-fetch key. Two sources with the same pre-fetch key are a
  configuration error. The store rejects the list and records a diagnostic. It does not merge
  them. To use the two sources, give one of them an alias.
- The cache folder name uses the pre-fetch key:
  `<pre-fetch key>-<first 8 hex of sha256(normalized URL)>`. Thus a changed URL never uses a
  stale cache.
- After a fetch, the catalog `name` is the **display id** of the marketplace.

## 6. The `MarketplaceStore`

### 6.1 Responsibilities

One `actor MarketplaceStore` owns all marketplace state. It:

1. Holds the ordered source list and the policy.
2. Returns the layers for the registry, with no network I/O.
3. Fetches, materializes, and swaps snapshots.
4. Runs update checks and automatic updates.
5. Publishes events. The registry reloads on an update event.

The store is separate from `SkillsRegistry`. The registry stays a pure disk reader, and the
existing tests stay valid. A host that uses no marketplaces sees no change.

### 6.2 Public API sketch (illustrative)

```swift
import FoundationModelsSkills

// Left to right: the last URL wins over the earlier URLs.
let store = MarketplaceStore(sources: [
    MarketplaceSource("https://github.com/swissarmyhammer/skills.git"),
    MarketplaceSource("github:acme/team-skills", autoUpdate: false),
])

let stack = DotfolderStack(name: "skills", workingDirectory: projectDirectory,
                           defaultsDirectory: shippedSkillsURL, userDirectory: userConfigURL)

// Marketplace layers first (lowest precedence), then the local stack.
// This call reads only the cache. It never waits on the network.
let registry = SkillsRegistry(marketplaces: store, stack: stack, watch: true)

// Fetch a cold cache and check for updates. The registry reloads on each update.
await store.start()
```

```swift
public struct MarketplaceSource: Sendable, Hashable, Codable {
    public var url: String                 // any §5.1 form
    public var ref: String?                // branch or tag
    public var sha: String?                // a pin; it wins over ref and stops auto-update
    public var path: String?               // a subfolder in the repository
    public var alias: String?              // a local name; it is the pre-fetch key (§5.3)
    public var select: SkillSelection      // .all (default) | .plugins([String]) | .skills([String])
    public var autoUpdate: Bool            // default true
    public var grants: MarketplaceGrants   // default .none: no shell injection, no scripts
}

public actor MarketplaceStore {
    public init(sources: [MarketplaceSource],
                cacheDirectory: URL = MarketplaceStore.cacheDirectory(environment: ProcessInfo.processInfo.environment),
                policy: MarketplacePolicy = MarketplacePolicy())
    public nonisolated func marketplaceLayers() -> [MarketplaceLayer]  // stable `current` paths, lowest first
    public func start() async                                   // first sync and check; then the host's schedule, if any
    public func stop()
    public func check() async -> [MarketplaceStatus]            // query only; never installs
    public func update(_ id: String? = nil, force: Bool = false) async -> [MarketplaceEvent]
    public func pin(_ id: String, sha: String) async throws
    public func unpin(_ id: String) async throws
    public nonisolated var events: AsyncStream<MarketplaceEvent> { get }
    public nonisolated var layerUpdates: AsyncStream<Void> { get }   // the registry rebuilds on each value
    public nonisolated var diagnostics: [MarketplaceDiagnostic] { get }
}

public enum MarketplaceEvent: Sendable {
    case checked(id: String, current: String, latest: String)
    case updateAvailable(id: String, from: String, to: String)   // autoUpdate off, or checkOnly
    case updated(id: String, from: String?, to: String)          // `current` swapped; the registry reloads
    case failed(id: String, error: String, keptVersion: String?) // the last good snapshot stays
}
```

### 6.3 Configuration

The host gives the source list in code. This follows decision #29: the package names no
directory convention of its own. As a convenience (like `DotfolderStack`), the package also
gives `MarketplaceConfig`. This is a `Codable` file named `marketplaces.yaml`:

```yaml
marketplaces:            # left to right; the last entry wins
  - url: https://github.com/swissarmyhammer/skills.git
  - url: github:acme/team-skills
    ref: stable
    autoUpdate: false
```

- `MarketplaceConfig.load(from: stack)` reads `marketplaces.yaml` from the `user` and
  `project` layers. It appends the project list after the user list, so project entries win.
  If both files name the same id, the project entry replaces the user entry completely. There
  is no field merge.
- **A project file is a trust risk.** A freshly cloned repository can add a remote source.
  The host must load the project file only for a trusted folder. We document this in
  `docs/security.md`. Claude Code has the same gate.

### 6.4 Skill selection

- `.all` (default): every skill in the catalog.
- `.skills([...])`: only the named skills.
- `.plugins([...])`: only the skills of the named plugins. This is useful for a third-party
  catalog that has many plugins. Our own catalog has one plugin.
- A name that is not in the catalog gets a diagnostic. It is not an error.

The materializer copies only the selected skills. Thus a skill that is not selected does not
exist for the registry.

### 6.5 Partial scope

**Problem.** `StencilPass` builds one partials stack from all layers. A skill from
marketplace A can then include `_partials/header.md` from marketplace B, if B is later in the
list.

**Decision:** scope partials by the layer that won. For a skill from marketplace layer *k*,
the partials stack is:

```
url[k]._partials < defaults < user < project
```

- A skill never sees the partials of other marketplaces.
- A local `_partials/` file with the same name still overrides a marketplace partial. This is
  the same "local wins" rule as for skills.
- A skill from a local layer sees only the local layers. Local skills do not include
  marketplace partials. This keeps local skills independent of a remote source.
- Change: `StencilPass.partialsStack(layers:)` takes the winning layer and builds the scoped
  list. It is a small change, and the existing tests cover it.

### 6.6 Trust and execution

| Capability | Local layers (today) | Marketplace layers |
|---|---|---|
| Stencil render | trusted for `.defaults`, else untrusted | **always untrusted** |
| `` !`shell` `` injection | host `RenderPolicy` | **off**, unless `grants.shellInjection` is set for that marketplace |
| `run script` | host policy + `allowed-tools` grants | **off**, unless `grants.scripts` is set for that marketplace; the `allowed-tools` grant is still necessary |

- Today `RenderPolicy` applies to the full registry. The registry must apply the more
  restrictive of the registry policy and the grant of the winning marketplace. This is a
  change in `RenderPipeline` and `ScriptGate`.
- The copied sah skills use no shell injection and no scripts. Thus the default grants have
  no effect on them.

### 6.7 Allowlist and blocklist

`MarketplacePolicy` has:

- `allowedSources: [SourcePattern]?`. When it is not `nil`, a source must match one entry.
  An empty array blocks all sources. Patterns: an exact URL, an owner wildcard
  (`github:swissarmyhammer/*`), or a host regex.
- `blockedSources: [SourcePattern]`.
- The store checks both lists **before any network or disk I/O**. A blocked source gets a
  diagnostic, and it has no layer.

## 7. Cache

### 7.1 Location

The cache follows the model cache pattern (`FoundationModelsACPAgent`'s `ModelResolver` uses
`HF_HUB_CACHE`, then `HF_HOME/hub`, then `~/.cache/huggingface/hub`):

1. `SKILLS_MARKETPLACE_CACHE`, when it is set and not empty.
2. Else `~/.cache/skills/marketplaces`.

A host can also give `cacheDirectory:`. `MarketplaceStore.cacheDirectory(environment:)` is a
pure function of the environment, so tests can give their own.

### 7.2 Layout

The layout follows the Hugging Face hub layout: one folder for each repository, one
`snapshots/<revision>/` folder for each revision, and `refs/` files that name a revision.

```
~/.cache/skills/marketplaces/
├── state.json                              one record for each marketplace (below)
└── swissarmyhammer-skills-1a2b3c4d/
    ├── repo.git/                           bare libgit2 repository; shallow fetch; no work tree
    ├── refs/
    │   └── main                            text file: the SHA that `main` resolved to
    ├── snapshots/
    │   ├── 9f8e7d…(40 hex)/                materialized layer: <skill>/SKILL.md, _partials/
    │   └── 1c2d3e…/                        the previous snapshot, kept for rollback
    ├── current -> snapshots/9f8e7d…        the layer root that the registry reads
    └── lock                                a flock file; one writer across processes
```

`state.json` (written atomically):

```json
{
  "version": 1,
  "marketplaces": {
    "swissarmyhammer-skills-1a2b3c4d": {
      "url": "https://github.com/swissarmyhammer/skills.git",
      "ref": "main", "pinnedSha": null,
      "currentSha": "9f8e7d…", "catalogVersion": "1.2.0",
      "lastChecked": "2026-09-14T19:55:43Z", "lastUpdated": "2026-09-12T08:10:00Z",
      "lastError": null
    }
  }
}
```

### 7.3 Materialize and swap

1. Fetch the commit into `repo.git/` with `GitTransport` (a shallow fetch, `depth = 1`, of the
   pinned `sha` or of the `ref`).
2. Read the catalog blob from the commit tree. Resolve the selection (§6.4).
3. Write the selected skill folders and `_partials/` into `snapshots/<sha>.tmp/`. The files
   come directly from the tree and blob objects (`git_tree_entry_bypath`,
   `git_blob_rawcontent`). There is no checkout and no work tree. A file with mode `100755`
   keeps its execute bit, so `run script` grants still work.
4. Validate while writing. Reject a tree entry name with `..` or `/`, a symlink entry (mode
   `120000`) whose target goes outside the skill folder, a submodule entry (mode `160000`),
   and a size or file count above the policy limits. If validation fails, delete
   `<sha>.tmp/`, keep `current`, and publish `.failed`.
5. Rename `<sha>.tmp/` to `<sha>/`. Write `refs/<ref>`.
6. Make a new symlink `current.new` → `snapshots/<sha>`, then `rename(2)` it over `current`.
   This step is atomic. A reader sees the old snapshot or the new snapshot, never a partial
   one.
7. Write `state.json`. Publish `.updated`.

**Why write from the tree, not a checkout?** A checkout has the repository layout. A
third-party repository can put skills in many folders. The flat snapshot is always a valid
layer root. It contains only the selected skills. Every file goes through the validation in
step 4 before the registry can see it. libgit2 also has no sparse checkout, so a checkout
would write the full repository.

### 7.4 Registry reload

The registry does not depend on the file watcher for marketplace layers. A symlink swap does
not send a reliable event to a `DispatchSource` that has the old target folder open.

- `SkillsRegistry(marketplaces:stack:watch:)` subscribes to `store.events`. On `.updated` it
  runs the same `ReloadCoordinator` rebuild that the watcher uses. The catalog swap, the
  `onReload` stream, and the searcher `update(items:)` all work as they do today.
- The watcher continues to watch the local layers. A `file://` marketplace is a local folder,
  so the watcher also watches it.

### 7.5 Offline and cold start

- The registry is always built from the cache. It never waits on the network.
- Cold start with no cache: the marketplace layer is empty. `store.start()` fetches in the
  background. The first `.updated` event makes the registry reload.
- A fetch fails, but a cache exists: keep the last good snapshot. Publish `.failed` with
  `keptVersion`. Try again at the next check.
- A read-only seed folder (`SKILLS_MARKETPLACE_SEED`) with the same layout gives an offline or
  CI install. The store uses a seed entry when the cache has no entry, and it never updates a
  seed entry.

### 7.6 Cleanup

Cleanup uses no age limit. It is based only on counts:

- After each successful swap, keep `current` and the one previous snapshot for rollback.
  Delete all other snapshots.
- Before a delete, the store takes the `lock` file. A second process that uses the same cache
  holds a shared lock on its `current` target. The store does not delete a locked snapshot.
  This does the same job as the Claude `.in_use/` marker.

## 8. Update checks and automatic update

### 8.1 Check

A check is a cheap remote query. It downloads no skill content:

- git: `GitTransport.remoteHead(url:ref:)` connects a detached remote and reads the ref list
  (`git_remote_ls`). This is the `ls-remote` equivalent. It gives the head SHA of the ref.
  Compare it with `currentSha`.
- Later HTTPS sources: `If-None-Match` with the stored ETag, and the per-skill `digest` in a
  well-known index.

### 8.2 When a check runs

There is no correct hard-coded time. Thus the package has no built-in time value:

- **At start.** `store.start()` checks every marketplace one time.
- **On request.** `check()`, `update()`, and the CLI check immediately.
- **On a schedule, only if the host asks.** `MarketplacePolicy.checkInterval` is `nil` by
  default. When the host sets it, the store also checks at that interval while the process
  runs. A long-running host (an agent server, an editor) can set it. A short CLI run does not
  need it.
- **No duplicate checks.** If a check of a marketplace is in progress, a second request waits
  for the result of the first. It does not start a second remote connection. This needs no
  debounce time.
- **No shared state between processes.** Each process checks at its own start. A check is one
  remote ref listing, and the `lock` file stops two processes from writing the same snapshot.

### 8.3 Update rules

- `autoUpdate: true` (default): a new SHA starts the §7.3 steps, then `.updated`.
- `autoUpdate: false`: publish `.updateAvailable`. The host or the CLI runs `update`.
- A pinned source (`sha:` set, or `pin(_:sha:)`) is never updated automatically. `check`
  still reports that a newer SHA exists.
- `SKILLS_MARKETPLACE_AUTOUPDATE=0` stops all automatic updates. Checks continue. A host can
  also set `MarketplacePolicy.autoUpdate = false`.
- `MarketplacePolicy.checkOnly = true` is a dry run. The store checks and reports. It never
  fetches content.

### 8.4 Running sessions

Claude Code keeps the loaded version until `/reload-plugins`. This package already hot-reloads
by design (plan.md §7). A skill body that a session already used stays in its transcript. A
reload changes only the catalog for later calls. Thus hot reload is the default. A host that
wants a stable session sets `MarketplacePolicy.applyUpdates = .nextLaunch`. Then the store
materializes the new snapshot but swaps `current` only at the next `start()`.

## 9. Provenance, diagnostics, and the CLI

### 9.1 Provenance

- `SkillDiagnostic.Provenance` gets an optional `marketplace` value: the id, the URL, the
  SHA, and the catalog version.
- `list skill` and the `/` command listing can show the source of each skill, for example
  `commit (swissarmyhammer-skills@1.2.0)`.
- A shadow diagnostic names both sides, for example "local `project/.skills/commit` shadows
  `commit` from marketplace `swissarmyhammer-skills`".

### 9.2 The model surface does not change

The model-facing `OperationTool` gets no marketplace operations. Marketplace skills are rows
in the same catalog, so `search skill`, `list skill`, and `use skill` show them with no
change.

### 9.3 CLI

`SkillsCLI` gets a `marketplace` command group. It is a host command, not a model operation:

```
skills marketplace list                   the sources in order, the current SHA, last checked, status
skills marketplace check [<id>]           query only
skills marketplace update [<id>] [--force]
skills marketplace pin <id> <sha>
skills marketplace unpin <id>
skills marketplace add <url> [--ref]      appends to marketplaces.yaml (so it wins over earlier entries)
skills marketplace remove <id>
```

## 10. Security summary (additions to `docs/security.md`)

1. A marketplace is untrusted content. It always renders untrusted. It has no shell
   injection and no scripts unless the host grants them for that marketplace.
2. The allowlist and the blocklist run before any I/O.
3. A project `marketplaces.yaml` can add a remote source. Load it only for a trusted folder.
4. The package does not start the `git` binary. libgit2 runs no hooks, does not fetch
   submodules, and runs no LFS filters. SSH URLs are not supported, thus the package starts
   no `ssh` process. HTTPS uses the system trust store. An HTTPS credential goes only to the origin of its
   source.
5. The materializer rejects path traversal, escaping symlinks, and oversized content.
6. The model cannot change the source list.
7. A remote skill can never replace a local skill. Only local layers shadow marketplace
   layers, and a marketplace can shadow only an earlier marketplace.

## 11. Feature ideas: adopt, defer, or reject

| Idea (source) | Status | Reason |
|---|---|---|
| read `.claude-plugin/marketplace.json` (Claude, Codex, Copilot) | **v1** | the de-facto standard |
| pin by `sha`; `sha` wins over `ref` (Claude) | **v1** | reproducible |
| cheap check with `ls-remote` before a download (`gh skill`, `npx skills`) | **v1** | a check costs no content download |
| keep the last good cache on failure (Claude) | **v1** | offline safety |
| atomic snapshot swap; keep one previous snapshot (Claude cache, HF hub layout) | **v1** | no partial reads; rollback |
| allowlist and blocklist before I/O (Claude `strictKnownMarketplaces`) | **v1** | safe for managed hosts |
| select skills or plugins from a catalog (Claude, `anthropics/skills`) | **v1** | a host takes only what it needs |
| `renames` map (Claude official catalog) | **v1** | cheap; it keeps selections valid |
| `checkOnly` dry run (Claude `--check-only`, `gh skill --dry-run`) | **v1** | cheap |
| read-only seed folder (Claude `CLAUDE_CODE_PLUGIN_SEED_DIR`) | **v1** | offline and CI installs; hermetic tests |
| fixed check interval, start jitter, refresh debounce, age-based cleanup (Claude) | **Reject** | no hard-coded times; §8.2 and §7.6 use events and counts |
| HTTPS `marketplace.json` URL, headers, and a token helper | Later | needs an HTTP fetch path and git-free plugin sources |
| well-known `index.json` with digests (agentskills RFC) | Later | the RFC is a draft; our repository publishes it now |
| `archive` source with `sha256` (Claude) | Later | needs a safe unpacker |
| project lock file `skills-lock.json`, sorted, no timestamps (`npx skills`) | Later | reproducible teams; after pinning works |
| remote blocklist feed with a reason (Claude `blocklist.json`) | Later | a kill switch for a bad skill version |
| token cost for each skill in the catalog (Claude catalog cache) | Later | useful for the `preload` decisions |
| qualified id `marketplace:skill` to reach a shadowed skill | Later | useful; the bare id stays canonical |
| a pre-rendered `dist` branch for plain clients (Claude Code, Codex) | Later | lets Claude Code use the same skills |
| copy `builtin/agents` into the repository | Later | agents are later |
| namespaced-only remote names (Claude, Codex) | **Reject** | it breaks the "local wins by name" requirement |
| `command` source (Claude) | **Reject** | runs arbitrary shell at fetch time |
| `npm` source | **Reject** | no need in this family |
| show both duplicate skills (Codex) | **Reject** | our model is full replace by name |

## 12. Phases

Each phase ends with green tests. The phase ids continue after plan.md M7.

- **MK0 — Extras.** Add `DotfolderStack.Source.marketplace`. Confirm that `StencilPass`
  renders it untrusted.
- **MK1 — Repository and copy.** Make `../skills` with the §3.2 layout. Copy 24 skills and
  8 partials. Do the §3.4 conversions. Add `scripts/generate-catalogs`, `scripts/release`, and
  the §3.6 CI. Tag `v1.0.0`. Do not change sah.
- **MK2 — Catalog and local source.** `MarketplaceSource`, catalog parsing (§5.2), selection,
  renames, identity rules, and the `file://` source as a direct layer.
  `SkillsRegistry(marketplaces:stack:watch:)`. Precedence tests.
- **MK3 — Partial scope and grants.** The §6.5 scoped partials stack. The §6.6 per-marketplace
  grants in `RenderPipeline` and `ScriptGate`.
- **MK4 — Git fetch and cache.** Add the exact `swift-libgit2` dependency. The internal
  `GitTransport` protocol and its libgit2 type (remote head, shallow fetch, tree read,
  cancellation, the HTTPS credential callback). The §7.1 location, the §7.2 layout,
  `state.json`, materialize from the tree and swap, reload on `.updated`, offline rules, the
  seed folder, cleanup, and the lock.
- **MK5 — Checks and automatic update.** Remote-head checks, check at start, the optional host
  interval, coalesced checks, pins, `checkOnly`, `applyUpdates`, and the environment switches.
- **MK6 — Policy, CLI, docs.** Allowlist and blocklist. The `skills marketplace` commands.
  `MarketplaceConfig`. Changes to `docs/security.md`, `docs/operations.md`, and the README.
  A `--marketplace` mode in `skills-demo`.

## 13. Testing

The unit tier stays hermetic. It uses no network (CI requires this).

- **Git fixtures.** A test makes a temporary repository with libgit2 (init, commit, tag). It
  uses a `file://` URL as a git source. This tests the real libgit2 `GitTransport` with no
  network and no `git` binary.
- **Transport double.** The other store tests use a counting `GitTransport` double. It records
  each remote-head call and each fetch.
- **Precedence.** Two marketplaces and a local stack all have a skill `commit`. The local
  skill wins. Remove the local skill: the last URL wins. Reverse the list: the other
  marketplace wins. Each shadow diagnostic names the correct sides.
- **Partial scope.** Marketplaces A and B both ship `_partials/header.md` with different text.
  A skill from A renders A's header. A local `_partials/header.md` overrides both.
- **Untrusted render.** A marketplace skill with a filter or a `{% now %}` tag gets the
  untrusted-rejection diagnostic, even with the `.defaults` layer present.
- **Grants.** A marketplace skill with `` !`echo hi` `` does not run it with default grants. It
  runs when the host grants `shellInjection` for that marketplace.
- **Update cycle.** Commit a change to the fixture repository. `check` reports
  `.updateAvailable`. `update` swaps `current`. The registry reloads once. The searcher gets
  exactly one `update(items:)`. The new body shows. This is the same shape as the hot-reload
  test in plan.md §13.
- **Coalesced checks.** Two concurrent `check()` calls on one marketplace make one remote-head
  call.
- **No time default.** With no `checkInterval`, the store makes no check after `start()`
  until a request comes. The test uses the counting transport double, not a clock.
- **Cancellation.** `stop()` during a fetch of the fixture repository ends the fetch.
  `current` does not change.
- **Tree safety.** Fixture commits with a `..` entry name, an escaping symlink, a submodule
  entry, and an executable script. The first three are rejected. The script keeps its execute
  bit in the snapshot.
- **Failure.** Make the fixture URL unreachable. `update` publishes `.failed` with
  `keptVersion`. The registry keeps the old catalog.
- **Materializer safety.** A fixture skill with a `../escape` symlink, an absolute path, or
  too many files is rejected. `current` does not change.
- **Cleanup.** After three updates, only `current` and one previous snapshot remain.
- **Pin.** A pinned source does not update. `check` still reports the newer SHA.
- **Policy.** A blocked source does no I/O. The counting transport double sees zero calls.
- **Cache location.** `cacheDirectory(environment:)` gives `SKILLS_MARKETPLACE_CACHE` when it
  is set, and `~/.cache/skills/marketplaces` when it is not set.
- **Catalog goldens.** Parse checked-in copies of the `anthropics/skills` catalog, the Claude
  official catalog (with `renames` and `git-subdir` entries), and our own catalog.
- **Copy.** In `../skills` CI: every skill validates, and every skill renders untrusted
  (§3.6).

## 14. Decisions

1. **Marketplaces are below the full local stack.** Order:
   `url[0] < … < url[n] < defaults < user < project`.
2. **Left to right, last wins.** This is the same rule as the `roots:` list.
3. **Remote skills use bare names.** The stack decides. We do not namespace them.
4. **Templates stay Stencil.** The copy converts the few Liquid constructs to Stencil. The
   skills need not work in a plain agentskills.io client.
5. **The `../skills` repository is a copy.** sah does not change.
6. **One plugin in our catalog.** A host selects by skill name when it needs a subset.
7. **One marketplace = one flat, materialized layer root** at a stable `current` path.
8. **A new `DotfolderStack.Source.marketplace` case** in Extras. It always renders untrusted.
9. **Partials are scoped** to the winning marketplace plus the local layers.
10. **Use libgit2, not the `git` binary.** Depend on `danielctull-forks/swift-libgit2`
    (`exact: "1.9.7"`) behind an internal `GitTransport` protocol. SSH URLs are not supported
    (amended 2026-09-18): that package builds no SSH transport on macOS, and an SSH URL gives
    `unsupported URL protocol`. We do not fork the package, and we do not enable its `libssh2`
    trait. Every example uses the HTTPS form.
11. **The store is separate from the registry.** The registry reads only disk. It reloads on a
    store event.
12. **The cache is in `~/.cache/skills/marketplaces`**, with `SKILLS_MARKETPLACE_CACHE` as the
    override. This is the same pattern as the model cache.
13. **No hard-coded times.** Check at start and on request. A periodic check runs only when the
    host gives an interval. Cleanup keeps a count of snapshots, not an age.
14. **Hot reload is the default.** `.nextLaunch` is an option.
15. **Automatic update is on by default.** A pin, a per-source flag, a policy flag, or an
    environment switch turns it off.
16. **No marketplace operations on the model surface.**
17. **`.claude-plugin/marketplace.json` is the primary catalog.** The repository also
    generates the Codex mirror and the well-known index.
18. **Agents are later.**

---

### Sources

- Claude Code plugin marketplaces — https://code.claude.com/docs/en/plugin-marketplaces
- Claude Code plugins reference — https://code.claude.com/docs/en/plugins-reference
- Claude Code discover plugins (auto-update) — https://code.claude.com/docs/en/discover-plugins
- Claude Code settings reference (`extraKnownMarketplaces`, `strictKnownMarketplaces`) — https://code.claude.com/docs/en/settings-reference
- `anthropics/skills` catalog — https://raw.githubusercontent.com/anthropics/skills/main/.claude-plugin/marketplace.json
- Claude Agent Skills (API) — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview
- agentskills.io specification — https://agentskills.io/specification
- agentskills.io client guide — https://agentskills.io/client-implementation/adding-skills-support
- Agent Skills Discovery RFC (well-known index) — https://github.com/cloudflare/agent-skills-discovery-rfc
- OpenAI skills (deprecated; see plugins) — https://github.com/openai/skills
- OpenAI plugins — https://developers.openai.com/plugins/build/plugins
- Vercel `skills` — https://github.com/vercel-labs/skills
- GitHub `gh skill install` / `update` — https://cli.github.com/manual/gh_skill_install, https://cli.github.com/manual/gh_skill_update
- GitHub Copilot plugin marketplace — https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-marketplace
- Cursor plugins — https://cursor.com/docs/reference/plugins
- Local evidence: `~/.claude/plugins/` (`known_marketplaces.json`, `installed_plugins.json`,
  `cache/<mkt>/<plugin>/<version>/.in_use/`, `blocklist.json`, `plugin-catalog-cache.json`)
- libgit2 SwiftPM packaging (selected) — https://github.com/danielctull-forks/swift-libgit2
  (`Package.swift`: SecureTransport; the `GIT_SSH_EXEC` setting has an empty trait list, thus
  SwiftPM never applies it and the build has no SSH transport)
- libgit2 SwiftPM packaging (fallback) — https://github.com/ibrahimcetin/libgit2
- Swift wrappers compared — https://github.com/ibrahimcetin/SwiftGitX,
  https://github.com/danielctull/swift-git, https://github.com/SwiftGit2/SwiftGit2,
  https://github.com/mfcollins3/libgit2-apple
- Model cache pattern: `../FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Doctor/ModelResolver.swift`
  (`HF_HUB_CACHE` → `HF_HOME/hub` → `~/.cache/huggingface/hub`, `snapshots/<revision>/`)
- This package: plan.md (§3, §4, #29), `docs/security.md`,
  `Sources/FoundationModelsSkills/Discovery/SkillDiscovery.swift`,
  `Sources/FoundationModelsSkills/Render/StencilPass.swift`
- Extras: `Sources/FoundationModelsExtras/TemplateEngine.swift` (untrusted whitelist),
  `DotfolderStack.swift` (`Source`), `DotfolderLoader.swift` (`_partials/` resolution)
