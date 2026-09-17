---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2n76yz7t2b07dyv9am3tptw
  text: |-
    ### Research

    Read the authoritative parser in FoundationModelsSkills before I wrote a catalog:
    `Sources/FoundationModelsSkills/Marketplace/MarketplaceCatalog.swift` and
    `Sources/FoundationModelsSkills/Marketplace/CatalogResolver.swift`.

    What the client reads:
    - It looks for `.claude-plugin/marketplace.json` first, then
      `.agents/plugins/marketplace.json`, then it scans the repository.
    - A catalog needs `name` and `plugins`. It also reads `owner`, `metadata.version`,
      and `renames`. It ignores every other key, for example `$schema`,
      `description`, `category`, and the Codex `interface` and `policy` keys.
    - A plugin `source` is a string, or an object. An object with
      `"source": "local"` and a `path` is the same as the string path. Any other
      object kind is a remote source, and the client skips the plugin.
    - A plugin with a `skills` array gives those folders. A plugin with no `skills`
      array gives the folders of `<source>/skills/` that hold a `SKILL.md` file.
      Thus the Codex form with one `local` plugin at `./` resolves to the same 24
      skills as the Claude form, and `_partials/` is never a skill.

    External formats:
    - The agentskills discovery index uses
      `"$schema": "https://schemas.agentskills.io/discovery/0.2.0/schema.json"` and a
      `skills` array of `{ name, type, description, url, digest }`, with
      `digest` as `sha256:<64 lowercase hex>`.
    - The Codex marketplace file uses `name`, `interface`, and `plugins` with an
      object source of kind `local`.
    - The `agent-plugins.org` 1.0.0 plugin schema has no property for a skills path.
      Thus `.codex-plugin/plugin.json` gets `name`, `version`, and `skills` only, and
      it claims no `$schema`, because a claimed schema would not permit `skills`.

    Baseline: `swift test` in `/Users/wballard/github/swissarmyhammer/skills` passes
    now with 4 tests in 1 suite.

    Plan: the generator reads the descriptions from a `SkillsRegistry` over
    `skills/`, the same loader the client uses, rather than from a hand-written
    frontmatter parser that could drift.
  timestamp: 2026-09-16T13:41:30.215242+00:00
- actor: claude-code
  id: 01m2n89txy0j84hkwjqjtycf83
  text: |-
    ### implement — changed

    TDD: `Tests/SkillsMarketplaceTests/CatalogSyncTests.swift` was written first and
    failed (no module `CatalogGenerator`). The library then made it pass.

    What landed in `/Users/wballard/github/swissarmyhammer/skills`:
    - `VERSION` (1.0.0), the one source of the catalog version.
    - `Sources/CatalogGenerator/` — the library: `CatalogGenerator`,
      `MarketplaceIdentity` (one source of each name), `CatalogSkill` (the digest),
      `ClaudeCatalog`, `CodexCatalog`, `CodexPluginManifest`, `DiscoveryIndex`,
      `GeneratedCatalogFile`, `CatalogGeneratorError`.
    - `Sources/generate-catalogs/GenerateCatalogsMain.swift` — the executable. It
      takes the repository root as one optional argument, and it writes with a
      `FileHandle`, never `print`.
    - `scripts/generate-catalogs` — the wrapper. It resolves its own repository,
      thus a run from any folder writes the same files.
    - The four generated files: `.claude-plugin/marketplace.json`,
      `.agents/plugins/marketplace.json`, `.codex-plugin/plugin.json`, and
      `.well-known/agent-skills/index.json`.

    Decisions and discoveries:
    - The generator reads the library with a `SkillsRegistry` over `skills/`, the
      loader the client uses. Thus the description of an index entry is the
      description the client reads, and no hand-written YAML parser can drift.
    - `.codex-plugin/plugin.json` claims no `$schema`. The `agent-plugins.org`
      1.0.0 schema has no property for a skills path, thus a claim of that schema
      would not agree with the `skills` key the manifest needs.
    - The Codex catalog carries no `skills` array. The client then takes the
      folders of `./skills/` that hold a `SKILL.md` file, which is the same set of
      24 skills the Claude catalog lists.
    - `#expect` takes a non-throwing autoclosure, thus each throwing call is now a
      `let` above the expectation.
    - `RepositoryLayout` is new: it holds the repository-root derivation that both
      test suites need, thus the helper is not copied into the second suite.

    Proof that the suite can fail: one skill path was removed from the committed
    Claude catalog by hand, and the run failed with 2 issues, in
    `committedCatalogsAreCurrent` and `claudePluginListsEverySkillOnce`. The file
    was then restored by a run of the generator.

    A second run of `scripts/generate-catalogs` after the commit leaves
    `git status` clean, thus the output is deterministic.

    - evidence: `swift test` in `/Users/wballard/github/swissarmyhammer/skills` — 9
      tests in 2 suites passed, 0 failures, 0 warnings. Local commit cb6d503, 20
      files changed. Not pushed.
    - next: `/review`
  timestamp: 2026-09-16T14:00:32.958069+00:00
