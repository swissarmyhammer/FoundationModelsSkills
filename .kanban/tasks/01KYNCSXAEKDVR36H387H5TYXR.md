---
depends_on:
- 01KYNCRETZJCE9AH8HVZXZSG3Y
- 01KYNCRS3QJFK120446YNXYAH7
- 01KYNCS3K5T60E4JQAJ8JQWXC5
position_column: todo
position_ordinal: '8880'
title: 'SkillsRegistry static core: build, visibility, call, listing'
---
## What
The Layer-3 source of truth, static half (plan §3, §6, §7.1; decisions #13/#25/#28, and #29 as amended 2026-07-28: **the registry takes its layer roots as a construction parameter** — an ordered list, lowest precedence first — and holds no opinion about where skills live). Composes discovery → decode → validate → listing into one catalog built at construction. Reload/watching is the follow-up task "SkillsRegistry reload".

- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`:
  - Init `(roots: [URL], policy: RenderPolicy)` — ordered roots, lowest precedence first, last-root-wins; builds the catalog once at construction (the reload task adds the `watch:` parameter and rebuild path). Do NOT name `.skills`, `~`, or `.config` anywhere in the registry — those are host policy. A convenience init taking a `DotfolderStack` (via the discovery task's helper) keeps §10's one-liner working; `FoundationModelsACPAgent`-style hosts pass `[~/.skills, <cwd>/.skills]` literals themselves.
  - Visibility model (§6 table): default = both surfaces; `disable-model-invocation` = user-only; `user-invocable: false` = model-only; `preload: true` = both + body injected; `partial: true`/validation-hidden = neither.
  - `metadata() -> [SkillMetadata]` — id, rendered description AND rendered `metadata.*` values (passes 1+3, never pass 2 — plan §5 "Templated: description, all metadata values, and the body"), parameter summaries, model-visibility flag.
  - `preloadedBodies() -> String` — rendered bodies of `preload: true` skills (through the current pipeline; pass fidelity arrives with the M5 render tasks).
  - `commandListing() -> [SkillListing]` — user-surface rows (§6.1): model-hidden-but-user-invocable included, `user-invocable: false` excluded.
  - `call(id:arguments:) throws -> String` — dereference the catalog, route the body through the render pipeline with arguments; unknown/hidden id throws a typed error carrying current ids (ops convert to correctives later).
  - `diagnostics` — the validator output with winning-root provenance.

## Acceptance Criteria
- [ ] Fixture-root registry: visibility table proven for all four §6 rows (default/`deploy`/`lint`; cover `preload` with a temp-dir skill)
- [ ] `call("commit", arguments:)` plumbing: the supplied arguments reach the pipeline's `RenderRequest` (recording fake pass asserts them) and the body string returns; unknown id throws the ids-carrying error (full `$0` substitution is proven later by the pass-1 task)
- [ ] A fixture frontmatter `metadata.*` value containing `{{ working_directory }}` renders through pass 3, and one containing `` !`echo x` `` stays inert (pass 2 never runs at metadata-build time)
- [ ] `commandListing()` and `metadata()` disagree exactly on the two visibility-split fixtures (`deploy`, `lint`)
- [ ] No `.skills`/`.config`/`~` literal appears in registry source (greppable) — roots come from the caller only

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillsRegistryTests.swift` — construction snapshot over fixture roots; visibility matrix; call-plumbing + unknown-id error; metadata.* templating cases; no-convention-literal grep check
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.