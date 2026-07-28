---
depends_on:
- 01KYNCQ6ZFGBMZSHBY2W3EN080
position_column: todo
position_ordinal: '8380'
title: Frontmatter model + Yams decode with quoting-fallback retry
---
## What
Decode skill frontmatter (plan §4, decision #27/#29). Extras' `FrontmatterDocument` does the textual split; YAML decoding is ours, with Yams.

- `Sources/FoundationModelsSkills/Frontmatter/SkillFrontmatter.swift` — model carrying every spec field: `name`, `description`, `license`, `compatibility`, `allowed-tools` (space-separated string, kept raw + tokenized), `metadata` (string-keyed map); and every extension field: `preload`, `user-invocable`, `disable-model-invocation`, `arguments` (space-separated string or YAML list), `argument-hint`, plus retired `partial`. Extension fields are accepted BOTH top-level (canonical) AND under `metadata.*`; top-level wins on conflict; record a diagnostic-worthy note when both are present. Unknown top-level keys are collected, never fatal.
- `Sources/FoundationModelsSkills/Frontmatter/FrontmatterDecoder.swift` — `FrontmatterDocument.split` → Yams decode. On a Yams parse error, run the quoting-fallback retry (plan §4): re-try with unquoted-colon `description:` values quoted; if the retry succeeds, decode + attach a diagnostic; if it fails, return a skip-with-diagnostic result, never throw out of the decoder.
- Output shape: `Result`-like `DecodedSkill` = (frontmatter, body, notes) or (skip reason) — the validator task consumes this.

## Acceptance Criteria
- [ ] All spec + extension fields decode from top-level and from `metadata.*`
- [ ] The `broken/` unquoted-colon fixture decodes via the retry with a diagnostic note
- [ ] Truly unparseable YAML yields a skip result with a diagnostic, no throw
- [ ] `arguments:` accepts both the space-separated string and YAML-list spellings

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/FrontmatterDecoderTests.swift` — table-driven: every field spelling; both `arguments` spellings; retry success; retry failure; unknown-keys collection
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.