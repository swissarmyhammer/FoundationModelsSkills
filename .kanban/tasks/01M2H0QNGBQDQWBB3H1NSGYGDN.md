---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2jkj908vyq35t6q5dzbdd14
  text: |-
    Research done.
    - No ARCHITECTURE.md exists.
    - `SkillSelection` and `MarketplaceDiagnostic` exist (sources task). Marketplace types are `internal` (for example `MarketplaceIdentity`, `MarketplaceLocation`). Thus the new catalog types are `internal` too.
    - Reuse: `PathConfinement.resolvedURL(relativePath:in:)` confines the local reader. `PathConfinement.isWellFormedRelativePath` checks catalog paths (it is `private` now; it must become `internal`). `SkillDiscovery.skillFileName` and `SkillDiscovery.excludedDirectoryNames` (`.git`, `node_modules`) are `private` now; they must become `internal` for the scan. `FrontmatterDecoder.decode(text:)` gives the name of a root `SKILL.md`.
    - Real catalog facts (read from the local Claude cache, no network): the official catalog has `renames` (9 entries, all to remote plugins, no `null`), and plugin sources `url` (155), `git-subdir` (89), and relative strings (52). A local plugin such as `./plugins/frontend-design` keeps its skills in `skills/<name>/SKILL.md`. A plugin such as `./plugins/code-review` has no `skills/` folder. `amd-skills` is `git-subdir` with a `skills` array relative to the plugin root. Codex uses `source: {source: "local", path: "./..."}` for a relative source.
    - Decisions: a skill name is its folder name (the same rule as discovery). The root `SKILL.md` of a scan takes its frontmatter `name`. Scan depth counts the path components of `SKILL.md` (`skills/x/SKILL.md` = 3). A `.plugins` selection reads only the selected plugins, so an unselected remote plugin gives no diagnostic. A listed skill folder with no `SKILL.md` file gives a warning and is skipped (discovery also skips such a folder).
  timestamp: 2026-09-15T13:19:40.552163+00:00
- actor: claude-code
  id: 01m2jma4r5y6ehbqs2vdq2rrcj
  text: |-
    Implementation done with TDD.
    - RED: the new `MarketplaceCatalogTests.swift` did not compile, because `CatalogResolver`, `ResolvedSkill`, `MarketplaceCatalog`, `LocalCatalogFileSource`, and `CatalogTreeEntry` did not exist.
    - GREEN: I added `CatalogFileSource.swift` (the protocol, `CatalogTreeEntry`, `CatalogFileSourceError`, and `LocalCatalogFileSource`), `MarketplaceCatalog.swift`, and `CatalogResolver.swift` (the resolver, `ResolvedCatalog`, `ResolvedSkill`, and `CatalogPath`). All new types are `internal`.
    - Reuse: `LocalCatalogFileSource` confines each path with `PathConfinement.resolvedURL(relativePath:in:)`. `CatalogPath.normalized` uses `PathConfinement.isWellFormedRelativePath` (now `internal`). The scan uses `SkillDiscovery.skillFileName` and `SkillDiscovery.excludedDirectoryNames` (now `internal`). The root `SKILL.md` name comes from `FrontmatterDecoder.decode(text:)`. The tests use `HotReloadTestSupport.makeTempDirectory()` and the new `FixtureLibrary.marketplaceCatalog(named:)`.
    - Fixtures (11 folders in `Examples/marketplace-fixtures/catalogs/`): `anthropics-skills`, `claude-plugins-official` (excerpt: 4 remote plugins, 3 local plugins, 2 real renames), `swissarmyhammer-skills`, `codex-catalog`, `claude-and-codex`, `duplicate-skills`, `remote-plugins` (`github`, `git-subdir`, `url`, `npm`), `renamed-skills` (includes a `null` rename), `repository-scan`, `single-skill-repository`, `nameless-root`. No file came from the network; the official excerpt is a hand copy of entries from the local Claude cache.
    - Behavior to know: a `.plugins` selection reads only the selected plugins, so an unselected remote plugin gives no diagnostic. A scan with a `.plugins` selection gives no skill and one warning for each name. An undecodable catalog gives one error and does not fall back to the Codex catalog or the scan. Renames follow one step only (the Claude map is old name to current name).
  timestamp: 2026-09-15T13:32:42.629482+00:00
