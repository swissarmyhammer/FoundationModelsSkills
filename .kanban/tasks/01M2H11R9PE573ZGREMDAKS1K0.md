---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2nbqdn674hfwmc775f91qvm
  text: |-
    Picked up. Research in /Users/wballard/github/swissarmyhammer/skills at 5a2ea62.

    What is there now: VERSION holds 1.0.0; Sources/CatalogGenerator + the generate-catalogs executable + scripts/generate-catalogs; Tests/SkillsMarketplaceTests with CatalogSyncTests (drift test, published-path literals) and SkillLibraryTests; each of the 24 skills/*/SKILL.md carries `metadata: version: "1.0.0"`; .github/workflows CI already triggers on `v*` tags.

    Decision on git. This repository has no libgit2 dependency, and the rule is that product Swift never starts `git` as a subprocess. Thus the git steps live in shell scripts under scripts/: scripts/release reads the tree state and the test result, and scripts/release-commit makes the release commit and the tag. The Swift `Release.run` takes those two host facts as inputs (a ReleasePreflight value), thus the refusal decision stays in one tested place and no Swift code starts git.

    Plan: Release + ReleaseError + ReleaseTag + SkillVersionRewrite in CatalogGenerator; a `release` executable target; scripts/release and scripts/release-commit; VersionTests and ReleaseToolTests, with one refusal test for each of: a version that is not X.Y.Z, a dirty tree, catalogs that are stale against a fresh generator run, and red tests. Each refusal test holds every file of the fixture repository byte for byte.
  timestamp: 2026-09-16T15:00:23.846300+00:00
- actor: claude-code
  id: 01m2ncbgk2166bnf70p7we76p5
  text: |-
    ### implement — changed
    - evidence: local commit a4e97fd in /Users/wballard/github/swissarmyhammer/skills (on main, not pushed). New: Sources/CatalogGenerator/{Release,ReleaseReport,ReleaseError,ReleasePreflight,ReleaseTag,SemanticVersion,SkillVersionRewrite}.swift, Sources/release/ReleaseMain.swift, scripts/release, scripts/release-commit, Tests/SkillsMarketplaceTests/{ReleaseToolTests,VersionTests,SkillFileVersion,FixtureRepository}.swift. Changed: Package.swift (the `release` product and target), Sources/CatalogGenerator/{CatalogGenerator,MarketplaceIdentity}.swift, Tests/SkillsMarketplaceTests/CatalogSyncTests.swift (its private fixture builder moved to the shared FixtureRepository, thus the new suite copies nothing).
    - `swift test`: 28 tests in 4 suites passed, zero failures and zero warnings (13 tests in 2 suites before).
    - Refusal proof: with the four checks taken out of `Release.check`, each of the four refusal tests failed with two issues each -- no error thrown, and the files of the fixture repository changed. With the checks in, all pass. The no-change tag test is also proved: before the fix, `scripts/release-commit` stopped on a commit that held nothing and made no tag.
    - Real repository: `swift run release 1.0.0 <root> clean passed` wrote each file and left `git status` empty (exit 0); `dirty` and the version `1.0` each exit 1 with a message and change nothing.
    - Not done here, by the order of the dispatching agent: the tag and the push. The tag command is `git -C /Users/wballard/github/swissarmyhammer/skills tag v1.0.0 && git -C /Users/wballard/github/swissarmyhammer/skills push --follow-tags`, or the whole step as `scripts/release 1.0.0` followed by `git push --follow-tags`.
    - next: /review
  timestamp: 2026-09-16T15:11:22.210453+00:00
- actor: claude-code
  id: 01m2nckysmnq93hj45zfnsrq9f
  text: |
    ### review — clean

    The `review` engine cannot read a sibling repository, thus this review was done by hand in `/Users/wballard/github/swissarmyhammer/skills` at commit `a4e97fd`.

    **1. Each refusal bites (mutation test).** Each guard of `Release.check` was defeated one at a time (the condition was replaced with `true`), `swift test` was run, and the file was restored:

    - `SemanticVersion.isSemantic(version)` defeated -> "A version that is not X.Y.Z is refused" failed
    - `preflight.workingTree == .clean` defeated -> "A dirty working tree is refused" failed
    - `preflight.testRun == .passed` defeated -> "A red test run is refused" failed
    - `stale.isEmpty` defeated -> "Stale catalogs are refused" failed

    No mutation failed a test of another guard. Each failure reported two issues: the error that was not thrown, AND `before == after` at `ReleaseToolTests.swift:117`. Thus the "writes nothing" part of each refusal is tested, and it is not empty. `Release.run` also reads and rewrites every `SKILL.md` in memory before it writes one file.

    **2. Git runs only in the scripts.** `grep` for `Process(`, `posix_spawn`, `system(`, `NSTask`, `execve` and `Subprocess` over `Sources/` gives nothing. Only `Tests/SkillsMarketplaceTests/ReleaseToolTests.swift` starts a program, and it is test code. The git steps are in `scripts/release` and `scripts/release-commit`.

    **3. The tag agrees with the files.** `v1.0.0` points at `a4e97fd` on `origin` and in the local clone. `VERSION` is `1.0.0`. All 24 `SKILL.md` files name `metadata.version: "1.0.0"`. `.claude-plugin/marketplace.json` and `.codex-plugin/plugin.json` name `1.0.0`. `.well-known/agent-skills/index.json` and `.agents/plugins/marketplace.json` publish no version by their schema; they carry per-skill digests, which the generator writes again after the version rewrite.

    **4. Tests.** `swift test` gives 28 tests in 4 suites, passed, with 0 warnings. Log: `scratchpad/final-test.log`.

    **5. The catalogs are current.** `./scripts/generate-catalogs` changed no file (`git status --porcelain` is empty after the run).

    **6. The version gates bite too.** With `GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v1.0.0` the suite passes; with `v9.9.9` the test "A tag run names the version of the repository and of the catalog" fails. A changed `SKILL.md` fails the digest test and the catalog-bytes test. A `VERSION` of `9.9.9` fails three tests. `.github/workflows/ci.yml` triggers on `tags: ['v*']`.

    The working tree is clean and `HEAD` is `a4e97fd` after the review. No commit, no push, and no change to the tag was made.

    **Open, but not a defect of the code:** the CI run of the `v1.0.0` tag on GitHub was not read. The test that CI runs was proved to work, but the run itself must be read on GitHub.

    - evidence: 28 tests in 4 suites passed, 0 warnings; 4 of 4 refusal guards proved by mutation; tag `v1.0.0` = `a4e97fd` on origin; catalogs current
    - next: read the CI run of the `v1.0.0` tag on GitHub
  timestamp: 2026-09-16T15:15:58.900391+00:00
depends_on:
- 01M2H0Z7JJVKY2QKN1SB42CVF0
position_column: done
position_ordinal: e680
title: Add the ../skills release tool and tag v1.0.0
---
## What

**Cross-repository task.** Run it from a session opened in `/Users/wballard/github/swissarmyhammer/skills`. The `/finish` pipeline in FoundationModelsSkills cannot do it. Steps marked **(operator)** need the network and a person's approval.

marketplace.md §3.2 (`scripts/release`) and §3.6 step 4. One command sets the version everywhere, so the version in `VERSION`, in each `SKILL.md`, in the catalogs, and in the tag never differs.

In `/Users/wballard/github/swissarmyhammer/skills`:
- `Package.swift`: put the release logic in the `CatalogGenerator` library (for example `Release.run(version:repository:)`), and add an executable target `release` that calls it. Add `scripts/release` as a wrapper around `swift run release "$@"`.
- `swift run release <X.Y.Z>`: check that the version is a valid semantic version and that the working tree is clean. Write `VERSION`. Rewrite `metadata.version` in each `skills/*/SKILL.md` (edit only that one frontmatter line; keep the rest of the file byte for byte). Run the catalog generator. Commit `release: vX.Y.Z` and make the tag `vX.Y.Z`. It does not push.
- §3.6 item 4 in CI: when the CI run is for a `v*` tag, a test checks that the tag name without `v` equals `VERSION` and the Claude catalog `metadata.version`. The CI workflow already triggers on `v*` tags (scaffold task).

- [x] The release logic in `CatalogGenerator`, the `release` target, and the wrapper
- [x] Version check, clean-tree check, and the `VERSION` write
- [x] The `metadata.version` rewrite that changes only that line; regenerate, commit, tag
- [x] The tag-equals-version test
- [ ] **(operator)** `swift run release 1.0.0` (the files already say `1.0.0`, so this makes the tag), then `git push --follow-tags`

## Where the git steps live

The repository has no libgit2 dependency, and product Swift never starts `git`. Thus the git steps are shell scripts under `scripts/`:

- `scripts/release <X.Y.Z>` reads the state of the working tree (`git status --porcelain`) and the result of `swift test`, gives both to `swift run release`, and then calls `scripts/release-commit`.
- `scripts/release-commit <X.Y.Z> <root>` makes the release commit and the tag. It makes the commit only when a file changed, thus the first release of a repository that already names the version still gets its tag.
- `Release.run(version:repository:preflight:)` holds the whole refusal decision in one tested place.

## Acceptance Criteria
- [x] After `release 1.0.1` on a temporary copy of the repository, `VERSION`, every `metadata.version`, and every catalog version say `1.0.1`, and the tag `v1.0.1` exists (checked by a test)
- [x] A dirty tree or a bad version stops the tool with an error and changes nothing (checked by a test)
- [x] Stale catalogs and red tests also stop the tool and change nothing (checked by a test)
- [ ] On a `v*` tag, CI fails when the tag and `VERSION` differ (the test is in `VersionTests`; the proof comes with the tag run)
- [ ] The tag `v1.0.0` is on `origin`

## Tests
- [x] `Tests/SkillsMarketplaceTests/VersionTests.swift` in `../skills`: every `SKILL.md` `metadata.version` equals `VERSION`; the version rewrite changes only the `metadata.version` line of a fixture `SKILL.md`; when the environment names a `v*` tag (`GITHUB_REF_TYPE=tag`, `GITHUB_REF_NAME`), the tag equals `VERSION` and the Claude catalog version
- [x] `Tests/SkillsMarketplaceTests/ReleaseToolTests.swift`: copy a small fixture repository to a temporary folder, make it a git repository with the test's own `Process` call (test code only), run `Release.run(version: "1.0.1", …)`, and assert the file changes and the tag; a dirty tree, red tests, stale catalogs and the version `1.0` are refused with no change
- [x] Run `swift test` in `../skills`; expect green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cross-repo