---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5abykzv50b20xtg5pk4ersd
  text: |-
    Research (implement step):
    - No string-distance helper in FoundationModelsExtras (incl. Operations) or FoundationModelsRanker. Ranker has only Trigram.dice (Sørensen-Dice), and this package does not depend on Ranker directly. So a small Levenshtein lives in this package.
    - Once the `id` enum goes, `SkillsToolSchema.make` is exactly `SchemaFusion.fuse(operations, name:, description: nil)` from Operations: same op enum, same `OperationKeys.opFieldDescription` text, same field order. Plan: SkillsToolSchema delegates to `SchemaFusion.fuse` with no root description (the one reason the type still exists: the catalog is not in the prompt twice), and the copied fieldUnion/typeSchema go.
    - `SkillsCatalogTool.skillIDs` (public) stays: FoundationModelsAgents tests (`SkillsToolSharingTests`) read it as the ids visible when the tool was made. It no longer feeds the schema; its doc comment changes to say so.
    - The two unusable-id correctives (`UseSkill.unusableIDMessage`, `ResourceIDLookup.unusableIDMessage`) are copies. Plan: one shared text builder used by both, so `use skill` and the resource ops give the same corrective.
    - Tests that pin the old corrective wording ("Currently usable ids: ...", alphabetical) are in SkillOperationsTests, UseSkillPlainTextTests, ResourceOpsTests, ResourceIDLookupTests, SkillsCLITests, HotReloadTests; docs/operations.md shows the old text too.
    - A reload happens only through the watcher (`watch: true`), so the reload-added test follows the SkillsTelemetryTests pattern (`ReloadTestSupport.tally` + `expectExactlyOneEvent`).
  timestamp: 2026-10-19T15:19:46.427497+00:00
- actor: claude-code
  id: 01m5acaby0x504f5wakpqdmk4q
  text: |-
    Implementation landed (TDD):
    - RED: new UnusableSkillIDCorrectiveTests (near miss `explor` -> `explore` first + exact search call; limit case `lint` -> `flint, line, lints, list, mint` proving the 5-id cap and edit-distance-then-id order; list resource gives the same text as use skill), and SkillsCatalogToolTests (id field plain string for a full catalog; a reload-added skill is admitted by the schema and loads through the tool). Seen failing for the right reason (old `Currently usable ids:` alphabetical text; `enum` present).
    - GREEN: `SkillsToolSchema.make(name:operations:)` now delegates to `SchemaFusion.fuse(_:name:)` with no root description (the copied field-union and type-schema code is gone). New `UnusableSkillIDText` (Operations/) writes the one corrective for `UseSkill` and `ResourceIDLookup`: `The skill id `<id>` is not currently usable. Closest usable ids: <≤5 ids>. To find a skill, call the `skills` tool with {"op": "search skill", "query": "<the kind of work>"}.` Closeness = Levenshtein edit distance (case-sensitive, like the lookup), ties by id. Empty catalog text unchanged. `SkillCatalogText` gained `searchCall(query:)`; both it and `call(op:id:path:)` now build through one private `call(op:fields:)`, so the call shapes cannot drift.
    - `SkillsCatalogTool.skillIDs` kept (public; FoundationModelsAgents tests read it) and re-documented as the ids of the description; it no longer feeds the schema.
    - Doc comments corrected in SkillsCatalogTool.swift, SkillsTool.swift, SkillsToolSchema.swift; README.md and docs/operations.md no longer state the enum / next-session rule and show the new corrective.
    - Existing tests moved to the new contract, no coverage removed: SkillOperationsTests, UseSkillPlainTextTests (exact text for `totally-made-up`, which also pins the cap: `lint` is 6th), ResourceOpsTests, ResourceIDLookupTests, SkillsCLITests, HotReloadTests.
    - Full `swift test`: 633 tests in 58 suites passed, 0 failures. One build-system line in the output: `warning: missing creator for mutated node: ('.../mlx-swift_Cmlx.bundle/Contents/MacOS')` — SwiftPM/llbuild about the mlx-swift dependency bundle, not from this change's sources.
    - Process slip: one test-file rename of the separator string was done with `sed -i` through the shell instead of the file tool; the result was checked and is correct.
  timestamp: 2026-10-19T15:26:11.392270+00:00
- actor: claude-code
  id: 01m5acaem4faqy18yh7j05ddr3
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsSkills/Operations/{SkillsToolSchema,SkillsCatalogTool,SkillsTool,SkillCatalogText,UseSkill}.swift, new Operations/UnusableSkillIDText.swift, Resources/ResourceSupport.swift; Tests: new UnusableSkillIDCorrectiveTests.swift, SkillsCatalogToolTests, UseSkillPlainTextTests, SkillOperationsTests, ResourceOpsTests, ResourceIDLookupTests, SkillsCLITests, HotReloadTests; README.md, docs/operations.md. `swift test` (1800 s timeout): 633 tests in 58 suites passed, 0 failed; one SwiftPM build warning about the mlx-swift_Cmlx.bundle (dependency, not this change).
    - next: /review
  timestamp: 2026-10-19T15:26:14.148203+00:00
- actor: claude-code
  id: 01m5acbys5e3j537s4bfjjvs9t
  text: |-
    ### test — green
    - evidence: `swift test` (full run, exit 0) — 633 tests in 58 suites passed, 0 failed, 0 skipped; no warnings from this package. The only build warning is the known mlx-swift dependency one ("missing creator for mutated node ... mlx-swift_Cmlx.bundle"), which appeared again.
    - next: review
  timestamp: 2026-10-19T15:27:03.461091+00:00
position_column: doing
position_ordinal: '80'
title: Make the skills `id` a plain string, and let the use skill corrective name the closest ids and say to call search skill
---
## What
Decision (a), from foundationmodelsacpagent-a5 on 2026-10-19. The owner wants added skills announced in a running session. The `id` enum in `SkillsCatalogTool.parameters` (`SkillsToolSchema`) is fixed when the tool is made, so the model cannot write an id that a reload added. The agents tool makes the same change for `name` (foundationmodelsagents-93, task ^x27vjcb).

- `SkillsToolSchema` makes `id` a plain string for every session. The schema is still byte-identical for the whole session.
- The live registry checks the id at call time. It already does: `registry.call` → `UnknownSkillError`.
- The unknown-id corrective of `use skill` (and of the resource operations, which share `ResourceSupport.unusableIDMessage`) names the closest visible ids and says to call `search skill`. A small model without the enum will sometimes guess an id.
- Correct the `SkillsCatalogTool` doc comment that says a hot-reload skill cannot be loaded until the next session.

## TDD: failing tests first
- [x] the `id` field of `parameters` has no enum, for an empty catalog and a full one
- [x] `use skill` with a skill that a reload added, after the tool was made, gives the skill text
- [x] `use skill` with a near-miss id (for example `explor`) gives a corrective that names `explore` first and holds the `search skill` call
- [x] the corrective lists at most N closest ids, in a stable order
- [x] update the existing `SkillsToolSchema` and `SkillsCatalogTool` tests that pin the enum

## Acceptance
- [x] Tests written first and seen failing, then passing; full `swift test` green #skills