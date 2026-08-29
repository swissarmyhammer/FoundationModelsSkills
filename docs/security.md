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
