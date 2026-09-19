# Marketplaces

A marketplace is a git repository, or a folder on this computer, that holds
skills. `MarketplaceStore` keeps each marketplace in a cache, and it gives one
skill layer for each marketplace to `SkillsRegistry`. Each marketplace layer is
below the full local stack, thus a local skill always wins over a marketplace
skill of the same name.

This page is the host guide. It tells you how to add a marketplace, what the
store does with it, and what the `skills marketplace` commands do. Read
[`security.md`](security.md) for the security posture of a marketplace.

## Add a marketplace in code

The host gives the source list. The package names no directory convention of
its own.

```swift
import FoundationModelsSkills

// Left to right: the last source wins over the sources before it.
let store = MarketplaceStore(sources: [
    MarketplaceSource("https://github.com/swissarmyhammer/skills.git"),
    MarketplaceSource("github:acme/team-skills", autoUpdate: false),
])

let stack = DotfolderStack(
    name: "skills",
    workingDirectory: projectDirectory,
    defaultsDirectory: shippedSkillsURL,
    userDirectory: userConfigURL)

// This call reads only the cache. It never waits on the network.
let registry = SkillsRegistry(marketplaces: store, stack: stack, watch: true)

// Fetch a cold cache and check each remote one time. The registry rebuilds
// its catalog on each update.
await store.start()
```

`MarketplaceSource` has these fields:

| Field | Meaning |
|---|---|
| `url` | The location of the marketplace, in one of the forms below. |
| `ref` | A branch or a tag. It wins over a `#ref` suffix on `url`. |
| `sha` | A commit pin. It wins over `ref`, and it stops the automatic update. |
| `path` | A subfolder of the repository. The store reads only that path. |
| `alias` | A local name. When you set it, it is the pre-fetch key. |
| `select` | The skills to take: `.all`, `.plugins([…])`, or `.skills([…])`. |
| `autoUpdate` | Whether the store installs a new commit when it finds one. The default is `true`. |
| `grants` | What the skills of the marketplace can run. The default is `.none`. |

## Add a marketplace in `marketplaces.yaml`

`MarketplaceConfig` reads the same list from a file with the name
`marketplaces.yaml`. The file is a convenience, like `DotfolderStack`.

```yaml
marketplaces:            # left to right; the last entry wins
  - url: https://github.com/swissarmyhammer/skills.git
  - url: github:acme/team-skills
    ref: stable
    autoUpdate: false
```

`MarketplaceConfig.load(from:includeProject:)` reads the file of the user
layer. With `includeProject: true`, it also reads the file of the project
layer, and it puts the project list after the user list. Thus a project entry
wins.

**A project file is a trust risk.** A repository that you cloned can add a
remote source with that file. Read the project file only for a folder that you
trust.

## The order of the layers

The store gives its layers to the registry below the local stack. The full
order is:

```
url[0] < … < url[n] < defaults < user < project
```

The last layer wins. Thus a marketplace can shadow only a marketplace that is
before it in the list, and every local layer shadows every marketplace. The
winner replaces the full skill folder. There is no merge.

The source of each marketplace layer is
`DotfolderStack.Source.marketplace`. That tag, and not the position of the
layer, is what makes the layer render untrusted and what scopes its partials.

## Source forms

| Form | Example |
|---|---|
| git HTTPS | `https://github.com/swissarmyhammer/skills.git` |
| GitHub shorthand | `github:swissarmyhammer/skills` |
| git repository on this computer | `file:///Users/me/skills.git` |
| folder on this computer | `file:///Users/me/skills` |
| ref suffix on a git form | `…/skills.git#v1.2.0` |

**SSH URLs are not supported.** The libgit2 build of this package has no SSH
transport. The parser accepts an SSH URL, but the store cannot connect to it:
the check and the fetch fail, and the diagnostic is `unsupported URL protocol`.
Use the HTTPS form of the same repository. For a private repository, give a
token through `MarketplacePolicy.credentials`.

The parser applies these rules to a URL:

- A git URL must end in `.git`. The suffix tells a `file://` repository, which
  the transport fetches, from a `file://` folder, which the store reads
  directly.
- An HTTPS URL that holds a user name or a password is refused. A credential
  comes from `MarketplacePolicy.credentials`, and never from a URL.
- A folder on this computer has no ref and no commit. A `ref`, a `sha`, or a
  `#ref` suffix on such a URL is refused.
- The GitHub shorthand must be `github:owner/repo`.

A folder on this computer is the layer root itself. The store makes no copy, it
keeps no cache entry, and it fetches nothing. A `watch: true` registry watches
that folder as it watches a local layer.

## Identity

- Before a fetch, the store knows only the source. Thus it uses a **pre-fetch
  key**: the alias, if you give one, else the last path component of the
  repository without `.git`.
- A pre-fetch key must be one folder name. An empty key, or a key with a `/`
  character or a NUL character, is refused.
