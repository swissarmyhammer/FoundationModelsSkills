---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m31z67cx07ax68gjdj2nxa7d
  text: |-
    Part of item 2 is done already, by the card `^sg5cf2n`: the "Add a marketplace in code" example of `docs/marketplaces.md` passes `layout: SkillMarketplaceLayout.skills` now, because the Extras initializer needs a layout and the example would otherwise not compile. The rest of item 2 (the intro sentences) and every other item are still open.

    Note for item 1: the §6.2 sketch of `marketplace.md` still writes `MarketplaceStore(sources: [...])` with no layout, thus a reader who copies it gets code that does not compile. Give that sketch the same `layout:` line.
  timestamp: 2026-09-21T12:31:25.085626+00:00
- actor: claude-code
  id: 01m326yhbeg2j91tt44twbmdy3
  text: |-
    Research, before the edit.

    State of the code that the documents must now match:
    - `Package.swift` takes `Marketplace` from `FoundationModelsExtras` for the library, and `MarketplaceFixtures` from the same package for the test target only. No manifest entry of this package names a git package; Extras pins `danielctull-forks/swift-libgit2` `exact: "1.9.7"` for its `Marketplace` target alone, and its own comment dates that decision `2026-09-19`.
    - Extras holds the products `Marketplace` and `MarketplaceFixtures`, and the test target `MarketplaceTests`.
    - `Sources/FoundationModelsSkills/SeamReexports.swift` re-exports `Marketplace`, thus `import FoundationModelsSkills` alone still compiles the host example.
    - `MarketplaceStore.init` of Extras needs `layout: MarketplaceLayout`. `Sources/FoundationModelsSkills/Discovery/SkillMarketplaceLayout.swift` gives `SkillMarketplaceLayout.skills`, the one value of that type for a skill tree.
    - `Render/StencilPass.swift` stays here but holds no Stencil work: it makes an Extras `StenciledDotfolderStack` for each render. That stack reads the layer tag, renders each layer that is not `.defaults` untrusted, scopes the partials (`partialsStack(for:)`), and gives each quarantined span to Stencil as a value. Thus `marketplace.md` §4.3, §6.5 and decision 8 must not name a local `StencilPass.resolvedTrust` or a local `partialsStack(layers:)` change any more.
    - `PathConfinement` and the watcher are gone from `Sources/`; Extras holds both.
    - Four test files import `MarketplaceFixtures`: `MarketplaceTestSupport.swift`, `MarketplaceCLITests.swift`, `MarketplaceLocalSourceTests.swift`, `MarketplaceEndToEndTests.swift`.

    Decision on the number of the new decision: the card asks for "a decision 16, dated 2026-09-19". The decision list of `marketplace.md` grew after the card was written and already holds 1 to 18, thus 16, 17 and 18 name other decisions that still hold. A renumber would break each reference to them. The new decision goes in at the next free number, 19, with the date `2026-09-19` and the text the card states. The acceptance criterion that a test can read -- the date string in `marketplace.md` -- holds.

    `plan.md` §11: the `--marketplace` paragraph names the command group of `marketplace.md` §9.3 over the fixture library. This package still holds that command group, thus the paragraph holds with no change.
  timestamp: 2026-09-21T14:47:01.742462+00:00
