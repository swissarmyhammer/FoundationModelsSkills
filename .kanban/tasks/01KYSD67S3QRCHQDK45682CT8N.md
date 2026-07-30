---
position_column: todo
position_ordinal: '8480'
title: 'ReadResource: page large text resources instead of 1 MB hard refusal'
---
## What
New defect introduced by the bounded-read fix (ef80be5): `read resource` now stat-checks size and HARD-REFUSES any file over 1,000,000 bytes (`Resources/ReadResource.swift:126, 145-148`). §7.3's paging contract — "at most 500 lines per call; `totalLines` tells the model to page via `start`/`end`" — is thereby unsatisfiable for any legitimate UTF-8 text resource over 1 MB (large changelogs, logs, CSVs) that was previously pageable. Undocumented and untested.

Fix: keep memory bounded WITHOUT refusing large text — read incrementally (streaming line scan) up to the requested `start`/`end` window plus enough to compute `totalLines` cheaply (or report `totalLines` as a lower bound when scanning is capped, with the cap documented). Preserve the stat-first refusal only for the non-UTF-8/binary corrective path (its byte size can come from stat, no full materialization). Choose and document exact semantics on the op; note them in README's op table if they deviate from §7.3's letter.

## Acceptance Criteria
- [ ] A 5 MB UTF-8 text fixture pages successfully with correct slice content for windows at the start, middle, and end
- [ ] Memory stays bounded (no full-file `Data(contentsOf:)` for text reads — verify by code inspection/greppable absence + a large-file test that completes quickly)
- [ ] Binary refusal still stat-based, no full read
- [ ] Chosen semantics documented on the op and in README

## Tests
- [ ] Extend `Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift` — large-text paging matrix; binary refusal unchanged
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.