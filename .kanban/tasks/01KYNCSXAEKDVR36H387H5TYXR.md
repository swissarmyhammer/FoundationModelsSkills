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
The Layer-3 source of truth, static half (plan §3, §6, §7.1; decisions #13/#25/#28). Composes discovery → decode → validate → listing into one catalog built at construction. Reload/watching is the follow-up task "SkillsRegistry reload".

- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`:
  - Init `(stack: DotfolderStack, policy: RenderPolicy)` — builds the catalog once at construction (the reload task adds the `watch:` parameter and rebuild path).
  - Visibility model (§6 table): default = both surfaces; `disable-model-invocation` = user-only; `user-invocable: false` = model-only; `preload: true` = both + body injected; `partial: true`/validation-hidden = neither.
  - `metadata() -> [SkillMetadata]` — id, rendered description AND rendered `metadata.*` values (passes 1+3, never pass 2 — plan §5 "Templated: description, all metadata values, and the body"), parameter summaries, model-visibility flag.
  - `preloadedBodies() -> String` — rendered bodies of `preload: true` skills (through the current pipeline; pass fidelity arrives with the M5 render tasks).
  - `commandListing() -> [SkillListing]` — user-surface rows (§6.1): model-hidden-but-user-invocable included, `user-invocable: false` excluded.
  - `call(id:arguments:) throws -> String` — dereference the catalog, route the body through the render pipeline with arguments; unknown/hidden id throws a typed error carrying current ids (ops convert to correctives later).
  - `diagnostics` — the validator output with provenance.

## Acceptance Criteria
- [ ] Fixture-stack registry: visibility table proven for all four §6 rows (default/`deploy`/`lint`; cover `preload` with a temp-dir skill)
- [ ] `call("commit", arguments:)` plumbing: the supplied arguments reach the pipeline's `RenderRequest` (recording fake pass asserts them) and the body string returns; unknown id throws the ids-carrying error (full `$0` substitution is proven later by the pass-1 task)
- [ ] A fixture frontmatter `metadata.*` value containing `{{ working_directory }}` renders through pass 3, and one containing `` !`echo x` `` stays inert (pass 2 never runs at metadata-build time)
- [ ] `commandListing()` and `metadata()` disagree exactly on the two visibility-split fixtures (`deploy`, `lint`)

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillsRegistryTests.swift` — construction snapshot over fixtures; visibility matrix; call-plumbing + unknown-id error; metadata.* templating cases
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.