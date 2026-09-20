---
comments:
- actor: claude-code
  id: 01m2zm9jbep2e9nd6ht0bs91mv
  text: |-
    ### Research — the upstream initializer is written but not published

    Step 1 of the card says to check the upstream first. I did this.

    `swift package update FoundationModelsExtras` gives "Everything is already up-to-date". `Package.resolved` did not change. `git status` shows no change to `Package.resolved`.

    The resolved revision is `1c150fb`. The file
    `.build/checkouts/FoundationModelsExtras/Sources/FoundationModelsExtras/DotfolderStack.swift`
    at that revision has two public initializers only:
    `Layer.init(source:root:)` and `DotfolderStack.init(name:workingDirectory:defaultsDirectory:userDirectory:environment:)`.
    A search for `init(layers` in the full checkout of Extras gives no result.
    Thus the public `DotfolderStack.init(layers:)` is not there.

    The cause is exact. The Extras card `^00nmjzg` is done in the local clone at
    `/Users/wballard/github/swissarmyhammer/FoundationModelsExtras`. Commit `62bf1aa`
    ("feat(dotfolder-stack): add init(layers:) and isExecutable(_:)") adds
    `public init(layers: [Layer])` at line 180 of `DotfolderStack.swift`.
    But `git status -sb` in that clone gives `## main...origin/main [ahead 1]`, and
    `origin/main` is still `1c150fb`. The commit is local only.

    This package names Extras as `.package(url: ..., branch: "main")` of the remote.
    Thus SwiftPM resolves `origin/main`, and the new initializer is out of reach until
    a person pushes the commit.

    The last comment of the Extras card states this: "the push criterion stays with the
    user after the loop". Criterion 6 of that card, "The work is committed and pushed to
    `main` of this repository", is thus not complete.

    ### One more call site than the card names

    The card names three callers. There are four now:

    - `Sources/FoundationModelsSkills/Discovery/SkillDiscovery.swift`
    - `Sources/FoundationModelsSkills/Render/StencilPass.swift`
    - `Sources/FoundationModelsSkills/Resources/SkillOverlay.swift`
    - `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift` — `DotfolderStack(layers: layers)` as the `base` of a `FrontmatterDocumentStack`. The card `^dzcmb4z` added this one after this card was written.

    All four use the same one-label form `DotfolderStack(layers:)`, thus all four bind to
    the public initializer with no change of text, as the card states.

    ### No code changed

    I made no change to `Sources/`, to the tests or to `Package.resolved`. The shim
    `Sources/FoundationModelsSkills/Discovery/DotfolderStack+Layers.swift` is still there.
    To delete it now would stop the build, because the resolved Extras revision gives no
    other initializer that takes the layers.
  timestamp: 2026-09-20T14:42:31.406386+00:00
- actor: claude-code
  id: 01m2zmag7rq6t6407tr6pvbpcn
  text: |-
    ### What Extras must give, and the card for the Extras board

    Extras must give one thing, and one thing only: the commit `62bf1aa` of
    `/Users/wballard/github/swissarmyhammer/FoundationModelsExtras` must be on
    `origin/main`. The code is written and the tests are green in that clone. It is not
    published.

    I did not write this card on the Extras board. Two reasons:

    1. The instruction for this step says not to edit the Extras repository, and a card
       of that board is a file in `.kanban/` of that repository.
    2. The kanban tool cannot reach that board from this session. I called
       `get board` with `path` set to the Extras clone, and the tool gave the
       `FoundationModelsSkills` board. The `cross-repo` tag of this board states the same
       rule: "Work in a sibling repository; run from a session opened in that repository".

    Here is the text of the card. A person opens a session in
    `/Users/wballard/github/swissarmyhammer/FoundationModelsExtras` and adds it there.

    ---

    **Title:** Push `main` so the consumers can resolve `DotfolderStack.init(layers:)`

    **Description:**

    ## What

    Commit `62bf1aa` ("feat(dotfolder-stack): add init(layers:) and isExecutable(_:)")
    is on local `main` only. `git status -sb` gives `## main...origin/main [ahead 1]`,
    and `origin/main` is `1c150fb`.

    The card `^00nmjzg` is in `done`, but its criterion "The work is committed and pushed
    to `main` of this repository" is not met. Its last comment says "the push criterion
    stays with the user after the loop".

    `FoundationModelsSkills` names this package as `.package(url: ..., branch: "main")`
    of the remote. Thus `swift package update FoundationModelsExtras` there gives
    "Everything is already up-to-date" and resolves `1c150fb`, which has no
    `public init(layers:)` and no `isExecutable(_:)`.

    Four cards of the `FoundationModelsSkills` board wait for this push:
    `^whth0pd` (delete the `DotfolderStack(layers:)` shim), `^214wnyr` (take the execute
    bit from the stack), `^69fpbra` (the render move) and `^9v5b1w4` (the watcher move).

    ## Acceptance Criteria

    - [ ] `git push origin main` completes, and `origin/main` names `62bf1aa`.
    - [ ] The two uncommitted kanban files of `^00nmjzg` are committed with it or before it.
    - [ ] `swift package update FoundationModelsExtras` in `FoundationModelsSkills`
          moves `Package.resolved` to the new revision.
    - [ ] `grep "public init(layers"` in the new checkout of Extras gives a result.

    #cross-repo #loading-boundary

    ---

    ### The order of the work after the push

    A person pushes. Then `^whth0pd` starts again and finishes in one pass: it runs
    `swift package update FoundationModelsExtras`, deletes
    `Sources/FoundationModelsSkills/Discovery/DotfolderStack+Layers.swift`, and leaves
    the four call sites as they are. The card `^214wnyr` then takes the execute bit.
  timestamp: 2026-09-20T14:43:02.008363+00:00