- actor: claude-code
  id: 01m2n8mhskn04spjgkw3mqmq2a
  text: |-
    ### review — findings
    - scope: `/Users/wballard/github/swissarmyhammer/skills` at commit `cb6d503`. The `review` MCP engine is bound to the FoundationModelsSkills root and cannot read a sibling repository, thus every check was done by hand.
    - evidence: 4 findings — Sources/CatalogGenerator/ClaudeCatalog.swift:10, Sources/CatalogGenerator/CatalogGenerator.swift:19, Tests/SkillsMarketplaceTests/CatalogSyncTests.swift:100, Tests/SkillsMarketplaceTests/CatalogSyncTests.swift:114
    - verified correct: the four generated files give every field that `MarketplaceCatalog` and `CatalogResolver` read, and they match the marketplace.md 3.3 example field for field; 24 skills in the Claude plugin and 24 in the discovery index, equal to the 24 folders of `skills/` that hold a `SKILL.md`; `skills/_partials` is in neither; the drift test fails when a catalog goes stale (proved two times, then restored, tree clean); `swift test` gives 9 tests in 2 suites, all pass, and a rebuild of the new sources gives 0 warnings; no credential, no token, and no personal path is in a generated file; no force unwrap, no `try!`, no `as!`, no `@unchecked Sendable`, and no `fatalError` in the new sources.
    - every finding is about test rigor and API surface. No defect of the generated output was found.
    - next: correct the 4 findings in `../skills`, run `swift test`, then run `/review` again. The card stays in `review`. Nothing was committed and nothing was pushed.
  timestamp: 2026-09-16T14:06:24.051535+00:00
