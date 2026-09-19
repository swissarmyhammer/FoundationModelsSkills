---
assignees:
- claude-code
depends_on:
- 01M2XD7YJF87V9PF0EPSG5CF2N
position_column: todo
position_ordinal: '9280'
title: Delete the marketplace catalog fixtures and the fixture helper that reads them
---
## What

After the consume card, no test in this package reads the catalog fixtures. The three readers (`SnapshotWriterTests`, `MarketplaceCatalogTests`, `GitTreeFileSourceTests`) moved to Extras, which holds its own copy of the fixtures. The folder and its helper are now dead weight.

1. Delete `Examples/marketplace-fixtures/` (the 11 catalog fixtures).
2. Delete `FixtureLibrary.marketplaceCatalog(named:)` and its doc comment in `Tests/FoundationModelsSkillsTests/FixtureLibrary.swift`. Check `FixtureLibraryTests.swift` for a case that reads it, and delete that case.
3. Search `Sources/`, `Tests/`, `Examples/` and `docs/` for `marketplace-fixtures`, and remove each reference. `marketplace.md` §13 names the fixture folder; the documents card (`^eb2vsqg`) corrects §13 to say the fixtures live in Extras, so leave that document to that card.

## Acceptance Criteria

- [ ] `Examples/marketplace-fixtures/` does not exist.
- [ ] No file under `Sources/`, `Tests/` or `Examples/` names `marketplace-fixtures` or `marketplaceCatalog(`.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/FixtureLibraryTests.swift`: the remaining `FixtureLibrary` cases still pass, and no case names the catalog helper.
- [ ] `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift` (or a new walk test): no file under `Sources/`, `Tests/` or `Examples/` holds the string `marketplace-fixtures`.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail. #marketplace #skills