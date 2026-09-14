---
assignees:
- claude-code
depends_on:
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: todo
position_ordinal: 8a80
title: 'Add MarketplaceConfig: load and save marketplaces.yaml from the user and project layers'
---
## What

marketplace.md §6.3. A convenience for hosts. The host can still give the source list in code (plan.md decision 29).

Create `Sources/FoundationModelsSkills/Marketplace/MarketplaceConfig.swift`:
- A `Codable` model of `marketplaces.yaml`: `marketplaces: [MarketplaceSource]`, decoded with Yams. The order in the file is left to right, and the last entry wins.
- `static func load(from stack: DotfolderStack, includeProject: Bool) throws -> MarketplaceConfig`. It reads `marketplaces.yaml` from the `.user` layer, then from the `.project` layer only when `includeProject` is `true`. The parameter has **no default**, so the host must decide the trust gate. It appends the project list after the user list. When a project entry has the same merge key as a user entry, the project entry replaces it completely (no field merge), in the project's position. The merge key is `alias`, else the normalized URL from `MarketplaceLocation`.
- `func save(to url: URL) throws` writes YAML (for the CLI `add` and `remove` commands).
- An unparseable file throws an error that names the file.

- [ ] Model and Yams decoding
- [ ] `load(from:includeProject:)` with order and replace-by-key
- [ ] `save(to:)` round trip
- [ ] Error for a bad file

## Acceptance Criteria
- [ ] With `includeProject: false`, a project file has no effect
- [ ] A project entry with the same key replaces the user entry completely
- [ ] `save` then `load` gives the same list

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceConfigTests.swift`: user only; user and project with order; replace-by-alias and replace-by-URL; `includeProject: false`; save and load round trip; a bad YAML file error names the file
- [ ] Run `swift test --filter MarketplaceConfigTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace