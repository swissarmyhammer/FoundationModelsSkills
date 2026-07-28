---
depends_on:
- 01KYNCQ6ZFGBMZSHBY2W3EN080
position_column: todo
position_ordinal: '8280'
title: Directory-shaped skill discovery over DotfolderStack.layers
---
## What
Layer-3 discovery (plan §3, §4, decision #19/#29). Extras' `enumerate` is flat-file only, so walk `DotfolderStack.layers` ourselves.

- `Sources/FoundationModelsSkills/Discovery/DiscoveredSkill.swift` — record: canonical `id` (directory name), `skillDirectory: URL`, `skillFileURL: URL` (the `SKILL.md`), winning `Layer` (provenance from Extras source tracking), plus the list of shadowed lower-layer candidates for the shadowing advisory.
- `Sources/FoundationModelsSkills/Discovery/SkillDiscovery.swift` — for each stack layer root, enumerate immediate `name/SKILL.md` directories. Higher layers shadow lower by directory name (full-replace, decision #3; stack order is defaults < user < project, nearest wins). Skip `.git` and `node_modules`; bound scan depth (skill dirs are looked up at the layer root — depth bound applies to the walk, not nesting of skills). Skip entries without `SKILL.md`. No YAML parsing here; discovery is purely structural.
- Construction does no I/O beyond the explicit discovery call (mirror Extras' posture).

## Acceptance Criteria
- [ ] Discovery over the §11 fixture stack (explicit `defaultsDirectory`/`userDirectory` fixture URLs — hermetic) finds exactly: `base-style` (winner = user layer, defaults copy recorded as shadowed), `commit`, `deploy`, `lint`, `spec-clean`
- [ ] `user/_partials/` is NOT discovered as a skill (no `SKILL.md` shape / underscore dir)
- [ ] A directory without `SKILL.md` is ignored
- [ ] Provenance on each record names the winning layer

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillDiscoveryTests.swift` — fixture-stack discovery snapshot; shadowing case; `.git`/`node_modules` skip case over a temp directory
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.