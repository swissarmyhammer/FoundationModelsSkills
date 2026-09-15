---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2jzqys3bj1xv6xct2kbnaf1
  text: |-
    Research and decisions of the implementation.

    What is already there, and what this task adds:
    - `CatalogFileSource` gives `contents(atPath:)` and `entries(inDirectory:)`, and `CatalogTreeEntry.Kind` already has `.file(isExecutable:)`, `.directory`, `.symlink(target:)` and `.submodule`. Thus the writer needs no new read protocol.
    - `CatalogPath` holds the tree path rules (`separator`, `child(named:of:)`, `display(path:)`). The writer uses them, and adds no second path helper.
    - `MarketplaceCache` keeps the install, the swap and the lock. The writer only stages the folder.

    Signature: the card writes `write(_ catalog:...)`. The file uses `write(catalog:from:to:limits:)`. Every parameter, the behavior and the result are the same. The label is there because the house rule says that a first argument carries a label unless the call is a value-preserving conversion, and because every other marketplace call in this package labels its first argument (`CatalogResolver.resolve(from:selection:)`, `MarketplaceCache.install(snapshotAt:sha:ref:)`).

    Name rule: the writer checks each name with its own `validated(name:inDirectory:)`, which throws `SnapshotError` as the card asks. The rule is the rule of `MarketplaceCache.isSafe(component:)`: no empty name, no separator (`/` or `\`), no control character. It adds the two names that walk out of a folder or name the folder itself: a name that holds `..`, and the name `.`. A name with a leading dot stays permitted, because a skill folder can hold a `.gitignore` file, and a refusal there would stop the whole snapshot.

    Symbolic link rule: the writer counts levels. It reads no file, so a link to a file that is not there gives the same answer. A target that starts with `/` or `~`, or that walks above the root of its own skill folder, throws. A link that stays inside is copied as a link.

    Counts: the check comes after the count, so `maxFiles: 1` permits the first file and throws at the second. A symbolic link counts as one file with zero bytes.

    Partials: the writer takes the folder of each selected skill folder, one time each, in catalog order, and copies `<folder>/_partials` into `<snapshot>/_partials`. A second write of the same snapshot path is the duplicate case: the later folder wins, and the report holds one warning that names both sides.
  timestamp: 2026-09-15T16:52:29.603173+00:00
- actor: claude-code
  id: 01m2jzr4xx3bb5zpf2v2mz0t4c
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsSkills/Marketplace/SnapshotWriter.swift (new), Tests/FoundationModelsSkillsTests/SnapshotWriterTests.swift (new). `swift build --build-tests`: 0 errors, 0 warnings. `swift test --filter SnapshotWriterTests`: 13 tests, 13 passed. `swift test`: 592 tests in 42 suites, all passed.
    - next: /review

    Note on the test-driven steps. The tests came first and failed because the types were not there. One test then failed for a true reason: with `maxFiles: 1` the writer permits the first file and throws at the second one. The test named the first file. The test now names the second file, and the writer is unchanged.
  timestamp: 2026-09-15T16:52:35.901527+00:00
- actor: claude-code
  id: 01m2k001k16nyh4e6yzb814jq0
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 3e8f8f6); 0 findings, 0 confirmed, 0 refuted, 7 validator runs; all prior checklist items are checked
    - next: move the task to done
  timestamp: 2026-09-15T16:56:54.625030+00:00
- actor: claude-code
  id: 01m2k00fyypa3ve9crm8dzv0s5
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files (Marketplace/SnapshotWriter.swift, Tests/FoundationModelsSkillsTests/SnapshotWriterTests.swift)
    - test: green — swift build --build-tests 0 warnings; swift test x2, 592 passed each run, 0 failed, 0 skipped
    - commit: 3e8f8f6 feat(marketplace): add the snapshot writer for the layer root
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-15T16:57:09.342393+00:00
depends_on:
- 01M2H0QNGBQDQWBB3H1NSGYGDN
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: done
position_ordinal: d180
title: Write a validated flat snapshot of the selected skills (SnapshotWriter)
---
## What

marketplace.md §7.3 steps 3–4 and §4.2. Turn a resolved catalog into one flat layer folder: `<skill>/…` for each selected skill, plus `_partials/`. The input is any `CatalogFileSource`, so the same code works for a local folder and for a libgit2 commit tree.

Create `Sources/FoundationModelsSkills/Marketplace/SnapshotWriter.swift`:
- `SnapshotWriter.write(_ catalog: ResolvedCatalog, from: any CatalogFileSource, to temporaryDirectory: URL, limits: SnapshotLimits) throws -> SnapshotReport`.
- Copy each selected skill folder recursively to `temporaryDirectory/<skill name>/`. Copy `_partials/` from each folder that holds selected skills. If two such folders give the same partial name, record a diagnostic; the later one wins.
- Keep the execute bit: a `.file(isExecutable: true)` entry is written with mode `0o755`.
- Reject, and throw `SnapshotError` naming the path: an entry name that contains `..` or `/`; a `.symlink` whose target resolves outside its skill folder; a `.submodule` entry; a total byte count or file count above `SnapshotLimits` (`maxBytes`, `maxFiles`; these are host policy values, not times). On any throw, delete `temporaryDirectory`.
- A file whose text starts with `version https://git-lfs.github.com/spec/v1` is an LFS pointer. Write it, and add a diagnostic to `SnapshotReport`.

- [x] `SnapshotLimits`, `SnapshotError`, `SnapshotReport`
- [x] Recursive copy with the execute bit and `_partials/`
- [x] Validation rules with cleanup on failure
- [x] LFS pointer diagnostic

## Acceptance Criteria
- [x] A snapshot of a fixture catalog is a folder that `SkillsRegistry(roots: [snapshot])` loads with the expected skill ids
- [x] Each rejection case throws, and leaves no temporary folder behind
- [x] An executable script keeps mode `0o755`

## Tests
- [x] `Tests/FoundationModelsSkillsTests/SnapshotWriterTests.swift`: a happy path over `LocalCatalogFileSource` (the registry loads the result); selection keeps only the chosen skills; `_partials/` is copied and a duplicate partial gives a diagnostic; an in-memory fake `CatalogFileSource` gives a `..` name, an escaping symlink, and a submodule (each rejected, and the folder is removed); `maxFiles` and `maxBytes` overflow; the execute bit; an LFS pointer diagnostic
- [x] Run `swift test --filter SnapshotWriterTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace