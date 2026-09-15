---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2jj54gefsk535mawr6rpmsk
  text: |-
    Research done.
    - `DotfolderStack.layers` is ordered lowest first (defaults < user < project). The package reaches layers through `stack.layers` and filters on `layer.source` (see `SkillDiscovery.roots(from:)`, `SkillsRegistry.init(stack:)`, `StencilPass`). `DotfolderStack.content(_:)` gives only the nearest copy, so the loader reads `<layer.root>/marketplaces.yaml` for each selected layer.
    - `MarketplaceSource` decodes with only `url`. Its encode is synthesized, so nil fields are not written.
    - `MarketplaceLocation` is internal. Its `normalizedURL` gives the URL merge key. A source with a bad URL has no normalized URL. The loader then uses the raw `url` text as the key, because validation of the list is the job of the store (`MarketplaceIdentity.validate`), not of the loader.
    - Yams: `YAMLDecoder().decode(_:from: String)` and `YAMLEncoder().encode(_:) -> String`. `FrontmatterDecoder` is the only other Yams user.
    - Plan: `MarketplaceConfig` (Codable, `marketplaces: [MarketplaceSource]`), a public `MarketplaceConfigError` that names the file, merge by a `MergeKey` enum (`alias` or `url`) so an alias never equals a URL key by accident.
  timestamp: 2026-09-15T12:55:01.390341+00:00
- actor: claude-code
  id: 01m2jjakw32rtnk2b3q3js9vth
  text: |-
    TDD RED recorded.
    - First run: `swift test --filter MarketplaceConfigTests` did not compile, because `MarketplaceConfig` and `MarketplaceConfigError` did not exist.
    - Second run, with a skeleton (`load` gives an empty list, `save` does nothing): 11 tests, 10 fail with 14 issues. Each failure is the expected one: no read, no merge, no save, no error.
    - `aMissingFileGivesAnEmptyList` passes on the skeleton. This is correct: an empty list is the correct result for a missing file. The test stays, so the real loader cannot treat a missing file as an error.
  timestamp: 2026-09-15T12:58:00.963289+00:00
- actor: claude-code
  id: 01m2jjdvfhjeare6kh37spmy99
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsSkills/Marketplace/MarketplaceConfig.swift (new), Sources/FoundationModelsSkills/Marketplace/MarketplaceConfigError.swift (new), Tests/FoundationModelsSkillsTests/MarketplaceConfigTests.swift (new). `swift test --filter MarketplaceConfigTests`: 11 tests in 1 suite pass. `swift test`: 473 tests in 36 suites pass, 0 failures, no warning lines.
    - notes: `load(from:includeProject:)` has no default. It reads `.user`, then `.project` only when `includeProject` is `true`. `.defaults` and `.marketplace` layers are never read. A missing file adds no entry. The merge key is a private `MergeKey` enum (`alias` or `url`), so an alias never matches a URL with the same text. Only the `url` field decides a URL key; `ref` and `sha` do not. A URL that does not parse keeps its raw text as its key, because the store validates the list later. Entries with the same key in one file stay, so that the store can record its duplicate-key diagnostic. `save(to:)` makes a missing parent folder and writes the file atomically. `MarketplaceConfigError` is public and holds `file` and `underlyingError`. Its `description` names the file path. The git binary is not used, and the code has no time values. No ARCHITECTURE.md exists.
    - next: /review
  timestamp: 2026-09-15T12:59:47.057022+00:00
- actor: claude-code
  id: 01m2jjsf0fym6t7r2d3djxf2b4
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (cc4f49f). 0 findings, 0 confirmed, 0 refuted. 7 attempts, 0 failed. 3 files reviewed. 6 .kanban files not reviewed because of .reviewignore.
    - next: None. The task has no prior review findings. The task moved to done.
  timestamp: 2026-09-15T13:06:07.503502+00:00
- actor: claude-code
  id: 01m2jjt2nv7hkaaz5rmjpjjehe
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 new files (MarketplaceConfig.swift, MarketplaceConfigError.swift, MarketplaceConfigTests.swift)
    - test: green — swift package clean && swift test, 473 passed, 0 failed, 0 skipped, 0 warnings
    - commit: cc4f49f feat(marketplace): add MarketplaceConfig for marketplaces.yaml
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-15T13:06:27.643604+00:00
depends_on:
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: done
position_ordinal: cb80
title: 'Add MarketplaceConfig: load and save marketplaces.yaml from the user and project layers'
---
## What

marketplace.md §6.3. A convenience for hosts. The host can still give the source list in code (plan.md decision 29).

Create `Sources/FoundationModelsSkills/Marketplace/MarketplaceConfig.swift`:
- A `Codable` model of `marketplaces.yaml`: `marketplaces: [MarketplaceSource]`, decoded with Yams. The order in the file is left to right, and the last entry wins.
- `static func load(from stack: DotfolderStack, includeProject: Bool) throws -> MarketplaceConfig`. It reads `marketplaces.yaml` from the `.user` layer, then from the `.project` layer only when `includeProject` is `true`. The parameter has **no default**, so the host must decide the trust gate. It appends the project list after the user list. When a project entry has the same merge key as a user entry, the project entry replaces it completely (no field merge), in the project's position. The merge key is `alias`, else the normalized URL from `MarketplaceLocation`.
- `func save(to url: URL) throws` writes YAML (for the CLI `add` and `remove` commands).
- An unparseable file throws an error that names the file.

- [x] Model and Yams decoding
- [x] `load(from:includeProject:)` with order and replace-by-key
- [x] `save(to:)` round trip
- [x] Error for a bad file

## Acceptance Criteria
- [x] With `includeProject: false`, a project file has no effect
- [x] A project entry with the same key replaces the user entry completely
- [x] `save` then `load` gives the same list

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceConfigTests.swift`: user only; user and project with order; replace-by-alias and replace-by-URL; `includeProject: false`; save and load round trip; a bad YAML file error names the file
- [x] Run `swift test --filter MarketplaceConfigTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace