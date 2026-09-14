---
assignees:
- claude-code
depends_on:
- 01M2H0Z7JJVKY2QKN1SB42CVF0
position_column: todo
position_ordinal: 8f80
title: Add the ../skills release tool and tag v1.0.0
---
## What

**Cross-repository task.** Run it from a session opened in `/Users/wballard/github/swissarmyhammer/skills`. The `/finish` pipeline in FoundationModelsSkills cannot do it. Steps marked **(operator)** need the network and a person's approval.

marketplace.md §3.2 (`scripts/release`) and §3.6 step 4. One command sets the version everywhere, so the version in `VERSION`, in each `SKILL.md`, in the catalogs, and in the tag never differs.

In `/Users/wballard/github/swissarmyhammer/skills`:
- `Package.swift`: put the release logic in the `CatalogGenerator` library (for example `Release.run(version:repository:)`), and add an executable target `release` that calls it. Add `scripts/release` as a wrapper around `swift run release "$@"`.
- `swift run release <X.Y.Z>`: check that the version is a valid semantic version and that the working tree is clean. Write `VERSION`. Rewrite `metadata.version` in each `skills/*/SKILL.md` (edit only that one frontmatter line; keep the rest of the file byte for byte). Run the catalog generator. Commit `release: vX.Y.Z` and make the tag `vX.Y.Z`. It does not push.
- §3.6 item 4 in CI: when the CI run is for a `v*` tag, a test checks that the tag name without `v` equals `VERSION` and the Claude catalog `metadata.version`. The CI workflow already triggers on `v*` tags (scaffold task).

- [ ] The release logic in `CatalogGenerator`, the `release` target, and the wrapper
- [ ] Version check, clean-tree check, and the `VERSION` write
- [ ] The `metadata.version` rewrite that changes only that line; regenerate, commit, tag
- [ ] The tag-equals-version test
- [ ] **(operator)** `swift run release 1.0.0` (the files already say `1.0.0`, so this makes the tag), then `git push --follow-tags`

## Acceptance Criteria
- [ ] After `release 1.0.1` on a temporary copy of the repository, `VERSION`, every `metadata.version`, and every catalog version say `1.0.1`, and the tag `v1.0.1` exists (checked by a test)
- [ ] A dirty tree or a bad version stops the tool with an error and changes nothing (checked by a test)
- [ ] On a `v*` tag, CI fails when the tag and `VERSION` differ
- [ ] The tag `v1.0.0` is on `origin`

## Tests
- [ ] `Tests/SkillsMarketplaceTests/VersionTests.swift` in `../skills`: every `SKILL.md` `metadata.version` equals `VERSION`; the version rewrite changes only the `metadata.version` line of a fixture `SKILL.md`; when the environment names a `v*` tag (`GITHUB_REF_TYPE=tag`, `GITHUB_REF_NAME`), the tag equals `VERSION`
- [ ] `Tests/SkillsMarketplaceTests/ReleaseToolTests.swift`: copy a small fixture repository to a temporary folder, make it a git repository with libgit2 or with the test's own `Process` call (test code only), run `Release.run(version: "1.0.1", …)`, and assert the file changes and the tag; a dirty tree and the version `1.0` are refused with no change
- [ ] Run `swift test` in `../skills`; expect green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cross-repo