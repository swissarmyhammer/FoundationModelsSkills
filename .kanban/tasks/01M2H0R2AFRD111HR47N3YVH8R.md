---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2jh6efsxte0qydaxse6wapz
  text: |-
    Research results:
    - No ARCHITECTURE.md. The Marketplace folder had only Git/GitTransport.swift and Git/LibGit2Transport.swift. No code used CryptoKit before this task.
    - NoGitProcessTests scans Sources/ for a line that starts a process and names git. The new files start no process.
    - The store task needs MarketplaceIdentity.validate on the pre-fetch keys. The config task decodes marketplaces.yaml as [MarketplaceSource] with Yams, and its merge key is the alias, else the normalized URL. Thus MarketplaceSource decodes with only `url`: a missing field gets the init default.
    - The allowlist task (SourcePattern) matches on MarketplaceLocation.normalizedURL. Thus the github: shorthand normalizes to https://github.com/owner/repo.git, and a local folder normalizes to file://<path> with no trailing slash.
    - Decisions: SkillSelection encodes `.all` as the string "all", and the other cases as a map with one key (plugins or skills). The Swift default form (`_0`) is hard to read in YAML. A git form must end in .git, so that the later HTTPS marketplace.json form (§5.1) is not read as git. An HTTPS URL with a user name or a password is refused, because credentials come from MarketplacePolicy.credentials. A pre-fetch key with "/" or NUL, or an empty key, is refused, because the key is one folder name in the cache.
    - The scheme and the github: prefix are not case sensitive. The host is written in lowercase.
  timestamp: 2026-09-15T12:38:15.801344+00:00
- actor: claude-code
  id: 01m2jhkxr4fk48fxt819y7wjg6
  text: |-
    ### implement — changed
    - evidence: 7 new files: Sources/FoundationModelsSkills/Marketplace/SkillSelection.swift, MarketplaceSource.swift (MarketplaceGrants and MarketplaceSource), MarketplaceDiagnostic.swift, MarketplaceSourceError.swift, MarketplaceLocation.swift, MarketplaceIdentity.swift; Tests/FoundationModelsSkillsTests/MarketplaceSourceTests.swift. 1 changed file: marketplace.md §5.3.
    - evidence: TDD. RED: the test build failed because the types did not exist. GREEN: `swift test --filter MarketplaceSourceTests` passed 28 tests in 1 suite, 0 failures. `swift test` passed 462 tests in 35 suites, exit 0, 0 warnings.
    - evidence: swiftlint 0.65 with the validator rules (force_unwrapping, no_magic_numbers, missing_docs, function_body_length, and others) found 0 problems. swiftformat --lint with the validator rules: 0 of 7 files need formatting. One preferLazyMap finding in MarketplaceIdentity.duplicateKeyDiagnostics was corrected.
    - note: periphery did not run here. SwiftPM made no index store, also with --enable-index-store and a clean scratch build. Each new internal symbol has a caller in the tests or in the production code. The review step runs periphery.
    - note: marketplace.md §6.2 is an illustrative sketch. Its comment on `alias` still says "it wins over the catalog name". The new §5.3 text makes the alias the pre-fetch key, and the catalog name the display id after a fetch. The store task owns the display id. §6.2 can need the same change. This task did not change §6.2, because the card names only §5.3.
    - next: /review
  timestamp: 2026-09-15T12:45:37.412019+00:00
position_column: doing
position_ordinal: '80'
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

- [x] `MarketplaceSource`, `MarketplaceGrants`, `SkillSelection`, `MarketplaceDiagnostic`, Codable round trip
- [x] `MarketplaceLocation` parsing for each §5.1 form, with errors for bad input
- [x] Pre-fetch key, `cacheFolderName`, and duplicate-key validation
- [x] The `marketplace.md` §5.3 text update

## Acceptance Criteria
- [x] Each §5.1 URL form parses to the expected `MarketplaceLocation`
- [x] `cacheFolderName` is stable for one URL and different for two URLs
- [x] A list with a duplicate pre-fetch key gives a diagnostic

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceSourceTests.swift`: a parameterized table over the URL forms (SSH, HTTPS, `github:`, `#ref`, `file://`, invalid); `sha` over `ref`; alias over the repository name for the pre-fetch key; `cacheFolderName` golden value; duplicate-key rejection; Codable round trip of a `MarketplaceSource` with every field and of each `SkillSelection` case
- [x] Run `swift test --filter MarketplaceSourceTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace