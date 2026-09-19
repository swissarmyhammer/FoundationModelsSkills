---
assignees:
- claude-code
depends_on:
- 01M2XD7YJF87V9PF0EPSG5CF2N
position_column: todo
position_ordinal: '9080'
title: Correct marketplace.md and the host documents for the Extras home of the marketplace
---
## What

The documents of this package state that the marketplace implementation lives here. After the move they must state that Extras holds it, and that this package holds only the registry hookup, the provenance in the diagnostics, and the CLI command group.

1. `marketplace.md`: change the status paragraph and the Part B statement ("marketplace support in this package") to name the `Marketplace` product of `FoundationModelsExtras` as the home of the store, the cache, the transport, the catalog read, the writer and the config. Change §4.3 and decision 8 (the `Source.marketplace` case is no longer the only thing in Extras). Change §6.2 so the sketch shows `import FoundationModelsSkills` still works through the re-export, and shows the `MarketplaceLayout` value. Change §12 to name the Extras cards as the phases MK5 and after. Change §13 to say the git fixture, the transport doubles and the catalog fixtures live in the `MarketplaceFixtures` product and the `MarketplaceTests` target of Extras, and that this package imports the doubles from that product. Change decision 10 to say the libgit2 dependency lives in Extras. Add a decision 16, dated 2026-09-19: Extras owns all marketplace file reading; there is no per-marketplace grant. Keep every other section as the design record.
2. `docs/marketplaces.md`: state in the intro that the types come from Extras through `FoundationModelsSkills`, and that a host that uses Extras alone can import `Marketplace` directly. Keep the `import FoundationModelsSkills` example, because it still compiles. Add the `MarketplaceLayout` line to the "Add a marketplace in code" section. Remove any sentence that says the store is part of this package.
3. `docs/security.md`, section `## Marketplaces`: rule 4 says "the `FoundationModelsSkills` library links no libgit2 and starts no `git` process; the test bundle links libgit2 only through the `MarketplaceFixtures` product of Extras, and libgit2 itself is a dependency of Extras". Keep the other rules.
4. `docs/development.md`: add one paragraph to the dependency notes: `Marketplace` and `MarketplaceFixtures` resolve from `FoundationModelsExtras` `main`, and a change to the marketplace behavior goes to that repository.
5. `README.md`: keep the `docs/marketplaces.md` bullet; add "(implemented in FoundationModelsExtras)" to it.
6. `plan.md` §11: no change of substance; check that the `--marketplace` paragraph still holds.

## Acceptance Criteria

- [ ] No document in this package says that the store, the cache, the transport, the catalog read, the writer or the config is implemented in this package.
- [ ] `marketplace.md` has decision 16 with the date `2026-09-19`, its §6.2 sketch names `MarketplaceLayout`, and its §13 names `MarketplaceFixtures`.
- [ ] `docs/security.md` says the library links no libgit2, and the test bundle links it only through `MarketplaceFixtures`.
- [ ] `MarketplaceDocsTests` still passes: the env variable names, the seven command names, the SSH diagnostic and the README link are all present.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceDocsTests.swift`: `marketplace.md` holds the strings `2026-09-19`, `MarketplaceLayout` and `MarketplaceFixtures`; `docs/marketplaces.md` and `docs/security.md` hold the string `FoundationModelsExtras`; none of `marketplace.md`, `docs/marketplaces.md`, `docs/security.md` holds the phrase `in this package` on a line that also holds `store`, `cache` or `transport`.
- [ ] Same file: the existing assertions (env variable names, command names, SSH diagnostic, README link) still pass.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#marketplace #skills