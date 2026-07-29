---
comments:
- actor: claude-code
  id: 01kypnz20m9je6w6r51sa9ckzf
  text: |-
    Implemented via TDD. Wrote Tests/FoundationModelsSkillsTests/SkillsRegistryTests.swift first (RED — confirmed compile failure referencing not-yet-existing SkillsRegistry/UnknownSkillError), then implemented Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift (GREEN — all 12 new tests + full 162-test suite pass, `swift test` exit 0).

    Design decisions worth recording:
    - Task text says the DotfolderStack convenience init should go "via SkillDiscovery's existing DotfolderStack->roots helper" — i.e. SkillDiscovery.roots(from:), which only extracts bare URLs and discards each layer's Source (.defaults/.user/.project) tag. So there is genuinely no way for SkillsRegistry to know which host-supplied root (if any) is a trusted "shipped defaults" directory, regardless of construction path. Resolved this by having the registry synthesize every root into an untrusted DotfolderStack.Layer(source: .project, root:) internally — a safe, conservative default (matches §8's "hosts should still trust-gate untrusted project layers" posture) — documented explicitly in both init doc comments so it's not a silent surprise.
    - Visibility computed via a small ResolvedVisibility struct with 3 independent boolean formulas (validator eligibility AND frontmatter opt-out/opt-in per axis), doc-commented with the literal plan.md §6 table for traceability — data-driven per the task's own guidance rather than an if/else chain.
    - All four §6 visibility rows proven directly against real fixtures: default=spec-clean, disable-model-invocation=deploy, user-invocable:false=lint, preload:true=git-context (git-context already had preload:true, so no temp-dir fixture was needed for that row).
    - metadata.* templating (the {{ working_directory }} renders / !`echo x` stays inert acceptance criterion) needed a temp-dir-constructed fixture since no existing Examples/skill-library fixture has metadata.* values with templating syntax — added one inline in the test file (writeMetadataTemplatingSkill helper), consistent with SkillDiscoveryTests' own temp-dir-fixture pattern, rather than touching the shared Examples library.
    - call(id:arguments:) throws UnknownSkillError for BOTH a truly-unknown id and a validator-hidden id (partial:true) — the catalog never stores a validator-hidden skill at all, so the two cases collapse naturally into the same dictionary-miss without needing a separate isHidden check in call() itself.
    - Confirmed via `grep`-style test (registrySourceNamesNoDotfolderConventionLiteral) that SkillsRegistry.swift never spells ".skills", ".config", or "~" anywhere, including doc comments — had to phrase trust/layer doc comments abstractly to avoid these literals.

    No dead ends worth recording — the design came together cleanly on the first pass once the DotfolderStack.Layer/Source trust question above was resolved.

    Verification: `swift test` — 162/162 tests pass, exit 0. Local `mcp__sah__review` (working diff) — 0 findings. A self-review fork checked the five review-history categories (doc-comment convention, nesting depth, near-duplicate blocks, boolean naming, caller-history references) and found only two minor missing doc comments in the test file's private helpers, which were fixed. An adversarial double-check pass was also run per the really-done gate; its verdict will be recorded in a follow-up comment.
  timestamp: 2026-07-29T10:15:46.964842+00:00
- actor: claude-code
  id: 01kypt27dtdc4gk2ht99rqq6es
  text: |-
    Adversarial double-check (really-done gate) ran twice, per the "bound the loop" rule:

    Round 1 verdict: REVISE, 4 findings:
    1. (High) init(stack:policy:) was discarding DotfolderStack's real per-layer Source (.defaults/.user/.project), silently downgrading a shipped-defaults layer to untrusted Stencil rendering.
    2. (Medium) The try? render-failure fallback in renderedMetadataText/renderedBody was completely untested.
    3. (Medium) renderedMetadataFields only rendered top-level .string metadata values, never nested .array/.dictionary string scalars.
    4. (Low) The preload:true + disable-model-invocation:true combination was unproven.

    Fixed all four: refactored construction to a shared private init(layers:policy:) so init(stack:) now passes stack.layers straight through (preserving real trust tags) while init(roots:) still synthesizes uniformly untrusted layers (the only option from a bare [URL]); added a differential test proving the two paths now diverge correctly (stackConvenienceInitRendersTheDefaultsLayerTrustedUnlikeTheSameDirectoryPassedAsABareRoot); added a genuine-render-failure fallback test (metadataRenderFailureFallsBackToUnrenderedTextRatherThanThrowing, using a real Stencil `| uppercase` filter untrusted rendering's empty whitelist rejects); replaced renderedMetadataFields with a recursive renderedMetadataValue that handles .array/.dictionary at any depth; added preloadInjectsTheBodyEvenWhenTheSameSkillIsModelHidden proving the three visibility axes compose independently.

    Round 2 verdict: REVISE, 1 low finding (the new .dictionary recursion branch was implemented but not exercised by any test -- only .array was proven). Fixed by extending the existing metadata-templating fixture with a nested-mapping field and asserting its rendered value.

    Also worth recording: the local mcp__sah__review tool proved noisy/non-deterministic on this file -- repeated "review file" calls on the identical unchanged SkillsRegistry.swift returned wildly different results across runs (29 doc-comment "missing period" findings on one run, 18 different ones on the next, 0 on a third), and some flagged lines were already period-terminated single-physical-line comments, which is clearly a false positive. Verified this wasn't a real convention violation by checking that already-merged sibling files (e.g. SkillDiscovery.swift) with the identical multi-physical-line summary-sentence style get zero findings. Did NOT chase that noise. One genuine finding *did* surface in the same noisy batch and was fixed on its merits: `.sorted { $0.id < $1.id }` was triplicated verbatim across metadata()/commandListing()/preloadedBodies() -- extracted a shared `sortedCatalogEntries(where:)` helper.

    Final state: 165/165 tests pass (`swift test`, exit 0, up from the pre-existing 162), `swift build --build-tests` clean, `mcp__sah__review working` clean on the latest diff. Task remains in `doing` per /implement's process -- ready for /review.
  timestamp: 2026-07-29T11:27:25.114862+00:00
depends_on:
- 01KYNCRETZJCE9AH8HVZXZSG3Y
- 01KYNCRS3QJFK120446YNXYAH7
- 01KYNCS3K5T60E4JQAJ8JQWXC5
position_column: done
position_ordinal: 8b80
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
- [x] Fixture-root registry: visibility table proven for all four §6 rows (default/`deploy`/`lint`; cover `preload` with a temp-dir skill)
- [x] `call("commit", arguments:)` plumbing: the supplied arguments reach the pipeline's `RenderRequest` (recording fake pass asserts them) and the body string returns; unknown id throws the ids-carrying error (full `$0` substitution is proven later by the pass-1 task)
- [x] A fixture frontmatter `metadata.*` value containing `{{ working_directory }}` renders through pass 3, and one containing `` !`echo x` `` stays inert (pass 2 never runs at metadata-build time)
- [x] `commandListing()` and `metadata()` disagree exactly on the two visibility-split fixtures (`deploy`, `lint`)
- [x] No `.skills`/`.config`/`~` literal appears in registry source (greppable) — roots come from the caller only

## Tests
- [x] `Tests/FoundationModelsSkillsTests/SkillsRegistryTests.swift` — construction snapshot over fixture roots; visibility matrix; call-plumbing + unknown-id error; metadata.* templating cases; no-convention-literal grep check
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-07-29 06:30)

Clean — `review sha HEAD~1..HEAD` returned zero findings (14 checks attempted, 0 confirmed, 0 refuted).