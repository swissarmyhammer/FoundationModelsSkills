---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m320z5ej8yy4yscgqet5tka7
  text: |-
    Research before the edit.

    Who still reads the fixtures:
    - `Tests/FoundationModelsSkillsTests/FixtureLibrary.swift` is the only file of the whole repository outside `Examples/marketplace-fixtures/` that names `marketplace-fixtures` or `marketplaceCatalog`. The helper `FixtureLibrary.marketplaceCatalog(named:thisFile:)` has no caller.
    - `FixtureLibraryTests.swift` holds no case that reads the catalog helper, thus there is no case to delete there.
    - No document under `docs/` names `marketplace-fixtures`. `Package.swift` names no path under `Examples/`. Thus nothing else must change.
    - `git ls-files` counts 53 tracked files under `Examples/marketplace-fixtures/`.

    Where the new walk goes:
    - `DependencyGraphTests` already holds `linesNaming(_:under:in:where:)` and `files(under:)`, a walk over every regular file of a directory. The new guard reuses them, thus no suite keeps a second copy of the walk. `SwiftSourceScan` cannot serve here, because it reads Swift files only and the fixture folder holds Markdown and JSON.
    - The walk reads `Tests/` as well, thus it would report its own file. The two markers are therefore joined at run time from two parts, thus no line of any file holds a whole marker and the walk needs no exception.
  timestamp: 2026-09-21T13:02:30.866511+00:00
- actor: claude-code
  id: 01m32159sfaacyhm4s0b4m17ya
  text: |-
    The work, in TDD order.

    RED: two new cases in `DependencyGraphTests` before any deletion.
    - `holdsNoMarketplaceCatalogFixtures()` -- the folder under `Examples/` must be gone.
    - `namesNoDeletedMarketplaceFixture()` -- the walk over `Sources/`, `Tests/` and `Examples/` must report no line that holds either name.
    Both failed for the right reason: the first named the folder that was there, and the second named `FixtureLibrary.swift` lines 50, 60 and 66.

    GREEN: deleted `FixtureLibrary.marketplaceCatalog(named:thisFile:)` with its doc comment, and `git rm -r Examples/marketplace-fixtures` (53 tracked files). Both cases pass now.

    A decision worth keeping: the two names join from two parts (`"marketplace" + "-fixtures"`, `"marketplaceCatalog" + "("`). The walk reads `Tests/`, thus a whole literal would make the guard file report itself and the case could never pass. The join keeps the whole name off every line, thus the walk needs no exception for its own suite and the acceptance criterion holds word for word.

    The documentation stands outside the walk. `docs/marketplace.md` names no fixture folder today, and the documents card `^eb2vsqg` owns §13.
  timestamp: 2026-09-21T13:05:51.919579+00:00
- actor: claude-code
  id: 01m3215dx0yt0c0f1mg4pwntrb
  text: |-
    ### implement -- changed
    - evidence: 55 files -- Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift (2 cases added), Tests/FoundationModelsSkillsTests/FixtureLibrary.swift (helper deleted), and 53 files deleted under Examples/marketplace-fixtures/. `swift build --build-tests`: exit 0, 0 warnings. `swift test`: 586 tests in 54 suites, 0 failures.
    - next: /review
  timestamp: 2026-09-21T13:05:56.128026+00:00
- actor: claude-code
  id: 01m321888c60hfz0nrydrmg7j5
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` — build complete, 0 warnings. `swift test` — 586 tests in 54 suites passed, 0 failures, 0 skipped.
    - check: `Examples/marketplace-fixtures/` is absent. No file under Sources/, Tests/, Examples/, docs/ has the text "marketplace-fixtures" or "marketplaceCatalog(".
    - next: ready for review.
  timestamp: 2026-09-21T13:07:28.652891+00:00
- actor: claude-code
  id: 01m321e39jyqprvpc4vfj2scxf
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 340b569) — 0 findings, 0 confirmed, 0 refuted, 7 validator runs attempted, 0 failed. 2 files reviewed; 57 files not reviewed (4 by an ignore rule, 53 because no validator matches a fixture file).
    - next: task moved from review to done. No findings to correct.
  timestamp: 2026-09-21T13:10:40.178907+00:00
- actor: wballard
  id: 01m321en4v13yy155hkw83qpqc
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 55 files (53 fixture files deleted)
    - test: green — swift test, 586 passed, 0 warnings
    - commit: 340b569
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-21T13:10:58.459751+00:00
depends_on:
- 01M2XD7YJF87V9PF0EPSG5CF2N
position_column: done
position_ordinal: ff8980
title: Delete the marketplace catalog fixtures and the fixture helper that reads them
---
## What

After the consume card, no test in this package reads the catalog fixtures. The three readers (`SnapshotWriterTests`, `MarketplaceCatalogTests`, `GitTreeFileSourceTests`) moved to Extras, which holds its own copy of the fixtures. The folder and its helper are now dead weight.

1. Delete `Examples/marketplace-fixtures/` (the 11 catalog fixtures).
2. Delete `FixtureLibrary.marketplaceCatalog(named:)` and its doc comment in `Tests/FoundationModelsSkillsTests/FixtureLibrary.swift`. Check `FixtureLibraryTests.swift` for a case that reads it, and delete that case.
3. Search `Sources/`, `Tests/`, `Examples/` and `docs/` for `marketplace-fixtures`, and remove each reference. `marketplace.md` §13 names the fixture folder; the documents card (`^eb2vsqg`) corrects §13 to say the fixtures live in Extras, so leave that document to that card.

## Acceptance Criteria

- [x] `Examples/marketplace-fixtures/` does not exist.
- [x] No file under `Sources/`, `Tests/` or `Examples/` names `marketplace-fixtures` or `marketplaceCatalog(`.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/FixtureLibraryTests.swift`: the remaining `FixtureLibrary` cases still pass, and no case names the catalog helper.
- [x] `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift` (or a new walk test): no file under `Sources/`, `Tests/` or `Examples/` holds the string `marketplace-fixtures`.
- [x] `swift test` -- all tests pass, 0 failures.

## Workflow
- Use `/tdd` -- write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail. #marketplace #skills