- actor: claude-code
  id: 01m327drq4f9xqsr7stx5wsv66
  text: |-
    Implementation landed. TDD order: the new document claims were written first and failed (5 issues over `marketplace.md`, `docs/marketplaces.md` and `docs/security.md`), then the documents made them pass.

    `Tests/FoundationModelsSkillsTests/MarketplaceDocsTests.swift`
    - New claims: `docs/marketplaces.md`, `docs/security.md` and `marketplace.md` each name `FoundationModelsExtras`; `docs/security.md` and `marketplace.md` each name `MarketplaceFixtures`; `marketplace.md` names the date `2026-09-19` and the layout type. The layout name comes from `String(describing: MarketplaceLayout.self)`, thus a rename in Extras fails the suite and does not go quiet.
    - New test `noDocumentPutsAMovedPartInThisPackage`: no line of the three documents holds the phrase `in this package` beside the word `store`, `cache` or `transport`. It passed from the first run, because no line held that pair. It is the guard that keeps a later edit from putting a moved part back here.

    `marketplace.md`
    - The status paragraph and the Part B bullet name the `Marketplace` product of `FoundationModelsExtras` as the home, and this package as the consumer of it.
    - §4.3 drops the name `StencilPass.resolvedTrust` and names `StenciledDotfolderStack`; it records that the case shipped and that the rest of Part B followed it to Extras.
    - §5.1 says Extras holds the libgit2 dependency and the `GitTransport` wrapper, and that the pin is in the Extras manifest.
    - §6.2 names the product, shows that `import FoundationModelsSkills` is still sufficient through the re-export, and gives the sketch and the API the `layout:` argument.
    - §6.3 names the `Marketplace` product as the giver of `MarketplaceConfig`.
    - §6.5 names `StenciledDotfolderStack.partialsStack(for:)` in place of the local change that the plan first named.
    - §10 rule 4 says the library links no libgit2 and the test bundle reaches it only through `MarketplaceFixtures`.
    - §12 records that MK0 to MK6 shipped, and that MK5 and each phase after it are cards of Extras now.
    - §13 has a new paragraph "Where the fixtures live", and the git fixture and the transport doubles name `GitFixtureRepository`, `RecordingGitTransport` and `GatedGitTransport` of `MarketplaceFixtures`. The catalog goldens name `MarketplaceFixtures` and `MarketplaceTests`.
    - Decision 10 has the 2026-09-19 amendment for the libgit2 home. Decision 19 is new.
    - The Sources list names `StenciledDotfolderStack.swift`, `Sources/Marketplace/`, `Tests/MarketplaceFixtures/` and `Tests/MarketplaceTests/`.
    - A second pass took each other sentence that still said "the package" for a moved part: the non-goals, §6.3, §8.2, and the MK0 phase line.

    `docs/marketplaces.md`: a new intro paragraph names the five types and the two import forms; the code comment names `MarketplaceLayout` beside `SkillMarketplaceLayout.skills`; the SSH paragraph, the source-list paragraph and the check paragraph say "the store" in place of "the package".

    `docs/security.md`: the section intro names the Extras product; rule 4 carries the libgit2 sentence that the card states.

    `docs/development.md`: a new dependency note for `Marketplace` and `MarketplaceFixtures`.

    `README.md`: the marketplaces bullet now reads "(implemented in FoundationModelsExtras)".

    `plan.md`: read and left as it stands. The §11 `--marketplace` paragraph names the command group over the fixture library, which this package still holds.

    `CHANGELOG.md`: no entry. The file records each change of the public API, and this change is documentation only.

    Verification: `swift build --build-tests` — build complete, 0 warnings. `swift test` — 570 tests in 56 suites, 0 failures.
  timestamp: 2026-09-21T14:55:20.804740+00:00
- actor: claude-code
  id: 01m327dx0w54knzmwa0djcr3qq
  text: |-
    ### implement — changed
    - evidence: 8 files — marketplace.md, docs/marketplaces.md, docs/security.md, docs/development.md, README.md, Tests/FoundationModelsSkillsTests/MarketplaceDocsTests.swift (plus the two kanban files of this card). `swift build --build-tests`: build complete, 0 warnings. `swift test`: 570 tests in 56 suites, 0 failures. `swift test --filter MarketplaceDocsTests` before the document edits: 5 issues; after: 6 tests pass.
    - next: /review. The card stays in `doing`.
  timestamp: 2026-09-21T14:55:25.212389+00:00
- actor: claude-code
  id: 01m327gspy2fgqh8rzgjjtecre
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` — build complete, 0 warnings. `swift test` — 570 tests in 56 suites passed, 0 failures, 0 skipped.
    - next: ready for review.
  timestamp: 2026-09-21T14:57:00.126662+00:00
depends_on:
- 01M2XD7YJF87V9PF0EPSG5CF2N
position_column: doing
position_ordinal: '80'
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

- [x] No document in this package says that the store, the cache, the transport, the catalog read, the writer or the config is implemented in this package.
- [x] `marketplace.md` has the new decision with the date `2026-09-19`, its §6.2 sketch names `MarketplaceLayout`, and its §13 names `MarketplaceFixtures`. The decision stands at number 19, not 16: the list grew to 18 after the card was written, thus 16, 17 and 18 name other decisions that still hold, and a renumber would break each reference to them.
- [x] `docs/security.md` says the library links no libgit2, and the test bundle links it only through `MarketplaceFixtures`.
- [x] `MarketplaceDocsTests` still passes: the env variable names, the seven command names, the SSH diagnostic and the README link are all present.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/MarketplaceDocsTests.swift`: `marketplace.md` holds the strings `2026-09-19`, `MarketplaceLayout` and `MarketplaceFixtures`; `docs/marketplaces.md` and `docs/security.md` hold the string `FoundationModelsExtras`; none of `marketplace.md`, `docs/marketplaces.md`, `docs/security.md` holds the phrase `in this package` on a line that also holds `store`, `cache` or `transport`.
- [x] Same file: the existing assertions (env variable names, command names, SSH diagnostic, README link) still pass.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#marketplace #skills