- actor: claude-code
  id: 01m2jmacjp4m0k7p8pm9bfmvse
  text: |-
    ### implement — changed
    - evidence: 5 source/test files changed or added (Sources/FoundationModelsSkills/Marketplace/CatalogFileSource.swift, Sources/FoundationModelsSkills/Marketplace/MarketplaceCatalog.swift, Sources/FoundationModelsSkills/Marketplace/CatalogResolver.swift, Sources/FoundationModelsSkills/Resources/PathConfinement.swift, Sources/FoundationModelsSkills/Discovery/SkillDiscovery.swift), 2 test files (Tests/FoundationModelsSkillsTests/MarketplaceCatalogTests.swift, Tests/FoundationModelsSkillsTests/FixtureLibrary.swift), 58 fixture files in Examples/marketplace-fixtures/catalogs/. `swift test --filter MarketplaceCatalogTests`: 44 tests in 1 suite passed. `swift test`: 517 tests in 37 suites passed, 0 warnings, 0 failures, 0 skipped.
    - next: the task stays in doing. Run /review.
  timestamp: 2026-09-15T13:32:50.646899+00:00
- actor: claude-code
  id: 01m2jn1xwaqk5v6n1xbh3yb22v
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (commit 08a0a88). 4 findings, 4 confirmed, 0 refuted. Sources/FoundationModelsSkills/Marketplace/CatalogResolver.swift:418, Sources/FoundationModelsSkills/Marketplace/CatalogResolver.swift:434, Tests/FoundationModelsSkillsTests/MarketplaceCatalogTests.swift:473, Tests/FoundationModelsSkillsTests/MarketplaceCatalogTests.swift:488
    - next: Correct the 4 open items in "Review Findings (2026-09-15 08:38)". Put `selectedPlugins` and `selectedSkills` into one generic helper. Use one shared test helper for the temporary directory and for the SKILL.md text. Then run the review again. The task stays in `review`.
  timestamp: 2026-09-15T13:45:42.026980+00:00
- actor: claude-code
  id: 01m2jn2nxg8vwc39jr76kvg5b5
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — CatalogFileSource.swift, MarketplaceCatalog.swift, CatalogResolver.swift (new); PathConfinement.swift, SkillDiscovery.swift; MarketplaceCatalogTests.swift, FixtureLibrary.swift; fixtures in Examples/marketplace-fixtures/catalogs/
    - test: green — swift test, 517 passed, 0 failed, 0 skipped, 0 warnings
    - commit: 08a0a88 feat(marketplace): parse Claude, Codex, and scanned catalogs
    - review: findings — Sources/FoundationModelsSkills/Marketplace/CatalogResolver.swift:418, Sources/FoundationModelsSkills/Marketplace/CatalogResolver.swift:434, Tests/FoundationModelsSkillsTests/MarketplaceCatalogTests.swift:473, Tests/FoundationModelsSkillsTests/MarketplaceCatalogTests.swift:488
  timestamp: 2026-09-15T13:46:06.640875+00:00
- actor: claude-code
  id: 01m2jnhyyjfznef19qcqftrzgd
  text: |-
    Picked up the 4 findings of "Review Findings (2026-09-15 08:38)". The task is in doing again.
    - Findings 1 and 2: `selectedPlugins` and `selectedSkills` are replaced with one generic `selectedItems(_:by:noun:nameOf:)`. `SelectionNoun.selectedNames(in:)` gets the selection case. The same file had a second near-copy: the "compactMap(\.value) + flatMap(\.diagnostics)" join in `skills(of:inFolder:)`, `renamedNames`, and `scannedSkills`. It is now one `collected()` helper on `Array` where `Element == Diagnosed<Item?>`.
    - Finding 3: the new `Tests/FoundationModelsSkillsTests/MarketplaceTestSupport.swift` has `makeTempDirectory(withFiles:)` and `writeFile(_:to:)`. `MarketplaceCatalogTests` (was `makeTree`) and `ConfigFixture` in `MarketplaceConfigTests` (was `init` + `write`) use it.
    - Finding 4: the shared helper already existed: `ReloadTestSupport.skillFileContents(id:...)` and `writeSkillFile(id:in:...)`. `MarketplaceCatalogTests` (was `skillFileText`) and `SkillWatcherTests` (was a private `skillFileContents` + `writeSkillFile`) use it now. The watcher edit tests use `descriptionSuffix:` in place of `bodySuffix:`. The file text still changes between writes, so the signal assertions are the same.
    - Tool note: the `replace_all` flag of the `files` edit op changed only one occurrence each time. For many call sites, write the whole file.
  timestamp: 2026-09-15T13:54:27.410528+00:00
