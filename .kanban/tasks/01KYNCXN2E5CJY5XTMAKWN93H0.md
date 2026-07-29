---
depends_on:
- 01KYNCWEKBW84J06EDGSNBWVQT
position_column: doing
position_ordinal: '80'
title: 'Resource ops: list resource + read resource (§7.3)'
---
## What
The two passive tier-3 ops from plan §7.3 (specified to full fidelity; ungated reads), joining the fused tool.

- `Sources/FoundationModelsSkills/Resources/PathConfinement.swift` — the shared invariant: a skill-relative path, symlinks resolved, must land inside the skill directory; `..`, absolute paths, and escaping symlinks are rejected. One function, used by all three resource ops.
- `Sources/FoundationModelsSkills/Resources/ListResource.swift` — op `"list resource"`, `id` (req): every regular file under the skill dir except `SKILL.md`; relative path; kind from top-level folder (`scripts/`→`script`, `references/`→`reference`, `assets/`→`asset`, else `other`); byte size; executable bit; sorted by path; capped at 100 rows with `total` = real count; hidden files and outside-resolving symlinks skipped; unknown/model-hidden id → corrective with current ids. Output `ListResourceResult`/`ResourceRow` exactly as §7.3.
- `Sources/FoundationModelsSkills/Resources/ReadResource.swift` — op `"read resource"`, `id`+`path` (req), `start?` (default 1), `end?` (default start+499): verbatim content, NEVER through the §5 pipeline; ≤500 lines per call; `totalLines` for paging; non-UTF-8 → corrective with byte size. Output `ReadResourceResult` as §7.3.
- Register both ops in the fused tool (now five ops).
- Add fixture `Examples/skill-library/project/.skills/release-notes/` — `scripts/` + `references/` + `assets/` + `allowed-tools: "Script(scripts/*)"` frontmatter (the script itself is exercised by the next task; include a multi-hundred-line reference file for paging tests).

## Acceptance Criteria
- [ ] `list resource` over `release-notes` returns the sorted, kinded, capped row set with real `total`
- [ ] Path confinement rejects `../x`, `/etc/passwd`, and a symlink escaping the skill dir — each with a corrective
- [ ] `read resource` pages a 700-line reference in two calls with correct `totalLines`
- [ ] A binary asset draws the non-UTF-8 corrective with its byte size

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift` — listing snapshot; confinement matrix (plan §13: `..`, absolute, escaping symlinks); paging; binary corrective; >100-file cap over a generated temp skill
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.