- Two sources with the same pre-fetch key are a configuration error. The store
  refuses the full list, and it gives one diagnostic. Give one of the two
  sources an alias.
- The name of the cache folder is `<pre-fetch key>-<first 8 hex digits of the
  SHA-256 of the normalized URL>`. Thus a changed URL never uses a stale cache.
- After a fetch, the `name` field of the catalog is the **display id** of the
  marketplace. The commands and the diagnostics show that id.

## Catalog formats

The store looks for these, in order, and it uses the first that it finds:

1. `.claude-plugin/marketplace.json`.
2. `.agents/plugins/marketplace.json`, the Codex mirror. The same rules apply.
3. No catalog: a scan of the repository for `SKILL.md` files, to a depth of
   three path components. The more shallow `SKILL.md` wins.

The skills of a plugin are the entries of its `skills` array. When the plugin
has no such array, they are the folders of `<plugin source>/skills/` that hold
a `SKILL.md` file. A plugin with a remote source gets a diagnostic, and the
store skips it. The store also reads the `renames` map of a catalog: a selected
name that the catalog renamed maps to the new name, and a name that the catalog
removed selects nothing.

## Skill selection

- `.all` is the default. It takes every skill of the catalog.
- `.skills([…])` takes only the named skills.
- `.plugins([…])` takes only the skills of the named plugins.

The store copies only the selected skills into the snapshot. Thus a skill that
you did not select does not exist for the registry. A name that is not in the
catalog gets a diagnostic. It is not an error.

## The cache

The cache directory is:

1. `SKILLS_MARKETPLACE_CACHE`, when the variable is set and is not empty.
2. Else `~/.cache/skills/marketplaces`.

A host can also give `cacheDirectory:` to `MarketplaceStore`.
`MarketplaceStore.cacheDirectory(environment:)` is a pure function of the
environment, thus a test can give its own.

Each marketplace has one folder in the cache:

```
~/.cache/skills/marketplaces/
├── state.json                              one record for each marketplace
└── swissarmyhammer-skills-1a2b3c4d/
    ├── repo.git/                           bare repository; a shallow fetch
    ├── refs/main                           the commit that `main` resolved to
    ├── snapshots/<commit>/                 the materialized layer
    ├── current -> snapshots/<commit>       the layer root that the registry reads
    └── lock                                one writer at a time
```

The store writes the selected skill folders and the `_partials/` folder of the
marketplace into `snapshots/<commit>.tmp/`, directly from the objects of the
commit. There is no checkout and no work tree. The store refuses a tree entry
name that holds `..` or `/`, a symlink that points out of the skill folder, a
submodule entry, and content above the limits of
`MarketplacePolicy.snapshotLimits`. Then it renames the folder, makes a new
`current` symlink, and renames that symlink over the old one. That last step is
atomic: a reader sees the old snapshot or the new snapshot, and never a part of
one.

Cleanup uses counts, and no age limit. After each install, the store keeps
`current` and the one snapshot before it, and it deletes the others. A reader
holds a shared lock on the snapshot that it serves, thus cleanup in a second
process keeps that snapshot.

The writer lock never waits. When a second writer holds the folder of a
marketplace, the call does no work at all, the store keeps the snapshot that it
serves, and it tries again at the next pass. A wait would hold the thread of
the actor that the holder of the lock needs.

## The seed folder

`SKILLS_MARKETPLACE_SEED` names a read-only folder with the same layout as the
cache. The store uses a seed entry when the cache holds no snapshot of that
marketplace. It never writes the seed folder, and it never updates a
marketplace that the seed folder serves. Thus an offline install, or a CI
machine, can start with skills and with no network.

## Checks and updates

A check is a cheap query of the remote. It downloads no skill content: the
store connects a detached remote, reads the ref list, and compares the head
commit with the commit of the snapshot.

The package has no built-in time value. A check runs:

- **At start.** `store.start()` checks each marketplace one time.
- **On request.** `check()`, `update()`, and the commands below check at once.
- **On a schedule, only when the host asks.** `MarketplacePolicy.checkInterval`
  is `nil` by default. A long-running host, such as an agent server or an
  editor, can give a value. A short command-line run does not need one.

When a check of a marketplace is in progress, a second request waits for the
result of the first. It opens no second connection to the remote.

The update rules are:

- `autoUpdate: true` is the default. A new commit starts an install, and the
  store then publishes `.updated`.
- `autoUpdate: false` publishes `.updateAvailable`. The host, or the
  `marketplace update` command, installs the commit.
- `SKILLS_MARKETPLACE_AUTOUPDATE=0` stops every automatic update. Checks
  continue. `MarketplacePolicy.autoUpdate = false` does the same.
- `MarketplacePolicy.checkOnly = true` is a dry run. The store checks and
  reports, and it fetches no content.
- A fetch that fails keeps the last good snapshot. The store publishes
  `.failed` with the commit that stays.

`MarketplacePolicy.fetchTimeout` is `nil` by default. With a value, a fetch
that takes longer is cancelled, and the store keeps the snapshot that `current`
names.

