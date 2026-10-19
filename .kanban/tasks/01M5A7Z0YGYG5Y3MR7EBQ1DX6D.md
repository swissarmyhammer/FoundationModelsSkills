---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5abjt21b9ejfazfgje8nknd
  text: |-
    Implementation notes:
    - Extras pin: Package.swift tracks FoundationModelsExtras `branch: "main"`, and Package.resolved is gitignored (.gitignore line `Package.resolved`). `swift package update FoundationModelsExtras` moved the local pin from 6c91b77 to 39c9cde (origin/main, which has e6b2bf9 as an ancestor). No tracked file changes for the bump; CI resolves main fresh.
    - Deleted the uncommitted Operations/SkillCatalogChange.swift (the second compare).
    - Added `SkillsToolDescription.catalogEntries(for:isListed:)` (internal): filter with the predicate, then a private `entries(for:)` maps each skill to `CatalogEntry(name: id, description: SkillCatalogText.oneLine(description))`. The description list (`list(for:)` / `describedList`) now builds from the same `entries(for:)`, so the list and the notice entries come from one place. The predicate has no default: the reload task (^ZGHC7Y1 / 01M5A7ZGHC7Y1KY81E8C5KPNWV) must pass `context.visibilityPredicate`.
    - Name clash to know: SkillsRegistry has a private nested `CatalogEntry`; inside SkillsRegistry the name means that type, not the Extras one.
    - Tests: SkillCatalogChangeTests.swift renamed to SkillCatalogEntriesTests.swift (suite `SkillCatalogEntriesTests`), 9 cases, each maps both catalogs and then calls `CatalogChangeNotice(kind: .skills, from:to:)`. RED was the compile error "type 'SkillsToolDescription' has no member 'catalogEntries'"; GREEN 9/9.
    - The only warning in the build is the SwiftPM build-system note "missing creator for mutated node ... mlx-swift_Cmlx.bundle", from the mlx-swift dependency, not from this package's sources.
  timestamp: 2026-10-19T15:13:19.425996+00:00
- actor: claude-code
  id: 01m5abjwfa7fr142h2exkk75pp
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsSkills/Operations/SkillsToolDescription.swift (edited), Sources/FoundationModelsSkills/Operations/SkillCatalogChange.swift (deleted, was uncommitted), Tests/FoundationModelsSkillsTests/SkillCatalogEntriesTests.swift (new, replaces uncommitted SkillCatalogChangeTests.swift), Package.resolved (gitignored; Extras 6c91b77 -> 39c9cde). `swift test --filter SkillCatalogEntriesTests`: 9 passed; full `swift test`: 629 tests in 57 suites passed, exit 0.
    - next: /review
  timestamp: 2026-10-19T15:13:21.898612+00:00
- actor: claude-code
  id: 01m5abmghs5b5a7bq0v9gg5drq
  text: |-
    ### test — green
    - evidence: swift test — 629 tests in 57 suites passed, 0 failed, 0 skipped; the only build warning is the known mlx-swift dependency "missing creator for mutated node ... mlx-swift_Cmlx.bundle", which appeared again; no warnings from this package
    - next: review
  timestamp: 2026-10-19T15:14:15.225267+00:00
- actor: claude-code
  id: 01m5abmxfa9dvz77a7zk6a8bkn
  text: |-
    ### commit — changed
    - evidence: ee62157 feat(tool-description): map listed skills to Extras catalog entries
    - next: review
  timestamp: 2026-10-19T15:14:28.458621+00:00
position_column: doing
position_ordinal: '80'
title: Map the listed skill catalog to [CatalogEntry] for the Extras catalog compare
---
#skills

## What
FoundationModelsExtras e6b2bf9 ships the compare and the text: `CatalogChangeNotice(kind: .skills, from:to:)`. It compares by name and description, and it gives nil when nothing changed. Order alone is not a change. It does NOT filter entries and does NOT normalize white space: the caller gives the entries exactly as the description lists them.

Thus this package only maps a catalog to entries: filter with the tool's visibility predicate, then map each skill to `CatalogEntry(name: id, description: SkillCatalogText.oneLine(description))`. Put the mapping next to `SkillsToolDescription` so that the description list and the notice entries come from one place.

Delete the uncommitted `SkillCatalogChange` (Operations/SkillCatalogChange.swift). It is a second compare, which the request forbids. Rewrite `SkillCatalogChangeTests` against the mapping plus the Extras compare. Keep the cases that test the skills side: a hidden skill, white space that `oneLine` collapses, parameters and source not counting, a skill turning hidden or visible, and a custom predicate.

## Acceptance
- [x] Bump the Extras pin to e6b2bf9 or later
- [x] Tests written first and seen failing, then passing; full `swift test` green