---
assignees:
- claude-code
depends_on:
- 01M2H0TYWZG3C9B557Z31CYEGP
position_column: todo
position_ordinal: 8b80
title: Generate the ../skills catalogs (Claude, Codex, well-known index) from the skill folders
---
## What

**Cross-repository task.** Run it from a session opened in `/Users/wballard/github/swissarmyhammer/skills`. The `/finish` pipeline in FoundationModelsSkills cannot do it. Steps marked **(operator)** need the network and a person's approval.

marketplace.md §3.2, §3.3, §3.6 step 3. The catalogs are generated from `skills/`. Nobody edits them by hand. Use Swift, so the repository needs no `jq` or Python.

In `/Users/wballard/github/swissarmyhammer/skills`:
- Add a `VERSION` file with `1.0.0`. It is the one source of the catalog version.
- `Package.swift`: add a library target `CatalogGenerator` and an executable target `generate-catalogs` that calls it. Add `scripts/generate-catalogs` as a two-line wrapper around `swift run generate-catalogs`.
- `CatalogGenerator` writes three files from the folders in `skills/` (every folder that has a `SKILL.md`; `_partials/` is not a skill), sorted by name:
  1. `.claude-plugin/marketplace.json` — name `swissarmyhammer-skills`, owner `swissarmyhammer`, `metadata.version` from `VERSION`, and one plugin `swissarmyhammer` with `"source": "./"`, `"strict": false`, and `skills` = `["./skills/<name>", …]` (§3.3).
  2. `.agents/plugins/marketplace.json` — the Codex form with one `local` plugin at `./`, and `.codex-plugin/plugin.json` (name, version, skills path), after https://developers.openai.com/plugins/build/plugins.
  3. `.well-known/agent-skills/index.json` — the agentskills discovery index (`$schema` 0.2.0): one entry for each skill with `name`, `type: "skill-md"`, `description` (from the frontmatter), `url` (`/skills/<name>/SKILL.md`), and `digest` (`sha256:` of the `SKILL.md` bytes).
- The output is deterministic: sorted keys, sorted skills, a final newline.
- Run the generator and commit the files.

- [ ] `VERSION`, the `CatalogGenerator` target, the executable, and the wrapper script
- [ ] The Claude catalog
- [ ] The Codex catalog and plugin manifest
- [ ] The well-known index with digests; commit the generated files
- [ ] **(operator)** `git push`

## Acceptance Criteria
- [ ] `swift run generate-catalogs` writes the three files, and a second run changes nothing
- [ ] The Claude catalog lists all 24 skills in exactly one plugin
- [ ] CI fails when a committed catalog differs from the generator output

## Tests
- [ ] `Tests/SkillsMarketplaceTests/CatalogSyncTests.swift` in `../skills`: generate in memory and compare byte for byte with each committed file; every skill folder is in the Claude plugin exactly once; each `digest` equals the SHA-256 of its `SKILL.md`; the Claude catalog `metadata.version` equals `VERSION`
- [ ] Run `swift test` in `../skills`; expect green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cross-repo