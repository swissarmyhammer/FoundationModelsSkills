---
depends_on:
- 01M2X2BXEPERA9BG5CGCW1Z0Q7
position_column: todo
position_ordinal: '8280'
title: Resolve a skill file across the contributing directories
---
## What

`PathConfinement` (`Sources/FoundationModelsSkills/Resources/PathConfinement.swift:21`) resolves a skill-relative path against **one** skill directory. With the combined view a skill has more than one layer directory, thus a legal file can be in a lower layer.

1. Add `resolvedURL(relativePath:in directories: [URL]) -> URL?`. It reads the directories from the highest precedence to the lowest, and it gives the first copy that exists and that is inside that directory. The rule of each single directory does not change: symbolic links are resolved, and a path that leaves its directory is denied.
2. Keep the one-directory form. Write it on top of the list form, so that the two can never differ.
3. Add an internal type that each resource operation uses, for example `SkillOverlay` in `Sources/FoundationModelsSkills/Resources/`:
   - `resolve(_ relativePath: String) -> (url: URL, directoryIndex: Int)?` — the winning copy and which contributing directory gave it. The index lets a caller find the grants of that layer.
   - `entries() -> [String: URL]` — the union of the paths of the skill, each with its winning copy. It uses `DotfolderStack.tree(_:)`; it does not walk the directories itself.
4. The corrective text of a denied path does not change.

## Acceptance Criteria

- [ ] A path that only a lower layer holds resolves, and the resolved URL is in that lower directory.
- [ ] A path that two layers hold resolves to the copy of the higher layer.
- [ ] A path that leaves each of the directories is denied, with the text that is there now.
- [ ] The one-directory form gives the same answer as a list of one directory.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/PathConfinementTests.swift`: two directories; a path that only the lower one holds; the result names the lower copy.
- [ ] Same file: the same path in both directories gives the higher copy.
- [ ] Same file: `../x`, `/etc/passwd` and a symbolic link that points out of each directory are all denied.
- [ ] `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift` (new): `entries()` gives the union, and `resolve` names the directory that won.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#dotfolder-overlay #skills