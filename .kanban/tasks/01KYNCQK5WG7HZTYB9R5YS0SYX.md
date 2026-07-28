---
depends_on:
- 01KYNCQ6ZFGBMZSHBY2W3EN080
position_column: todo
position_ordinal: '8280'
title: Directory-shaped skill discovery over host-supplied layer roots
---
## What
Layer-3 discovery (plan §3, §4, decisions #19/#29 — #29 as amended 2026-07-28: **the host supplies the roots**; the package names no directory convention).

- `Sources/FoundationModelsSkills/Discovery/DiscoveredSkill.swift` — record: canonical `id` (directory name), `skillDirectory: URL`, `skillFileURL: URL` (the `SKILL.md`), the winning root (index + URL, the provenance the diagnostics surface), plus the list of shadowed lower-precedence candidates for the shadowing advisory.
- `Sources/FoundationModelsSkills/Discovery/SkillDiscovery.swift` — input: an **ordered `[URL]` of layer roots, lowest precedence first**. For each root, enumerate immediate `name/SKILL.md` directories. **Later roots shadow earlier** by directory name (full-replace, decision #3; last-root-wins). Skip `.git` and `node_modules`; bound scan depth. Skip directories without `SKILL.md`. No YAML parsing here; discovery is purely structural. Nonexistent roots are skipped silently (a host may pass `~/.skills` that does not exist yet).
- `DotfolderStack` is NOT the input — it is one host-side convenience for computing roots (`stack.layers` → root URLs). Provide a small helper that maps a `DotfolderStack` to the ordered root list so §10's convenience path stays one line.
- Construction does no I/O beyond the explicit discovery call.

## Acceptance Criteria
- [ ] Discovery over the §11 fixture roots (explicit fixture URLs in defaults→user→project order — hermetic) finds exactly: `base-style` (winner = user root, defaults copy recorded as shadowed), `commit`, `deploy`, `lint`, `spec-clean`
- [ ] `user/_partials/` is NOT discovered as a skill; a directory without `SKILL.md` is ignored
- [ ] A nonexistent root in the list is skipped without error
- [ ] Provenance on each record names the winning root
- [ ] The `DotfolderStack`→roots helper produces the same discovery result as passing the URLs directly

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillDiscoveryTests.swift` — fixture-root discovery snapshot; shadowing (last-root-wins); nonexistent-root case; `.git`/`node_modules` skip over a temp directory; stack-helper equivalence
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.