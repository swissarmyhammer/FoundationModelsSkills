---
comments:
- actor: claude-code
  id: 01m2xq6d8pkd28q9n85ksktj85
  text: |
    ### Research

    Read before the first edit:

    - `Sources/FoundationModelsSkills/Resources/PathConfinement.swift` — the one-directory form gives a URL for a path that does not exist, as long as the path stays in the directory. `ReadResource` needs that: it then gives the "could not be read" text, and not the denied text. Card ^1z0q7's sibling card (done) made that behavior. Thus the list form must keep it.
    - `.build/checkouts/FoundationModelsExtras/Sources/FoundationModelsExtras/DotfolderStack.swift` and `DotfolderStacking.swift`. The real API: `tree(_ subdirectory: String? = nil) -> [String: Located<String>]`, `childDirectories(of:)`, `layerDirectories(_:)`, `locate(_:)`, `item(at:)`. `Located` carries `url`, `layer` and `value`.
    - `DotfolderStack` states **no** public initializer that takes its layers. This package makes one: `Sources/FoundationModelsSkills/Discovery/DotfolderStack+Layers.swift` gives the internal `init(layers:)`. `SkillOverlay` uses it.
    - `Tests/FoundationModelsSkillsTests/WatcherTestSupport.swift` already gives `makeTempDirectory()`. The new tests use it, and make no temporary directory of their own.

    Two points where the card text and the code differ. The code wins:

    1. The card says `DotfolderStack.tree(_:)`. The signature is `tree(_ subdirectory: String? = nil)`, and its value is `Located<String>`: the **text** of the winning copy. A winning file whose bytes are not UTF-8 text is **not** in the view. Thus `entries()` leaves out a file that is not text, for example a PNG under `assets/`. `list resource` must give such a file. This is a new task, not a fault of this card.
    2. The card says the list form gives "the first copy that exists". Alone, that rule would break `ReadResource`. The rule this card writes is: give the first copy that exists; when no directory holds the path, give the resolved location in the highest directory that confines it. A list of one directory then gives exactly what the one-directory form gives today, which is the acceptance criterion.
  timestamp: 2026-09-19T20:54:44.758420+00:00
- actor: claude-code
  id: 01m2xqfj99jdvf6xq71nk55dbz
  text: |
    ### implement — changed

    - evidence: 4 files. `Sources/FoundationModelsSkills/Resources/PathConfinement.swift` (changed), `Sources/FoundationModelsSkills/Resources/SkillOverlay.swift` (new), `Tests/FoundationModelsSkillsTests/PathConfinementTests.swift` (new), `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift` (new), `Tests/FoundationModelsSkillsTests/LayerFixtureSupport.swift` (new). `swift build --build-tests`: 0 errors, 0 warnings. `swift test`: 783 tests in 63 suites, 0 failures. The 14 new tests are 8 in `PathConfinementTests` and 6 in `SkillOverlayTests`.
    - TDD: the two test files were written first and the build failed with "cannot find 'SkillOverlay' in scope" and no list form of `resolvedURL`. The tests pass after the two source files.
    - The shape of the list form: collect the confined location of the path in each directory, highest precedence first; give the first of them that exists; when none exists, give the first confined location. A list of one directory is then the one-directory form, letter for letter, and the test `theOneDirectoryFormGivesTheSameAnswerAsAListOfOneDirectory` holds the three path shapes.
    - `PathConfinement.winningCopy(relativePath:in:)` is the one function that decides. `resolvedURL(relativePath:in directories:)` gives its URL, `resolvedURL(relativePath:in skillDirectory:)` gives a list of one, and `SkillOverlay.resolve(_:)` gives its index. Thus the three can never differ.
    - The four callers of the one-directory form (`ListResource`, `ReadResource`, `RunScript`, `LocalCatalogFileSource`) are not changed, and their suites are green.
    - `SkillOverlay` has no caller in the sources yet: cards ^9jt4sq and ^hmmnga put the resource operations on it. The tests call it, thus `periphery` reads it as live.
    - New tasks: ^txjvhav (`entries()` leaves out a file that is not UTF-8 text, because `tree(_:)` reads the text; it blocks ^9jt4sq) and ^dkysgr9 (`SkillDiscoveryTests` keeps private copies of three fixture helpers that `LayerFixtureSupport` now shares).
    - next: `/review`.
  timestamp: 2026-09-19T20:59:44.809667+00:00