- actor: claude-code
  id: 01m2jnm9yp9r3wzyx3e2y16zgh
  text: |-
    ### implement — changed
    - evidence: 6 files. Sources/FoundationModelsSkills/Marketplace/CatalogResolver.swift (one generic `selectedItems(_:by:noun:nameOf:)` with `SelectionNoun.selectedNames(in:)`, and one `collected()` join helper); Tests/FoundationModelsSkillsTests/MarketplaceTestSupport.swift (new: `makeTempDirectory(withFiles:)`, `writeFile(_:to:)`); Tests/FoundationModelsSkillsTests/MarketplaceCatalogTests.swift; Tests/FoundationModelsSkillsTests/MarketplaceConfigTests.swift; Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift; Tests/FoundationModelsSkillsTests/ReloadTestSupport.swift (doc comment only). `swift test`: 517 tests in 37 suites passed, exit 0, 0 warnings, 0 errors. All 4 findings of "Review Findings (2026-09-15 08:38)" are checked. No assertion changed. The `git` binary was not used. No commit.
    - next: the task stays in doing. Run /review.
  timestamp: 2026-09-15T13:55:44.214951+00:00
depends_on:
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: doing
position_ordinal: '80'
title: Parse marketplace catalogs (Claude, Codex, repository scan) over a CatalogFileSource
---
## What

marketplace.md §5.2 and §6.4. Read a marketplace catalog and resolve the list of skills. Keep this code independent of git: it reads files through a small protocol. A local folder implements the protocol now; the libgit2 tree reader implements it later. Use `SkillSelection` and `MarketplaceDiagnostic` from the sources task (it owns them).

Create in `Sources/FoundationModelsSkills/Marketplace/`:
- `CatalogFileSource.swift` — `protocol CatalogFileSource: Sendable` with `func contents(atPath: String) throws -> Data?` and `func entries(inDirectory: String) throws -> [CatalogTreeEntry]`. `CatalogTreeEntry` has `name` and `kind` (`.file(isExecutable: Bool)`, `.directory`, `.symlink(target: String)`, `.submodule`). Add `LocalCatalogFileSource(root: URL)`.
- `MarketplaceCatalog.swift` — `Decodable` models for `.claude-plugin/marketplace.json`: `name`, `owner`, `metadata.version`, `plugins[]` (`name`, `source` as a string or an object, `strict`, `skills: [String]?`), `renames: [String: String?]`.
- `CatalogResolver.swift` — `CatalogResolver.resolve(from: any CatalogFileSource, selection: SkillSelection) -> ResolvedCatalog`. Order: `.claude-plugin/marketplace.json`, then `.agents/plugins/marketplace.json`, then a scan (`skills/*/SKILL.md`, then a root `SKILL.md`, maximum depth 3; the shallower one wins). `ResolvedCatalog` has `name`, `version`, `skills: [ResolvedSkill(name, path, plugin)]`, `renames`, `diagnostics: [MarketplaceDiagnostic]`.

Rules: use a plugin's `skills` array, else `<plugin source>/skills/*/SKILL.md`. A plugin with a remote `source` object (`github`, `git-subdir`, `url`) gets a diagnostic and is skipped. A duplicate skill name inside one catalog gets a diagnostic; the later plugin wins. A renamed selected name maps to the new name with a diagnostic; `null` means removed.

Fixtures go in `Examples/marketplace-fixtures/catalogs/`, found from `#filePath` in the same way as `Tests/FoundationModelsSkillsTests/FixtureLibrary.swift`: a copy of the `anthropics/skills` catalog, an excerpt of the Claude official catalog with `renames` and a `git-subdir` plugin, and a catalog in our own format.

- [x] `CatalogFileSource` and `LocalCatalogFileSource`
- [x] `MarketplaceCatalog` decoding (a `source` given as a string or an object)
- [x] `CatalogResolver`: order, plugin skills, scan fallback, duplicates
- [x] Selection filter and `renames`
- [x] Fixtures

## Acceptance Criteria
- [x] The resolver gives the correct skill list for all three fixture catalogs and for a catalog-free fixture folder
- [x] A remote plugin source, a duplicate, an unknown selected name, and a renamed name each give exactly one diagnostic and never throw

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceCatalogTests.swift`: golden tests for each fixture catalog; the Codex path; the scan fallback with depth and shallow-wins; `.plugins` and `.skills` selection; `renames`; a remote plugin source is skipped with a diagnostic
- [x] Run `swift test --filter MarketplaceCatalogTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace

## Review Findings (2026-09-15 08:38)

> Scope: `review sha HEAD~1..HEAD` (commit 08a0a88). The review examined only the lines that this change added or changed. The review examined 7 files. It did not examine 57 files.

> The review did not examine 4 files, because an ignore rule excludes them:
> - `.kanban/ (from .reviewignore)` — 4 files