- actor: claude-code
  id: 01m2n9e93bxcrgepfc6636exzj
  text: |-
    ### implement — changed

    Corrected the four review findings in
    `/Users/wballard/github/swissarmyhammer/skills`. Local commit `efe7a14`, not
    pushed.

    1. **api-surface.** `ClaudeCatalog` and `DiscoveryIndex` are now `internal` and
       `Encodable`, the same as `CodexCatalog` and `CodexPluginManifest`. The
       generator only encodes. `CatalogSyncTests` uses
       `@testable import CatalogGenerator`.
    2. **unused-public.** `CatalogGenerator.versionFileName` is `internal`, and the
       test reads it. The literal `"VERSION"` is written one time.
    3. **coverage-gap.** New file `Tests/SkillsMarketplaceTests/CommittedCatalogs.swift`
       holds a decode model for each committed file, with the key names of the
       published format. The new tests
       `codexCatalogHoldsOneLocalPlugin` and
       `codexPluginManifestNamesTheSkillsFolder` hold the plugin source kind, the
       source path, the plugin name, the skills folder, and the version equal to a
       literal of the test. The same cause was removed for the other two files:
       `claudeCatalogNamesTheMarketplace` holds the marketplace name, the owner,
       the plugin source, and `strict`, and the index test holds
       `type == "skill-md"`.
    4. **tautology.** `generationIsDeterministic` now builds a fixture repository in
       a temporary folder, writes the catalogs two times, and compares the files on
       disk. The old form compared two return values of `generate()`, which are
       equal by construction.

    Proof that the new tests find a wrong value. Each mutation ran the generator
    first, thus the drift test stayed green:

    - `CodexCatalog.localSourceKind` from `"local"` to `"git"` →
      `The Codex catalog holds one local plugin at the repository root` failed:
      `plugin.source.kind == Self.expectedLocalSourceKind`.
    - `CodexPluginManifest.skills` from `./skills` to `./` →
      `The Codex plugin manifest names the skills folder and the version` failed:
      `manifest.skills == Self.expectedSkillsFolder`.

    Both mutations were reverted, the generator ran again, and the four generated
    files are the committed bytes.

    A discovery: a model of the test target is a better truth than the type of the
    generator. It writes the key names a second time, thus a changed `CodingKeys`
    also fails a test.

    - evidence: `swift test` in `/Users/wballard/github/swissarmyhammer/skills` —
      12 tests in 2 suites passed, 0 failures, 0 warnings.
    - next: `/review`
  timestamp: 2026-09-16T14:20:27.115976+00:00
- actor: claude-code
  id: 01m2namhbwm5sa5zc13q7fepgr
  text: |-
    ### review — findings

    Round 2. Scope: `/Users/wballard/github/swissarmyhammer/skills` at commit `efe7a14`. The `review` MCP engine cannot read a sibling repository, thus every check was done by hand.

    - evidence: 2 new findings — Tests/SkillsMarketplaceTests/CatalogSyncTests.swift:252, Sources/CatalogGenerator/GeneratedCatalogFile.swift:12
    - the four findings of round 1 hold. Each was verified, not read:
      - The new Codex tests read a truth outside the generator: `CommittedCatalogs.swift` is a decode model of the test target, and each expected value is a literal of `CatalogSyncTests`. No value comes from a constant of the generator.
      - Mutation `CodexCatalog.localSourceKind` `"local"` to `"git"`, plus one run of the generator: `swift test` failed at `CatalogSyncTests.swift:288`. Reverted.
      - Mutation `CodexPluginManifest.skills` `./skills` to `./`, plus one run of the generator: `swift test` failed at `CatalogSyncTests.swift:303`. Reverted.
      - `generationIsDeterministic` can now fail: a `UUID` in the release version made it fail at `CatalogSyncTests.swift:245`. Reverted.
      - The four catalog types are each `internal` and `Encodable`. The literal `"VERSION"` is written one time.
    - `swift test`: 12 tests in 2 suites pass, 0 failures. A rebuild of every source of `CatalogGenerator`, `generate-catalogs`, and the test target reports 0 warnings.
    - The tree is clean at `efe7a14`. Nothing was committed and nothing was pushed.
    - next: correct the 2 findings in `../skills`, run `swift test`, then run `/review` again. The card stays in `review`.
  timestamp: 2026-09-16T14:41:20.764214+00:00
