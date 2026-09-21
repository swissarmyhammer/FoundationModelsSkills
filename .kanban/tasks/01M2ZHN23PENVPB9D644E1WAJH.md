---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3209kphhrdkvsgzwbm9y5n9
  text: |-
    Picked up the card and moved it to `doing`.

    Research:
    - `Sources/FoundationModelsSkills/Marketplace/` is gone. Commit 07a77c8 deleted the whole folder when the marketplace moved to the `Marketplace` product of `FoundationModelsExtras`. A glob over `Sources/FoundationModelsSkills/*` lists 59 files and no `Marketplace/` folder.
    - A grep of `FrontmatterDocument.split` over the repository gives 3 matches in 2 files, and both files are test files:
      - `Tests/FoundationModelsSkillsTests/NoFrontmatterSplitTests.swift` (the marker constant and the positive predicate test).
      - `Tests/FoundationModelsSkillsTests/FixtureLibrary.swift` (`decodeOutcome(text:)`, a test helper).
      No file of `Sources/` names the split, thus the walk gives no offender with the filter removed.
    - The suite gives the walk to `SwiftSourceScan`, the shared reader that `NoGitProcessTests`, `NoStandardOutWriteTests` and `NoDotfolderStackExtensionTests` also use. `NoGitProcessTests` is the prevailing shape of a guard with no exception: one `reportedLines(inDirectory:matching:)` call, no filter, and a message that names the rule.

    Plan: delete `marketplacePath`, delete the `.filter`, rename the test to say no exception, correct the message, and take the two paragraphs about the Marketplace exception out of the suite documentation.
  timestamp: 2026-09-21T12:50:44.561940+00:00
- actor: claude-code
  id: 01m320g4527jd9s4a331wz4j4g
  text: |-
    Implementation landed in `Tests/FoundationModelsSkillsTests/NoFrontmatterSplitTests.swift`:
    - Deleted the `marketplacePath` constant and its documentation line.
    - Deleted the `.filter { !$0.hasPrefix(Self.marketplacePath) }` from the walk. The call is now one `SwiftSourceScan.reportedLines(inDirectory:matching:)`, the shape `NoGitProcessTests` uses.
    - Renamed `noFileUnderSourcesOutsideTheMarketplaceSplitsADocument()` to `noFileUnderSourcesSplitsADocument()`.
    - Took "outside Marketplace/" out of the failure message.
    - Replaced the two paragraphs about the `Marketplace/` exception in the suite documentation with one line: the walk has no exception.

    Red-green record. Before the green run, a probe file was staged at
    `Sources/FoundationModelsSkills/Marketplace/Probe.swift` holding one comment line with the split text. That is the exact path the deleted filter hid. The guard reported it:

        ✘ noFileUnderSourcesSplitsADocument() ... found: Sources/FoundationModelsSkills/Marketplace/Probe.swift:1

    The probe was then deleted, and the same test passed. Thus the walk truly covers the folder the exception protected, and the test can still fail.

    ### implement — changed
    - evidence: 1 file — `/Users/wballard/github/swissarmyhammer/FoundationModelsSkills/Tests/FoundationModelsSkillsTests/NoFrontmatterSplitTests.swift`. `swift build --build-tests` exit 0, 0 warnings. `swift test` exit 0: 584 tests in 54 suites passed, 0 failures.
    - next: `/review`
  timestamp: 2026-09-21T12:54:18.018985+00:00
- actor: claude-code
  id: 01m320kr3xtpab4d71zyygnvmx
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` — 0 warnings, build complete. `swift test` — 584 tests passed, 0 failed, 0 skipped, 54 suites passed.
    - next: none. The build and the test suite are clean.
  timestamp: 2026-09-21T12:56:16.765245+00:00
- actor: claude-code
  id: 01m320rncbk86xtghjb1rgx6h0
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (786df68) — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. 1 file reviewed; 4 `.kanban/` files left out by `.reviewignore`.
    - next: task moved to done. No open finding stays.
  timestamp: 2026-09-21T12:58:57.803513+00:00
- actor: wballard
  id: 01m320s3zpagws9ynpmvea8818
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 1 file
    - test: green — swift test, 584 passed, 0 warnings
    - commit: 786df68
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-21T12:59:12.758210+00:00
depends_on:
- 01M2XD7YJF87V9PF0EPSG5CF2N
position_column: done
position_ordinal: ff8880
title: Delete the Marketplace exception of the frontmatter-split guard
---
## What

`NoFrontmatterSplitTests` (`Tests/FoundationModelsSkillsTests/NoFrontmatterSplitTests.swift`) holds this package to the boundary rule: no file of `Sources/` splits a document itself, because `FrontmatterDocumentStack` of `FoundationModelsExtras` gives the split.

The guard has one exception today. `Marketplace/CatalogResolver.rootSkillName()` reads the root `SKILL.md` of a marketplace repository through a `CatalogFileSource`. That source can be a git tree (`GitTreeFileSource`), thus it is no dotfolder stack and the document stack cannot serve it. The case keeps one call of `FrontmatterDocument.split`, and the test filters the `Marketplace/` folder out of the walk.

Card ^sg5cf2n gives the marketplace to Extras and deletes that folder. After it lands, the exception has nothing to protect.

## Acceptance Criteria

- [x] `NoFrontmatterSplitTests` walks every file of `Sources/`, with no folder filtered out.
- [x] `marketplacePath` and the prose about it are gone from the suite.
- [x] No file of `Sources/FoundationModelsSkills/` names `FrontmatterDocument.split`.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

#loading-boundary #skills