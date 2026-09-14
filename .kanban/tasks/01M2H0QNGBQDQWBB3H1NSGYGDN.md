---
assignees:
- claude-code
depends_on:
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: todo
position_ordinal: '8280'
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

- [ ] `CatalogFileSource` and `LocalCatalogFileSource`
- [ ] `MarketplaceCatalog` decoding (a `source` given as a string or an object)
- [ ] `CatalogResolver`: order, plugin skills, scan fallback, duplicates
- [ ] Selection filter and `renames`
- [ ] Fixtures

## Acceptance Criteria
- [ ] The resolver gives the correct skill list for all three fixture catalogs and for a catalog-free fixture folder
- [ ] A remote plugin source, a duplicate, an unknown selected name, and a renamed name each give exactly one diagnostic and never throw

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceCatalogTests.swift`: golden tests for each fixture catalog; the Codex path; the scan fallback with depth and shallow-wins; `.plugins` and `.skills` selection; `renames`; a remote plugin source is skipped with a diagnostic
- [ ] Run `swift test --filter MarketplaceCatalogTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace