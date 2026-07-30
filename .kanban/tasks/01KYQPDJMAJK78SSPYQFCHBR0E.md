---
comments:
- actor: claude-code
  id: 01kyrkwy9sch8w3kf08avv6w0z
  text: |-
    All three gaps were behavior-already-correct, test-only closures (no product code changes needed):

    1. Discovery depth: added `nestedTwoLevelsBelowRootIsNotDiscovered` (root/a/b/SKILL.md) and `aSkillFileDirectlyAtTheRootItselfIsNotDiscovered` (root/SKILL.md) to `SkillDiscoveryTests.swift`, pinning `SkillDiscovery`'s existing one-level-only, never-the-root-itself scan.
    2. Surplus trailing args: added `useSkillWithMoreArgumentsThanDeclaredSucceedsAndAutoAppendsTheSurplus` to `SkillOperationsTests.swift` using the existing `makeTempContext` helper (a skill declaring one named arg whose body references only `$0`, never bare `$ARGUMENTS`) — supplies two arguments, asserts success plus the literal `ARGUMENTS: production extra-flag` auto-append tail.
    3. Post-reload diagnostics for a genuinely broken skill: added `reloadIntroducingAGenuinelyMalformedYAMLSkillSurfacesASkipDiagnostic` to `SkillsRegistryReloadTests.swift`, distinct from the existing `reloadRefreshesPreloadedBodiesAndDiagnostics`'s missing-description (`.warning`) case — this one reuses the unparseable-YAML fixture shape from `DiagnosticsRenderingTests` (unterminated `[` in `name:`) and confirms the resulting `.skip` diagnostic surfaces after a live reload, not just at construction.

    `swift build --build-tests` clean; `swift test` 318/318 passed (314 + 4 new). Committing checkpoint next.
  timestamp: 2026-07-30T04:18:09.337418+00:00
position_column: doing
position_ordinal: '80'
title: Close remaining audit test gaps (discovery depth, trailing args, reload surfaces)
---
## What
Remaining behavior-is-correct-but-unpinned gaps from the plan audit, bundled:

1. **Discovery depth bound**: no test proves `root/a/b/SKILL.md` is NOT discovered and `root/SKILL.md` (at the root itself) is ignored — a future switch to a recursive enumerator would regress silently (`SkillDiscoveryTests.swift:73-126`; behavior at `Discovery/SkillDiscovery.swift:129-137`).
2. **Extra trailing args through the operation**: §7 mandates extras "ride the §5 ARGUMENTS: auto-append, never an error", but no test over-supplies arguments to `UseSkill` (`SkillOperationsTests.swift:149-169` covers missing/exact only; auto-append tested only at the pipeline layer).
3. **Post-reload `diagnostics`**: the reload suite asserts `metadata()`/`commandListing()`/`call` freshness but never that `diagnostics` reflects the post-reload generation (`SkillsRegistryReloadTests.swift`) — e.g. a reload that introduces a broken skill must surface its diagnostic. (Post-reload `preloadedBodies` is covered by the hot-reload integrity task.)

## Acceptance Criteria
- [ ] Nested and root-level `SKILL.md` non-discovery pinned
- [ ] `use skill` with surplus args succeeds and the rendered body carries the `ARGUMENTS:` auto-append
- [ ] A reload introducing a broken-YAML skill surfaces its diagnostic in `registry.diagnostics`

## Tests
- [ ] Extend `SkillDiscoveryTests.swift`, `SkillOperationsTests.swift`, `SkillsRegistryReloadTests.swift` as above
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — these ARE tests; any product-code fix they force is in scope.