- actor: claude-code
  id: 01m2nb07nk607k83aw6fv8qz72
  text: |-
    ### implement — changed

    Round 3. Corrected the two findings of the 09:40 review in
    `/Users/wballard/github/swissarmyhammer/skills`. Local commit `5a2ea62`, not
    pushed.

    **Finding 1, `CatalogSyncTests.swift:252`, coverage-gap.**
    `Tests/SkillsMarketplaceTests/CommittedCatalogs.swift` now writes the path of
    each published file as a literal of the test target, next to the key names it
    already writes a second time:

    - `CommittedClaudeCatalog.path = ".claude-plugin/marketplace.json"`
    - `CommittedCodexCatalog.path = ".agents/plugins/marketplace.json"`
    - `CommittedCodexPluginManifest.path = ".codex-plugin/plugin.json"`
    - `CommittedDiscoveryIndex.path = ".well-known/agent-skills/index.json"`

    Every test reads its file through one of these, thus no test takes a path from
    the generator. A new test,
    `The generator writes each catalog to its published path`, holds the write
    order of `generate()` equal to the four literals.

    **Finding 2, `GeneratedCatalogFile.swift:12`, unused-public.**
    `GeneratedCatalogFile.contents`, `CatalogGenerator.generate()`, and
    `CatalogGenerator.repositoryRoot` are `internal`. `init`, `write()`, and `path`
    stay `public`, because `GenerateCatalogsMain` calls them.

    A check of every other `public` of `Sources/CatalogGenerator/` and
    `Sources/generate-catalogs/` found one more with no outside user:
    `CatalogGeneratorError` and its `description`. The executable catches the error
    and reports its text, and it names no case. Both are now `internal`. The four
    catalog types and `versionFileName` were already `internal`. What stays
    `public`: `CatalogGenerator`, its `init(repositoryRoot:)`, `write()`,
    `GeneratedCatalogFile`, and `GeneratedCatalogFile.path`.

    **The path mutation proofs.** Each mutation ran `scripts/generate-catalogs`
    first, thus the drift test stayed green:

    - `ClaudeCatalog.path` from `.claude-plugin/marketplace.json` to
      `.claude-plugin/catalog.json` → `swift test` failed at
      `CatalogSyncTests.swift:251`, `paths == Self.expectedGeneratedPaths`, 13 tests
      with 1 issue. Reverted.
    - `DiscoveryIndex.path` from `.well-known/agent-skills/index.json` to
      `.well-known/agent-skills/skills.json` → the same test failed at the same
      line, 13 tests with 1 issue. Reverted.

    Both stray files, `.claude-plugin/catalog.json` and
    `.well-known/agent-skills/skills.json`, were deleted, the generator ran again,
    and the four committed catalogs hold the bytes of the round-2 commit: `git
    status` showed only the five source and test files.

    A discovery for the next round: a path constant of the generator is a value that
    no comparison with the generator output can hold, in the same way as a key name.
    The rule that the earlier rounds found holds for every value a client reads,
    the file name included.

    - evidence: `swift test` in `/Users/wballard/github/swissarmyhammer/skills` —
      13 tests in 2 suites passed, 0 failures. A rebuild of `CatalogGenerator` and
      the test run report 0 warnings.
    - next: `/review`

    ### implement — changed
    - evidence: 5 files — Sources/CatalogGenerator/CatalogGenerator.swift, Sources/CatalogGenerator/CatalogGeneratorError.swift, Sources/CatalogGenerator/GeneratedCatalogFile.swift, Tests/SkillsMarketplaceTests/CatalogSyncTests.swift, Tests/SkillsMarketplaceTests/CommittedCatalogs.swift; local commit 5a2ea62; swift test 13 tests in 2 suites, 0 failures, 0 warnings; path mutations ClaudeCatalog.path and DiscoveryIndex.path each failed the new test and were reverted
    - next: /review
  timestamp: 2026-09-16T14:47:44.051048+00:00