> The review did not examine 53 files, because no validator applies to them. All 53 files are fixture data below `Examples/marketplace-fixtures/catalogs/`:
> - `anthropics-skills/` — `.claude-plugin/marketplace.json` and 16 `skills/*/SKILL.md` files
> - `claude-and-codex/` — `.agents/plugins/marketplace.json`, `.claude-plugin/marketplace.json`, `skills/from-claude/SKILL.md`, `skills/from-codex/SKILL.md`
> - `claude-plugins-official/` — `.claude-plugin/marketplace.json`, `plugins/code-review/commands/code-review.md`, `plugins/frontend-design/skills/frontend-design/SKILL.md`, `plugins/skill-creator/skills/skill-creator/SKILL.md`
> - `codex-catalog/` — `.agents/plugins/marketplace.json`, `plugins/tools/skills/format/SKILL.md`, `plugins/tools/skills/lint/SKILL.md`, `plugins/tools/skills/notes/README.md`
> - `duplicate-skills/` — `.claude-plugin/marketplace.json`, `first/alpha/SKILL.md`, `first/shared/SKILL.md`, `second/skills/shared/SKILL.md`
> - `nameless-root/SKILL.md`
> - `remote-plugins/` — `.claude-plugin/marketplace.json`, `skills/local-one/SKILL.md`
> - `renamed-skills/` — `.claude-plugin/marketplace.json`, `skills/new-name/SKILL.md`, `skills/steady/SKILL.md`
> - `repository-scan/` — `docs/README.md`, `gamma/SKILL.md`, `nested/deep/delta/SKILL.md`, `skills/alpha/SKILL.md`, `skills/beta/SKILL.md`, `skills/gamma/SKILL.md`
> - `single-skill-repository/` — `SKILL.md`, `skills/solo/SKILL.md`
> - `swissarmyhammer-skills/` — `.claude-plugin/marketplace.json`, `skills/_partials/sah-task-standards.md`, `skills/code-context/SKILL.md`, `skills/commit/SKILL.md`, `skills/tdd/SKILL.md`, `skills/tdd/writing-good-tests.md`

- [x] `Sources/FoundationModelsSkills/Marketplace/CatalogResolver.swift:418` `duplication/duplication` — `selectedPlugins` and `selectedSkills` (line 434) are almost the same code. Each function examines one selection case. If the case does not match, the function returns all items. If the case matches, the function calls `filtered` with a different noun value. The only differences are the variable names and the literal values. Move this code into one shared function. Make a generic helper that has the selection case and the noun as parameters, and call it from the two functions. Example: `private func selectedItems<T>(_ items: [T], selection: SkillSelection, selectNames: (SkillSelection) -> [String]?, noun: SelectionNoun, nameOf: (T) -> String)`. This removes the duplicate guard and filter code.
- [x] `Sources/FoundationModelsSkills/Marketplace/CatalogResolver.swift:434` `duplication/duplication` — `selectedSkills` and `selectedPlugins` (line 418) are almost the same code. Each function examines one selection case. If the case does not match, the function returns all items. If the case matches, the function calls `filtered` with a different noun value. The only differences are the variable names and the literal values. Move this code into one shared function. Make a generic helper that has the selection case and the noun as parameters, and call it from the two functions. Example: `private func selectedItems<T>(_ items: [T], selection: SkillSelection, selectNames: (SkillSelection) -> [String]?, noun: SelectionNoun, nameOf: (T) -> String)`. This removes the duplicate guard and filter code.
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceCatalogTests.swift:473` `reuse/reuse` — This function makes a temporary directory again, but code for this is already in the project. `ConfigFixture::write` in `MarketplaceConfigTests.swift` does the same work: it makes a temporary directory and writes files into it from a dictionary. Make this function call the existing function, or put the two functions into one shared test utility. Make a shared test helper `makeTempDirectory(withFiles:)` in a common location (for example, `HotReloadTestSupport` or `FixtureLibrary`). Call it from `MarketplaceCatalogTests` and from `MarketplaceConfigTests`.
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceCatalogTests.swift:488` `reuse/reuse` — This function makes SKILL.md file text again, but code for this is already in the project. `skillFileContents` in `SkillWatcherTests.swift` does the same work: it makes a standard markdown template with frontmatter. Make this function call the existing function, or put the two functions into one shared test utility. Make a shared test helper `makeSkillFileText(named:)` in a common location (for example, `FixtureLibrary` or a new test utility module). Call it from `MarketplaceCatalogTests` and from `SkillWatcherTests`.