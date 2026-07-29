---
position_column: todo
position_ordinal: a380
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