- actor: claude-code
  id: 01m2zmbdc7yy0pkcj31rc5pa3v
  text: |-
    ### implement — stuck
    - evidence: 0 source files changed. `swift package update FoundationModelsExtras` gives "Everything is already up-to-date"; the resolved revision stays `1c150fb`, which has no `public DotfolderStack.init(layers:)` (a search for `init(layers` in the Extras checkout gives 0 results). `swift build --build-tests` gives "Build complete!" with 0 warnings. `git status` shows 4 changed files, all of them kanban records.
    - blocker: the Extras commit `62bf1aa` that adds the public initializer is on the local `main` of `/Users/wballard/github/swissarmyhammer/FoundationModelsExtras` only. `main` is 1 commit ahead of `origin/main`. This package resolves the remote branch `main`, thus the initializer is out of reach.
    - next: a person pushes `origin/main` in the Extras repository. Then this card starts again, runs the update, and deletes `Sources/FoundationModelsSkills/Discovery/DotfolderStack+Layers.swift`. The four call sites need no change of text.
    - note: the card says to leave the task in To Do when the upstream check fails. The instruction of this step says to leave it in `doing`. The task is in `doing`.
  timestamp: 2026-09-20T14:43:31.847260+00:00
- actor: wballard
  id: 01m2zmcygzk6zg61yt6wpqk26e
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — the Extras commit 62bf1aa (init(layers:)) is on local main only; origin/main is 1c150fb, and this package resolves the remote branch
    - test: not run
    - commit: none
    - review: not run
    - next: push main of FoundationModelsExtras, then swift package update here and do this card. I did not push that repository, because a card is in doing there now.
  timestamp: 2026-09-20T14:44:22.175659+00:00
- actor: wballard
  id: 01m30b9mp64qmb05mwg47nkmq6
  text: 'Unblocked on 2026-09-20. The Extras commit 62bf1aa (public DotfolderStack.init(layers:)) is on origin/main now, and Package.resolved here pins cf4be5c, which holds it. Start again from step 1. One correction of the card text: the two initializers with one signature do NOT stop the build. `swift build` of this package is green with the shim in place against cf4be5c, because the compiler prefers the initializer of this module. Thus this card is a plain cleanup: delete Discovery/DotfolderStack+Layers.swift, and check that the three callers and the dotfolder_name test still pass with the public initializer. No other card waits for this one, except the guard.'
  timestamp: 2026-09-20T21:24:31.046596+00:00