- actor: claude-code
  id: 01m2nbg4bfh89h6w0ray06mtq9
  text: |
    ### review — clean

    Round 3, a closing verification. Scope: `/Users/wballard/github/swissarmyhammer/skills` at commit `5a2ea62`. The `review` MCP engine cannot read a sibling repository, thus each check below was done by hand. The scope was the two findings of round 2 only. No new style check was made, and no new finding was opened.

    **1. The four published paths are literals of the test target.**
    `Tests/SkillsMarketplaceTests/CommittedCatalogs.swift` holds each path as a `static let` of the test target: `.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`, `.codex-plugin/plugin.json`, and `.well-known/agent-skills/index.json`. `CatalogSyncTests.expectedGeneratedPaths` is built from these four, and each test opens its file through one of them. No test reads a path from the generator.

    Proof by mutation: `ClaudeCatalog.path` was changed to `.claude-plugin/catalog.json`, and `scripts/generate-catalogs` ran one time. `swift test` failed:
    `CatalogSyncTests.swift:251`, `paths == Self.expectedGeneratedPaths`, 13 tests with 1 issue. `Every committed catalog file holds the generated bytes` passed in the same run, which shows that the drift test alone cannot find a changed path, and that the new literal test is what finds it. The source was reverted, the stray `.claude-plugin/catalog.json` was deleted, and the generator ran again.

    **2. The four declarations are no longer `public`.**
    A grep of every `public` in `Sources/` gives 5 matches in 2 files only: `CatalogGenerator`, `CatalogGenerator.init(repositoryRoot:)`, `CatalogGenerator.write()`, `GeneratedCatalogFile`, and `GeneratedCatalogFile.path`. `GeneratedCatalogFile.contents`, `CatalogGenerator.generate()`, `CatalogGenerator.repositoryRoot`, and `CatalogGeneratorError` with its `description` are `internal`. The package builds, and the test target reaches them with `@testable import`.

    **3. `swift test` is green with zero warnings.**
    13 tests in 2 suites pass, 0 failures. The log holds no `warning:` line and no `error:` line. The mutation run above compiled `CatalogGenerator` and the test target again, and it also reported no `warning:` line. Output went to a scratchpad log file, and no pipe to `tail` was used.

    **4. The tree is clean at `5a2ea62`, and the catalogs are current.**
    After the revert, the delete of the stray file, and a new run of `scripts/generate-catalogs`, `git status --porcelain` is empty. Thus the four committed catalogs are equal, byte for byte, to a new run of the generator. `git status --ignored` shows one ignored file, `Package.resolved`, which is not a generated catalog. `git ls-files` gives the four catalog files and no more.

    **The push is done.** `git log @{u}..HEAD` is empty, thus `5a2ea62` is on `origin/main`. The operator step of the card is satisfied.

    - evidence: 0 new findings. All 6 findings of rounds 1 and 2 are corrected and verified by mutation, not by reading. `swift test` — 13 tests in 2 suites, 0 failures, 0 warnings. Tree clean at `5a2ea62`, pushed.
    - next: none. The card moves to `done`. Nothing was committed and nothing was pushed by this step.
  timestamp: 2026-09-16T14:56:24.943341+00:00
depends_on:
- 01M2H0TYWZG3C9B557Z31CYEGP
position_column: done
position_ordinal: e580
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

- [x] `VERSION`, the `CatalogGenerator` target, the executable, and the wrapper script
- [x] The Claude catalog
- [x] The Codex catalog and plugin manifest
- [x] The well-known index with digests; commit the generated files
- [ ] **(operator)** `git push`

## Acceptance Criteria
- [x] `swift run generate-catalogs` writes the three files, and a second run changes nothing
- [x] The Claude catalog lists all 24 skills in exactly one plugin
- [x] CI fails when a committed catalog differs from the generator output

## Tests
- [x] `Tests/SkillsMarketplaceTests/CatalogSyncTests.swift` in `../skills`: generate in memory and compare byte for byte with each committed file; every skill folder is in the Claude plugin exactly once; each `digest` equals the SHA-256 of its `SKILL.md`; the Claude catalog `metadata.version` equals `VERSION`
- [x] Run `swift test` in `../skills`; expect green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cross-repo

## Review Findings (2026-09-16 09:15)

Scope: `/Users/wballard/github/swissarmyhammer/skills` at commit `cb6d503`. The `review` engine is bound to the FoundationModelsSkills root and cannot read a sibling repository, thus each check below was done by hand.