- actor: claude-code
  id: 01m2xqjnz325pz7e6sd8yp3yp0
  text: |-
    ### test — green
    - evidence: swift build --build-tests exit 0, no warnings; swift test — Test run with 783 tests in 63 suites passed after 10.140 seconds, 0 failed, 0 warnings, 0 skipped
    - next: ready for review
  timestamp: 2026-09-19T21:01:26.883406+00:00
depends_on:
- 01M2X2BXEPERA9BG5CGCW1Z0Q7
position_column: doing
position_ordinal: '80'
title: Resolve a skill file across the contributing directories
---
## What

`PathConfinement` (`Sources/FoundationModelsSkills/Resources/PathConfinement.swift`) resolved a skill-relative path against **one** skill directory. With the combined view a skill has more than one layer directory, thus a legal file can be in a lower layer.

1. Add `resolvedURL(relativePath:in directories: [URL]) -> URL?`. It reads the directories from the highest precedence to the lowest, and it gives the first copy that exists and that is inside that directory. The rule of each single directory does not change: symbolic links are resolved, and a path that leaves its directory is denied.
2. Keep the one-directory form. Write it on top of the list form, so that the two can never differ.
3. Add an internal type that each resource operation uses, `SkillOverlay` in `Sources/FoundationModelsSkills/Resources/`:
   - `resolve(_ relativePath: String) -> (url: URL, directoryIndex: Int)?` — the winning copy and which contributing directory gave it. The index lets a caller find the grants of that layer.
   - `entries() -> [String: URL]` — the union of the paths of the skill, each with its winning copy. It uses `DotfolderStack.tree(_:)`; it does not walk the directories itself.
4. The corrective text of a denied path does not change.

## Where the card text and the code differ

The code wins, and here is how:

1. **The card said "the first copy that exists", full stop.** That rule alone would break `ReadResource`: a path that no layer holds would be denied, and the model would read "the path is not accessible" for a file name that is simply wrong. Card ^dzxvms made the opposite behavior on purpose. The rule as written: give the first copy that exists; when **no** directory holds the path, give the resolved location in the highest directory that confines it. A list of one directory then gives exactly what the one-directory form gave before, which is acceptance criterion 4.
2. **The order of the list.** `PathConfinement` takes its directories **highest precedence first**, because it reads them in that order. `SkillOverlay` holds its directories **lowest precedence first**, the order of `DiscoveredSkill.contributingDirectories`, thus the `directoryIndex` of `resolve(_:)` is the position of that contributing directory. `SkillOverlay` turns the one order into the other, and no caller does that arithmetic.
3. **`tree(_:)` gives the text of a file, not its bytes.** `DotfolderStack.tree(_:)` drops a winning copy that is not UTF-8 text, thus `entries()` leaves out a file of bytes, for example a PNG under `assets/`. `list resource` must give such a file. New task ^txjvhav holds that work; it blocks ^9jt4sq.
4. **The fixture helpers of the new tests.** `Tests/FoundationModelsSkillsTests/LayerFixtureSupport.swift` is new, and `SkillDiscoveryTests` keeps private copies of three of its helpers. Those copies were there before this card. New task ^dkysgr9 holds that cleanup.

## Acceptance Criteria

- [x] A path that only a lower layer holds resolves, and the resolved URL is in that lower directory.
- [x] A path that two layers hold resolves to the copy of the higher layer.
- [x] A path that leaves each of the directories is denied, with the text that is there now. `deniedMessage(path:)` is not changed, and `ReadResourceTests` and `RunScriptTests` still hold its words.
- [x] The one-directory form gives the same answer as a list of one directory.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/PathConfinementTests.swift`: two directories; a path that only the lower one holds; the result names the lower copy.
- [x] Same file: the same path in both directories gives the higher copy.
- [x] Same file: `../outside.md`, `/etc/passwd`, `~/secrets.md`, the empty path, and a symbolic link that points out of each directory are all denied.
- [x] `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift` (new): `entries()` gives the union, and `resolve` names the directory that won.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#dotfolder-overlay #skills