- actor: claude-code
  id: 01m30b9ws578jtpaj1mjqkgapq
  text: |-
    ### Research — the upstream block is gone

    Step 1 of the card, run again:

    - `swift package update FoundationModelsExtras` gives "Everything is already up-to-date". `Package.resolved` pins `cf4be5cba0862c0326183196db80754116cf753c` for `foundationmodelsextras`, and `git status` shows no change to that file. Thus the pin moved before this session, and criterion 2 of the card is already met.
    - The checkout at `.build/checkouts/FoundationModelsExtras` is at `cf4be5c`, and line 180 of its `Sources/FoundationModelsExtras/DotfolderStack.swift` reads `public init(layers: [Layer]) {`. The body is `self.layers = layers` and nothing else.
    - The doc of that initializer states the `dotfolder_name` rule of this package word for word: "The list may hold more than one layer of one source. A stack with two `.project` layers takes its `dotfolder_name` from the highest of them." Thus the test `wellKnownValuesCurrentDerivesDotfolderNameFromTheHighestPrecedenceProjectLayer` of `StencilPassTests.swift` keeps its expected values.

    ### Four call sites, not three

    `grep "DotfolderStack(layers" Sources Tests` gives four, all in `Sources/`, all in the one-label form:

    - `Discovery/SkillDiscovery.swift`
    - `Render/StencilPass.swift`
    - `Resources/SkillOverlay.swift`
    - `Registry/SkillsRegistry.swift`

    No test names the initializer. Thus each call site binds to the public initializer with no change of text, as the card states.

    ### The shape of the new guard test

    `Tests/FoundationModelsSkillsTests/SwiftSourceScan.swift` already walks the Swift files of a directory, and two suites use it: `NoGitProcessTests` and `NoFrontmatterSplitTests`. The new source-scan test follows that pattern and keeps no copy of the walk.
  timestamp: 2026-09-20T21:24:39.333371+00:00
- actor: claude-code
  id: 01m30bsqhvbq9e000gjg6crwzf
  text: |
    ### The TDD cycle, and what the shim was doing

    RED: with the shim in place, `swift test --filter NoDotfolderStackExtensionTests` gave
    `noFileUnderSourcesExtendsTheLayerStack()` failed, and the message named the cause
    exactly: `Sources/FoundationModelsSkills/Discovery/DotfolderStack+Layers.swift:4`.
    The two line tests passed in both states, as they read text only.

    GREEN: with the shim deleted, the three cases of the suite pass.

    One discovery about the shim. The card expects an ambiguous use error from two
    initializers of one signature. There is none. Swift gives a declaration of the
    module itself precedence over a declaration the module imports, thus the internal
    shim silently shadowed the public initializer of Extras, and the build stayed
    green. The defect was thus a quiet one: each call site took the shim, and the
    shim built a stack over a placeholder name and the root directory before it
    replaced the layers. Now each call site takes the public initializer, which
    assigns the layers and does nothing else.

    ### A second collision came with the same Extras revision

    `swift build --build-tests` was red before this card touched one file, and the
    cause was not the initializer.

    `FoundationModelsExtras` at `cf4be5c` declares a `QuarantinedText` of its own, and
    `Sources/FoundationModelsSkills/SeamReexports.swift` holds
    `@_exported import FoundationModelsExtras`. Thus every consumer of this package
    sees two types of that name, and the bare name is ambiguous in a type position.
    One file failed:
    `Tests/FoundationModelsSkillsTests/RenderPipelineTests.swift`, at the two type
    positions of `RecordingPass.render`. The other four test files that name the type
    build, because each one names it in an expression position, where the
    initializer `QuarantinedText(original:)` decides.

    Module qualification cannot answer it: `Sources/FoundationModelsSkills/FoundationModelsSkills.swift`
    declares `public enum FoundationModelsSkills {}`, thus
    `FoundationModelsSkills.QuarantinedText` reads the namespace enum and gives
    "'QuarantinedText' is not a member type of enum
    'FoundationModelsSkills.FoundationModelsSkills'". I measured that.

    The repair is one line in that one test file:
    `import struct FoundationModelsSkills.QuarantinedText`. A scoped import takes
    precedence over a whole-module import, thus the file reads the type of this
    package. A comment above the line states why the line is there, and names the
    card `^69fpbra` ("Render: give Stencil and the quarantine to Extras"), which
    deletes the local type and this line with it.

    This is a change outside the text of this card. I made it because criterion 3 of
    this card asks for a green `swift build --build-tests` and a green `swift test`,
    and no test of this package could run while the target did not compile. The two
    `QuarantinedText` types are not equal (239 lines here, 247 in Extras, and Extras
    adds a builder type), thus a merge of the two is real work and stays with
    `^69fpbra`.
  timestamp: 2026-09-20T21:33:18.267419+00:00
- actor: claude-code
  id: 01m30bt0424xdawg0pqxhk09wt
  text: |-
    ### implement — changed
    - evidence: 3 files — deleted `Sources/FoundationModelsSkills/Discovery/DotfolderStack+Layers.swift`; added `Tests/FoundationModelsSkillsTests/NoDotfolderStackExtensionTests.swift` (3 cases); changed `Tests/FoundationModelsSkillsTests/RenderPipelineTests.swift` (one scoped import). `swift package update FoundationModelsExtras`: "Everything is already up-to-date", `Package.resolved` pins `cf4be5c`, which holds `public init(layers: [Layer])` at line 180. The four call sites (`SkillDiscovery.swift`, `StencilPass.swift`, `SkillOverlay.swift`, `SkillsRegistry.swift`) take the public initializer with no change of text. `grep "extension DotfolderStack" Sources/` gives 0. `swift build --build-tests` after `touch` of every Swift file of `Sources/` and `Tests/`: "Build complete!", 0 warnings. `swift test`: 812 tests in 67 suites passed, 0 failures. `wellKnownValuesCurrentDerivesDotfolderNameFromTheHighestPrecedenceProjectLayer` passes with no change of its expected values.
    - next: `/review`. The reviewer decides the one line outside this card, `import struct FoundationModelsSkills.QuarantinedText` in `RenderPipelineTests.swift`. The comment above it states the reason, and the card `^69fpbra` deletes it.
  timestamp: 2026-09-20T21:33:27.042933+00:00
- actor: claude-code
  id: 01m30byej8vw642xtz3dt57k5v
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` (after a full touch of every file in `Sources/` and `Tests/`, to force a clean recompile) — \"Build complete!\", 0 warnings. `swift test` — Test run with 812 tests in 67 suites passed, 0 failures, 0 skipped.
    - checks: `grep \"extension DotfolderStack\" Sources/` gives 0 matches. `Sources/FoundationModelsSkills/Discovery/DotfolderStack+Layers.swift` does not exist. `Tests/FoundationModelsSkillsTests/NoDotfolderStackExtensionTests.swift` (3 cases) and the scoped-import fix in `RenderPipelineTests.swift` (`import struct FoundationModelsSkills.QuarantinedText`, needed for the Extras `QuarantinedText` name clash from `cf4be5c`) both pass in the full run.
    - no commit made, per instruction.
    - next: `/review`.
  timestamp: 2026-09-20T21:35:52.904223+00:00
position_column: doing
position_ordinal: '80'
title: Delete the DotfolderStack(layers:) shim when Extras gives the public initializer
---
## What

`Sources/FoundationModelsSkills/Discovery/DotfolderStack+Layers.swift` is a shim: `extension DotfolderStack { internal init(layers: [Layer]) }`. It exists because `FoundationModelsExtras` had no such initializer. The Extras card `^00nmjzg` on the `FoundationModelsExtras` board adds `public init(layers: [Layer])` with the **same signature**. From the moment this package resolves that revision, each call site sees two initializers with one signature, and the build can stop with an ambiguous use error. Thus this card must land with the first package update that pulls that revision.

Each later card of this board that runs `swift package update FoundationModelsExtras` depends on this card. The card ^sg5cf2n is ready before this one can start, thus it carries the same instruction as a fallback: if its update pulls the public initializer, it deletes the shim in its own commit, and this card then has only its check to do.

1. **Check the upstream first.** Run `swift package update FoundationModelsExtras`. If the resolved revision has no public `DotfolderStack.init(layers:)`, stop, write a comment on this card, and leave it in To Do.
2. Delete `Discovery/DotfolderStack+Layers.swift`. The three callers (`Discovery/SkillDiscovery.swift`, `Render/StencilPass.swift`, `Resources/SkillOverlay.swift`) bind to the public initializer with no change of text.
3. `dotfolder_name`: the public initializer keeps the rule of this package, the highest-precedence `.project` layer (that Extras card states it). Check it with the test that is there now.

## Acceptance Criteria

- [x] `Discovery/DotfolderStack+Layers.swift` does not exist, and no file of `Sources/FoundationModelsSkills/` declares an initializer on `DotfolderStack`.
- [x] `Package.resolved` pins an Extras revision that holds the public `DotfolderStack.init(layers:)`.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/SkillDiscoveryTests.swift`, `SkillOverlayTests.swift` and `StencilPassTests.swift`: each case passes with no change of its expected values; the case "derives from the highest-precedence project layer" is one of them.
- [x] A source scan test: no file under `Sources/` holds the text `extension DotfolderStack`.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills #blocked-upstream