- [x] `Sources/CatalogGenerator/ClaudeCatalog.swift:10` `design/api-surface` — `ClaudeCatalog` and `DiscoveryIndex` are `public` and `Codable`, but `CodexCatalog` and `CodexPluginManifest` are `internal` and `Encodable`. The generator only encodes. The `public` visibility and the `Decodable` half are there only because `CatalogSyncTests` uses `import CatalogGenerator`. Make the four catalog types agree: use `@testable import CatalogGenerator` and give each type the same visibility and the same conformance.
- [x] `Sources/CatalogGenerator/CatalogGenerator.swift:19` `dead-code/unused-public` — `public static let versionFileName` has no user outside the module. `Tests/SkillsMarketplaceTests/CatalogSyncTests.swift:20` writes the literal `"VERSION"` a second time. Let the test read the constant, or make the constant `internal`.
- [x] `Tests/SkillsMarketplaceTests/CatalogSyncTests.swift:100` `tests/coverage-gap` — no test holds `.agents/plugins/marketplace.json` or `.codex-plugin/plugin.json` to a truth outside the generator. `committedCatalogsAreCurrent` compares the committed bytes with the output of the generator, thus it finds drift but never a wrong value. The Claude catalog gets `claudePluginListsEverySkillOnce` and `catalogVersionIsTheVersionFile`; the Codex pair gets nothing equal to these. A change of `CodexCatalog.Source.kind` away from `"local"`, or of `CodexPluginManifest.skills` away from `"./skills"`, passes every test after one run of the generator. Add a test that decodes the two committed Codex files and holds the plugin source kind, the source path, the skills folder, and the version equal to `VERSION`.
- [x] `Tests/SkillsMarketplaceTests/CatalogSyncTests.swift:114` `tests/tautology` — `generationIsDeterministic` calls `generate()` two times in one process and compares the results. Each encoded model is a struct with fixed `CodingKeys`, the encoder sets `.sortedKeys`, and the skills get an explicit `.sorted`. Thus the two results are equal by construction and the test cannot fail. Test the property the doc comment claims: call `write()` into a temporary root two times and compare the files on disk.

### What the review verified as correct

- **The catalogs are what the client parses.** `MarketplaceCatalog` and `CatalogResolver` read `name`, `owner`, `metadata.version`, `plugins[].name`, `plugins[].source`, and `plugins[].skills`. The Claude catalog gives every one of these. The source `"./"` normalizes to the root, and each `"./skills/<name>"` entry resolves to a folder that holds a `SKILL.md` file. `$schema`, `metadata.description`, `plugins[].description`, and the Codex `interface` are keys that `MarketplaceCatalog` documents as ignored, thus they are not a gap. The Codex catalog gives `name` and one `local` plugin at `./` with no `skills` array, thus `folderSkills` reads `skills/` and finds the same 24 skills. The generated files match the §3.3 example in `marketplace.md` field for field.
- **The generator is driven from the skill folders.** `CatalogGenerator` builds a `SkillsRegistry` over `skills/`, which is the loader the client itself uses.
- **The drift test genuinely fails.** Dropping `tdd` from the Claude catalog made two tests fail. Changing the version in `.codex-plugin/plugin.json` made `committedCatalogsAreCurrent` fail. Both files were restored and the tree is clean.
- **All 24 skills appear in each catalog that lists them.** 24 paths in the Claude plugin and 24 entries in the discovery index, equal to the 24 folders of `skills/` that hold a `SKILL.md`. `skills/_partials` holds no `SKILL.md` and is in neither file.
- **`swift test` passes with zero warnings.** 9 tests in 2 suites pass. A rebuild of every new source gives 0 warnings.
- **The repository is safe to publish.** No credential, no token, and no personal path is in the four generated files. The 24 frontmatter descriptions name only sah workflows and tools.
- **Swift style.** No force unwrap, no `try!`, no `as!`, no `@unchecked Sendable`, no `fatalError`, and no `print(`. Each number and format string has a name. Each public declaration has a doc comment.

