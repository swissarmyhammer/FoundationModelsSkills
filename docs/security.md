# Security and platform posture

## Security

- **No OS sandbox in v1.** `` !`shell` `` injection (plan.md §5) and `run
  script` (plan.md §7.3) run as usual child processes with the host's own
  privileges. They get the full environment. There is no filesystem or
  network restriction beyond the script's own working-directory
  discipline. `sandbox-exec` is deprecated API over a private profile
  language. Containment here is gates (host policy plus the skill's
  `allowed-tools` grants) and process control (own process group, timeout
  `SIGKILL`), not an OS sandbox. Examine this again when Apple ships a
  supported per-process confinement API.
- **Untrusted layers render untrusted.** Only the layer a host tags
  `.defaults` (shipped, consumer-controlled content) renders
  Stencil-trusted. Each user or project layer renders through the
  untrusted path in `FoundationModelsExtras`: a tag and filter whitelist,
  plus include-depth, output-size, and iteration budgets. These budgets
  bound the *template* pass only. Shell injection and scripts have their
  own gates, and Stencil trust never grants them. The budgets apply for
  each *render*: a body renders as one template. The pipeline gives each
  substituted argument value and each shell output to Stencil as an opaque
  context value, not as template text. Thus `{% if %}…{% endif %}` can
  straddle a `$N` splice, a spliced value can never become template
  syntax, and a splice *inside* a variable, tag, or comment (`{{ $1 }}`,
  `{% if $1 %}`, `{# $1 #}`) is a rendering error.
- **Server-side providers see the transcript.** A rendered skill body —
  with all environment variables exposed and shell output inlined — goes
  off-device if a session routes to a cloud provider. The search agent
  sees only metadata, not rendered bodies. This limits exposure during
  discovery. A used skill's full rendered body goes to the provider. This
  is a deliberate, accepted trade for the on-device-Mac use case.
- **Trust-gate untrusted project layers yourself.** A project `.skills/`
  directory from a freshly cloned repository can inject instructions into
  a session. `SkillsRegistry` gets its layer roots as a plain,
  caller-supplied list. It has no opinion about which directories are
  safe. Thus a host must only construct a registry (specially a
  script-enabled one) over roots it trusts. Each `SkillDiagnostic`
  carries the winning layer's provenance
  (`SkillDiagnostic.Provenance.root`), thus a host can show *where* a
  skill came from.

## Marketplaces

A marketplace is a git repository, or a folder on this computer, that gives a
skill layer below the full local stack. [`marketplaces.md`](marketplaces.md) is
the host guide. These are the rules that hold for every marketplace:

1. **A marketplace is untrusted content.** It always renders untrusted. Its
   skills have no `` !`shell` `` injection and no scripts, unless the host sets
   a grant for that one marketplace. The host `RenderPolicy` always wins: a
   grant can only keep a capability that the host left on, and the
   `allowed-tools` grant of the skill is still necessary.
2. **The allow-list and the block-list run before any I/O.**
   `MarketplacePolicy.allowedSources` and `MarketplacePolicy.blockedSources`
   are pure functions of the URL. A refused source gets a diagnostic, and the
   store makes no cache folder and opens no connection for it.
3. **A project `marketplaces.yaml` can add a remote source.** A repository that
   you cloned can carry that file. Load it only for a folder that you trust.
   The `skills marketplace` commands read it only with `--include-project`.
4. **The package does not start the `git` binary.** Git work goes through
   libgit2, which runs no hooks, fetches no submodules, and runs no large file
   storage filters. HTTPS uses the system trust store. SSH URLs are not
   supported: the libgit2 build has no SSH transport, thus the package starts
   no `ssh` process, and an SSH URL gives the diagnostic
   `unsupported URL protocol`.
5. **A credential stays out of every record.** A credential never appears in a
   stored URL, in a log line, in a diagnostic, or in an error message. An HTTPS
   URL that holds a user name or a password is refused when the store parses
   it, thus no such URL reaches `marketplaces.yaml`, `state.json`, a command
   line of output, or a message. A credential comes only from
   `MarketplacePolicy.credentials`, and the transport sends it only to the
   origin of that one source.
6. **The materializer validates every file that it writes.** It refuses a path
   that holds `..` or `/`, a symlink that points out of the skill folder, a
   submodule entry, and content above the size and file-count limits of the
   policy. A snapshot that fails validation is deleted, and the last good
   snapshot stays.
7. **The model cannot change the source list.** The model surface gets no
   marketplace operation. Only the host and the command line add, remove, pin,
   or update a marketplace.
8. **A remote skill can never replace a local skill.** The order is
   `url[0] < … < url[n] < defaults < user < project`. Only a local layer
   shadows a marketplace, and a marketplace can shadow only a marketplace that
   is before it in the list.

## Context compaction (note for hosts)

A used skill's rendered body is durable guidance. The session depends on
it for the remainder of the conversation. A host that summarizes or
prunes its own transcript must keep skill tool outputs out of that
pruning. This package has no opinion on transcript management, but if a
host silently drops a skill's body in the middle of a conversation, the
skill's behavior silently degrades.

## Platform

- **macOS is the primary, fully supported platform**: argument
  substitution, shell injection, environment and Stencil templating, and
  scripts all work.
- **iOS is unsupported, not stubbed.** A graceful "unavailable on
  platform" runtime stub is only possible when each dependency in the
  graph declares an iOS floor. Two of this package's three sibling
  dependencies (`FoundationModelsExtras`,
  `FoundationModelsMetadataRegistry`) are macOS-only, thus no iOS build
  of this package is possible at all. See the doc comment on the
  `FoundationModelsSkills` namespace enum
  (`Sources/FoundationModelsSkills/FoundationModelsSkills.swift`) for the
  full record of which dependency causes this.