## Pins

A pin holds one marketplace at one commit. Set the `sha` field of the source,
or call `store.pin(_:sha:)`. `store.unpin(_:)` drops the pin, and the
marketplace follows its ref again. The store records a pin in `state.json`,
thus the pin holds in a later run of the host too. A pinned marketplace is
never updated automatically, and a check still reports that a newer commit
exists.

`MarketplacePolicy.applyUpdates` says when a new snapshot becomes the snapshot
that the registry reads:

- `.immediately` is the default. The registry rebuilds its catalog while the
  process runs, because this package hot-reloads by design.
- `.nextLaunch` materializes the new snapshot and records it as pending. The
  next `start()` makes `current` name it. Thus a session keeps the catalog that
  it started with. The pending record lives in `state.json`, thus it is a flag
  on the disk and no timer, and it holds after a restart.

## Trust and grants

A marketplace layer always renders untrusted. Its skills have no shell
injection and no scripts, unless you set a grant for that marketplace:

```swift
MarketplaceSource(
    "github:acme/team-skills",
    grants: MarketplaceGrants(shellInjection: true, scripts: true))
```

The host `RenderPolicy` always wins. A grant can only keep a capability that
the host left on. It can never turn on a capability that the host turned off.
The `allowed-tools: Script(<glob>)` grant of the skill is still necessary too.

## Partial scope

A skill of a marketplace layer resolves `{% include %}` over this stack:

```
url[k]._partials < defaults < user < project
```

Thus a skill never reads a partial of a different marketplace, and a local
`_partials/` file with the same name still wins. A skill of a local layer sees
only the local layers: an include of a name that only a marketplace has is a
render error, and not the text of that marketplace.

## The allow-list and the block-list

`MarketplacePolicy` holds two lists of `SourcePattern` values:

- `allowedSources` is `nil` by default, which permits every source. With a
  list, a source must match one entry of the list. An empty list refuses every
  source.
- `blockedSources` is empty by default. A source that matches one entry gets no
  layer, whatever the allow-list says.

A pattern is an exact URL (`.exact`), an owner on a host (`.owner`), a regular
expression for the host (`.hostRegex`), or a path prefix for a source on this
computer (`.pathPrefix`).

The store applies both lists **before any network work and any disk work**. A
refused source gets a diagnostic, and it has no layer.

## Provenance

`MarketplaceProvenance` names the marketplace of each skill: the display id,
the URL of the source, the commit, and the version of the catalog. The `/`
command listing shows the text of that provenance, for example
`swissarmyhammer-skills@1.2.0`, and `SkillMetadata.source` holds the same text
for a host. The model-facing `search skill` and `list skill` lines give the id
and the description only. The text never holds the URL. A
shadow diagnostic names both sides, thus a user can see that a local skill
shadows a marketplace skill.

## The `skills marketplace` commands

Marketplace control is a host function. The model surface gets no marketplace
operation; see [`operations.md`](operations.md).

```
skills marketplace list                      the marketplaces in order, with the id, the URL,
                                             the commit, the catalog version, the last check,
                                             and the status
skills marketplace check [<id>]              asks each remote for its head; downloads no content
skills marketplace update [<id>] [--force]   brings a marketplace to its remote head
skills marketplace pin <id> <sha>            holds a marketplace at one commit
skills marketplace unpin <id>                drops the pin
skills marketplace add <url> [--ref <ref>] [--alias <alias>]
                                             puts a source at the end of the user file
skills marketplace remove <id>               takes a source out of the user file
```

Each command reads the `marketplaces.yaml` of the user layer. A command reads
the file of the project layer only with `--include-project`, which is the trust
gate of a cloned repository. `add` and `remove` write the user file only,
because a source of the project layer belongs to the repository, and not to
this user.

`add` parses the URL before it writes. Thus a URL that holds a credential never
reaches the file, and no message shows it.

The `--marketplace` mode of `Examples/skills-demo` runs this same command group
over the fixture library, for example `skills-demo --marketplace list`.

## Publish a marketplace

Use the layout of the `swissarmyhammer/skills` repository:

```
skills/                                   repository root
├── .claude-plugin/marketplace.json       the primary catalog
├── .agents/plugins/marketplace.json      the Codex mirror, generated
├── .well-known/agent-skills/index.json   the discovery index, generated
└── skills/                               ONE layer root
    ├── _partials/                        the Stencil partials of this marketplace
    ├── commit/SKILL.md
    └── …
```

Each skill is a direct child of one `skills/` folder, and the `_partials/`
folder is in that folder too. Thus `skills/` is a valid layer root, and
discovery skips `_partials/`, because that folder holds no `SKILL.md` file.

Use one plugin that lists every skill, with `"source": "./"` and an explicit
`skills` array. Generate the array from the folders, and do not write it by
hand. Give the catalog a `metadata.version`, and make each release tag `vX.Y.Z`
equal to that version.
