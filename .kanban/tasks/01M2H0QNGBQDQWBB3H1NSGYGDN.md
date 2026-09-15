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