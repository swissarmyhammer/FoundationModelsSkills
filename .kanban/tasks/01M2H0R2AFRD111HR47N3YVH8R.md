---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: Add MarketplaceSource, URL forms, and marketplace identity rules
---
## What

marketplace.md §5.1, §5.3, §6.2. The value types that a host uses to name a marketplace. Pure values with no I/O. **This task is the only owner** of `SkillSelection`, `MarketplaceGrants`, and `MarketplaceDiagnostic`; other tasks use them.

Create in `Sources/FoundationModelsSkills/Marketplace/`:
- `MarketplaceSource.swift` — `public struct MarketplaceSource: Sendable, Hashable, Codable` with `url`, `ref`, `sha`, `path`, `alias`, `select: SkillSelection` (default `.all`), `autoUpdate: Bool` (default `true`), `grants: MarketplaceGrants` (default `.none`). `public init(_ url: String, ref:sha:path:alias:select:autoUpdate:grants:)` with defaults. `MarketplaceGrants` has `shellInjection: Bool` and `scripts: Bool`, and `static let none`.
- `SkillSelection.swift` — `public enum SkillSelection: Sendable, Hashable, Codable { case all, plugins([String]), skills([String]) }`.
- `MarketplaceDiagnostic.swift` — `public struct MarketplaceDiagnostic: Sendable, Hashable` with `severity`, `marketplaceID: String?`, `message: String`.
- `MarketplaceLocation.swift` — `enum MarketplaceLocation { case git(url: String, ref: String?), local(URL) }` parsed from `MarketplaceSource.url`. Forms: scp-like SSH (`git@host:owner/repo.git`), `https://…​.git`, `github:owner/repo` (expands to `https://github.com/owner/repo.git`), a `#ref` suffix (the `ref:` field wins over the suffix), and `file://`. A `normalizedURL` string (lowercase host, no trailing `/`).
- `MarketplaceIdentity.swift`:
  - The **pre-fetch key** = `alias`, else the last path component of the repository without `.git`. It is known before any fetch.
  - `cacheFolderName(key:normalizedURL:)` = `"\(key)-\(first 8 hex of SHA-256(normalizedURL))"` (CryptoKit).
  - `validate(_ sources:) -> [MarketplaceDiagnostic]` rejects two sources with the same pre-fetch key.
  - After a fetch, the catalog `name` becomes the display id (the store task records that).
- `sha` wins over `ref`, and a source with `sha` is pinned.
- `marketplace.md` §5.3: change the text to say that validation and the cache folder name use the pre-fetch key, and that the catalog name is the display id after a fetch.

- [ ] `MarketplaceSource`, `MarketplaceGrants`, `SkillSelection`, `MarketplaceDiagnostic`, Codable round trip
- [ ] `MarketplaceLocation` parsing for each §5.1 form, with errors for bad input
- [ ] Pre-fetch key, `cacheFolderName`, and duplicate-key validation
- [ ] The `marketplace.md` §5.3 text update

## Acceptance Criteria
- [ ] Each §5.1 URL form parses to the expected `MarketplaceLocation`
- [ ] `cacheFolderName` is stable for one URL and different for two URLs
- [ ] A list with a duplicate pre-fetch key gives a diagnostic

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceSourceTests.swift`: a parameterized table over the URL forms (SSH, HTTPS, `github:`, `#ref`, `file://`, invalid); `sha` over `ref`; alias over the repository name for the pre-fetch key; `cacheFolderName` golden value; duplicate-key rejection; Codable round trip of a `MarketplaceSource` with every field and of each `SkillSelection` case
- [ ] Run `swift test --filter MarketplaceSourceTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace