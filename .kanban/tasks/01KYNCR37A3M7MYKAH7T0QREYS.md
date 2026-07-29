---
comments:
- actor: claude-code
  id: 01kynrqm8q9n03zaq7yrjnyhxk
  text: 'Research done: read plan.md §4/§7.1/§9(#27,#29), read Extras'' FrontmatterDocument.split(text:) (returns (frontmatter: String?, body: String), textual-only), read Extras'' YAMLValue/LayeredYAMLDocument (used for the *stack''s* layered config merge, not skill frontmatter -- not reused here since it''s not Decodable and this task''s YAML decode is squarely ours per #29). Read all Examples/skill-library fixtures including the four broken/ fixtures and the existing test-local placeholder SkillFrontmatter in FixtureLibraryTests.swift (explicitly marked "the real decode type lands... in a later task" -- this task). Plan: SkillFrontmatter as a Decodable struct with a custom init(from:) that merges top-level + metadata.* extension fields (top-level wins, note recorded on conflict), plus a small local FrontmatterValue (Decodable YAML-value enum) for metadata''s arbitrary-typed values and for arguments'' dual string/list spelling. FrontmatterDecoder.decode(text:) -> Outcome{.decoded(DecodedSkill)/.skipped(reason:)}, with a line-targeted regex quoting-fallback retry on the description: line, matching the plan''s §4 "unquoted colon inside description" case. Proceeding with TDD per task workflow note.'
  timestamp: 2026-07-29T01:44:54.807981+00:00
- actor: claude-code
  id: 01kyns4wb1r0xwff1d1wj36xse
  text: 'TDD complete, GREEN: wrote Tests/FoundationModelsSkillsTests/FrontmatterDecoderTests.swift first (confirmed RED -- build failed, real SkillFrontmatter/FrontmatterDecoder types didn''t exist), then implemented Sources/FoundationModelsSkills/Frontmatter/SkillFrontmatter.swift (model: all spec fields + all extension fields, top-level-vs-metadata.* merge with top-level winning and a note recorded on conflict, unknown-top-level-key collection, a local FrontmatterValue YAML-value enum for metadata''s arbitrary values and arguments'' dual string/list spelling) and Sources/FoundationModelsSkills/Frontmatter/FrontmatterDecoder.swift (DecodedSkill + FrontmatterDecoder.decode(text:) -> Outcome{.decoded/.skipped}, with a line-targeted quoting-fallback retry on the description: line, never throwing). `swift build` and `swift test` both exit 0, 32/32 tests pass (21 new + 11 pre-existing). Also refactored Tests/FoundationModelsSkillsTests/FixtureLibraryTests.swift to drop its private placeholder SkillFrontmatter (explicitly documented as scaffolding for this task''s real type) and use the production types instead -- updated specCleanCarriesPureSpecFieldsWithExtensionsUnderMetadata''s assertions to match the new metadata-fallback resolution semantics (disableModelInvocation/preload now resolve to false via metadata.* rather than staying nil, since that fixture only sets them under metadata). Running really-done''s adversarial double-check now before handoff.'
  timestamp: 2026-07-29T01:52:09.057680+00:00
- actor: claude-code
  id: 01kynsqay1c32w265t3kytg719
  text: 'really-done complete. Adversarial double-check (round 1) returned REVISE with 4 findings: (1) the both-present-conflict-plus-note table only covered the 4 Bool extension fields, not arguments/argument-hint; (2) the retry-attempted-but-still-fails test''s assertion (!reason.isEmpty) didn''t actually distinguish the retry-fired path from the immediate-skip path; (3) the quoting-fallback retry''s single-physical-line limitation (multi-line folded description: values) was undocumented; (4) an unused `import Foundation` in SkillFrontmatter.swift. Fixed all four: added topLevelArgumentsWinsOverMetadataOnConflictAndRecordsANote + topLevelArgumentHintWinsOverMetadataOnConflictAndRecordsANote tests; strengthened the retry-failure test to assert reason.localizedCaseInsensitiveContains("retry"); added a "Known limitation" paragraph to quotingFallback''s doc comment; removed the unused import. Re-spawned double-check once (per the bounded-loop contract) -- it verified each fix against actual file content, additionally mutation-tested the two new tests by temporarily swapping topLevel/metadataValue for arguments/argument-hint in SkillFrontmatter.init(from:) and confirming both new tests genuinely fail (not vacuous), then reverted and reconfirmed green. Verdict: PASS. Final fresh verification (this session): `swift build` exit 0, `swift test` exit 0, 34/34 tests pass (23 FrontmatterDecoderTests + 10 FixtureLibraryTests + 1 PackageSmokeTests), zero warnings beyond pre-existing unrelated SwiftPM dependency-identity/mlx-bundle warnings. All acceptance criteria met. Leaving task in doing for /review per the implement skill''s process (does not move to review itself).'
  timestamp: 2026-07-29T02:02:13.825268+00:00
depends_on:
- 01KYNCQ6ZFGBMZSHBY2W3EN080
position_column: doing
position_ordinal: '80'
title: Frontmatter model + Yams decode with quoting-fallback retry
---
## What
Decode skill frontmatter (plan §4, decision #27/#29). Extras' `FrontmatterDocument` does the textual split; YAML decoding is ours, with Yams.

- `Sources/FoundationModelsSkills/Frontmatter/SkillFrontmatter.swift` — model carrying every spec field: `name`, `description`, `license`, `compatibility`, `allowed-tools` (space-separated string, kept raw + tokenized), `metadata` (string-keyed map); and every extension field: `preload`, `user-invocable`, `disable-model-invocation`, `arguments` (space-separated string or YAML list), `argument-hint`, plus retired `partial`. Extension fields are accepted BOTH top-level (canonical) AND under `metadata.*`; top-level wins on conflict; record a diagnostic-worthy note when both are present. Unknown top-level keys are collected, never fatal.
- `Sources/FoundationModelsSkills/Frontmatter/FrontmatterDecoder.swift` — `FrontmatterDocument.split` → Yams decode. On a Yams parse error, run the quoting-fallback retry (plan §4): re-try with unquoted-colon `description:` values quoted; if the retry succeeds, decode + attach a diagnostic; if it fails, return a skip-with-diagnostic result, never throw out of the decoder.
- Output shape: `Result`-like `DecodedSkill` = (frontmatter, body, notes) or (skip reason) — the validator task consumes this.

## Acceptance Criteria
- [x] All spec + extension fields decode from top-level and from `metadata.*`
- [x] The `broken/` unquoted-colon fixture decodes via the retry with a diagnostic note
- [x] Truly unparseable YAML yields a skip result with a diagnostic, no throw
- [x] `arguments:` accepts both the space-separated string and YAML-list spellings

## Tests
- [x] `Tests/FoundationModelsSkillsTests/FrontmatterDecoderTests.swift` — table-driven: every field spelling; both `arguments` spellings; retry success; retry failure; unknown-keys collection
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.