## Review Findings (2026-09-16 09:40)

Scope: `/Users/wballard/github/swissarmyhammer/skills` at commit `efe7a14`, round 2. The `review` engine cannot read a sibling repository, thus each check below was done by hand.

- [x] `Tests/SkillsMarketplaceTests/CatalogSyncTests.swift:252` `tests/coverage-gap` — each test takes the path of a committed file from the generator itself: `ClaudeCatalog.path`, `CodexCatalog.path`, `CodexPluginManifest.path`, and `DiscoveryIndex.path`. The path is the most published value of a catalog, because a client finds the file by that name. This is the cause the 09:15 finding at line 100 names, and it is still in the file. Proof: `ClaudeCatalog.path` was changed to `.claude-plugin/catalog.json`, `scripts/generate-catalogs` ran one time, and all 12 tests passed, while `.claude-plugin/marketplace.json` kept the old bytes and no client would find the new file. Hold each of the four paths equal to a literal of the test, in the way `CommittedCatalogs.swift` holds each key name a second time.
- [x] `Sources/CatalogGenerator/GeneratedCatalogFile.swift:12` `dead-code/unused-public` — `GeneratedCatalogFile.contents`, `CatalogGenerator.generate()`, and `CatalogGenerator.repositoryRoot` are `public`, but no user outside the module reads them. `Sources/generate-catalogs/GenerateCatalogsMain.swift` calls `init`, `write()`, and `path` only, and the test target now uses `@testable import CatalogGenerator`. The `@testable import` of this round removed the one reason these three were `public`, which is the cause the 09:15 finding at line 19 names. Make the three `internal`, and keep `init`, `write()`, and `path` `public`.

### What round 2 verified as correct

- **The new Codex tests read a truth outside the generator.** `Tests/SkillsMarketplaceTests/CommittedCatalogs.swift` is a decode model of the test target, with the key names of the published format written a second time. The expected values are literals of `CatalogSyncTests`: `expectedLocalSourceKind = "local"`, `skillsFolderName = "skills"`, `expectedSkillsFolder = "./skills"`, `expectedPluginSource = "./"`. No value comes from a constant of the generator.
- **Mutation 1.** `CodexCatalog.localSourceKind` from `"local"` to `"git"`, then one run of the generator: `swift test` failed, `codexCatalogHoldsOneLocalPlugin` at `CatalogSyncTests.swift:288`, `plugin.source.kind == Self.expectedLocalSourceKind`. Reverted.
- **Mutation 2.** `CodexPluginManifest.skills` from `./skills` to `./`, then one run of the generator: `swift test` failed, `codexPluginManifestNamesTheSkillsFolder` at `CatalogSyncTests.swift:303`, `manifest.skills == Self.expectedSkillsFolder`. Reverted.
- **`generationIsDeterministic` can now fail.** It writes a fixture repository two times and reads the files back from disk. A `UUID` added to the release version of the generator made it fail at `CatalogSyncTests.swift:245`, `first == second`. Reverted.
- **The four catalog types agree.** `ClaudeCatalog`, `CodexCatalog`, `CodexPluginManifest`, and `DiscoveryIndex` are each `internal` and `Encodable` only.
- **The literal `"VERSION"` is written one time**, at `Sources/CatalogGenerator/CatalogGenerator.swift:20`. The test reads the constant.
- **`swift test` is green with zero warnings.** 12 tests in 2 suites pass. A rebuild of every source of `CatalogGenerator`, `generate-catalogs`, and the test target reports 0 warnings.
- **The tree is clean at `efe7a14`.** Each mutation was reverted, the generator ran again, and `git status` is empty. Nothing was committed and nothing was pushed.