---
assignees:
- claude-code
depends_on:
- 01M2H0QNGBQDQWBB3H1NSGYGDN
- 01M2H0R2AFRD111HR47N3YVH8R
position_column: todo
position_ordinal: '8680'
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

- [ ] `SnapshotLimits`, `SnapshotError`, `SnapshotReport`
- [ ] Recursive copy with the execute bit and `_partials/`
- [ ] Validation rules with cleanup on failure
- [ ] LFS pointer diagnostic

## Acceptance Criteria
- [ ] A snapshot of a fixture catalog is a folder that `SkillsRegistry(roots: [snapshot])` loads with the expected skill ids
- [ ] Each rejection case throws, and leaves no temporary folder behind
- [ ] An executable script keeps mode `0o755`

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SnapshotWriterTests.swift`: a happy path over `LocalCatalogFileSource` (the registry loads the result); selection keeps only the chosen skills; `_partials/` is copied and a duplicate partial gives a diagnostic; an in-memory fake `CatalogFileSource` gives a `..` name, an escaping symlink, and a submodule (each rejected, and the folder is removed); `maxFiles` and `maxBytes` overflow; the execute bit; an LFS pointer diagnostic
- [ ] Run `swift test --filter SnapshotWriterTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace