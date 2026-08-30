---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1acth5zgg6m90jega17z6w7
  text: |-
    Research notes for the next agent.

    - `SkillsToolAssembly.swift` gives three `async throws` overloads: `make(registry:session:embedder:followReloads:visibilityPredicate:)` with a `@Sendable (String) -> any AgentSession` closure, the same with a live `any AgentSession`, and `make(registry:embedder:followReloads:visibilityPredicate:)` with no session (mode `.retrieval`). `followReloads` defaults to `true` in all three.
    - The card says `ChatMode.swift` and `WatchMode.swift` only call `SkillsDemoAssembly.makeContext(registry:)`. That is not complete: `WatchMode.run()` also read `context.searchAgent` and pumped `registry.onReload -> searchAgent.update(items:)` by hand. `OperationTool` does not expose its context, thus the factory cannot give a context back. `WatchMode` now drops the hand pump -- the factory follows the reloads -- and keeps its own `onReload` subscription only to print. `SkillsRegistry.onReload` is a multicast broadcaster (`ReloadCoordinator.subscribe()`), thus the two subscriptions do not steal each other's events. Manual run of `--watch` plus a `touch` on a fixture file shows one reload event printed.
    - `SkillsDemoAssembly.makeContext(registry:)` is now `makeTool(registry:) async throws -> OperationTool<SkillsToolContext>`. It gives the factory no session, thus the demo keeps its old retrieval-only behavior.
    - `docs/operations.md:33` says "`SkillsTool.make` sets it to `isModelVisible` as the default." Each new overload defaults `visibilityPredicate` to `{ $0.isModelVisible }`, thus the line stays correct. No change made.
    - `ReadmeExampleTests.swift` imports only `FoundationModels`, `FoundationModelsSkills`, and `Testing`. Two constraints come from that short list: `URL` cannot be named, thus the three layer-root URLs come from `FixtureLibrary.url(relativePath:)`; and there is no `JSONDecoder`, thus `rankedIDs(in:)` reads the ids out of the answer text with `firstRange(of:)`.
    - The README block gives the factory a real `LanguageModelSession` closure. A search through that tool would call the on-device model, thus the block case asserts only that the tool and the session are built. The search case uses the no-session form the new README paragraph names, thus every case stays GPU-free.
    - A script compared the README fenced block (minus its two import lines) with the block held in the test, after dedent: the two are equal character for character.
  timestamp: 2026-08-30T22:32:13.759418+00:00
- actor: claude-code
  id: 01m1ad0tycxd2e83hkrz3cqaay
  text: |-
    ### implement — changed
    - evidence: 5 files. New `Tests/FoundationModelsSkillsTests/ReadmeExampleTests.swift`. Changed `README.md`, `Examples/skills-demo/SkillsDemoAssembly.swift`, `Examples/skills-demo/ChatMode.swift`, `Examples/skills-demo/WatchMode.swift`. `docs/operations.md` read and left as it is. Commands: `swift build` (clean, 0 warnings), `swift build --build-tests` (clean, 0 warnings), `swift test` -> 405 tests in 32 suites passed, 0 failures. `swift run skills-demo --chat` with a live model -> `[OK]` for `search skill` and `[OK]` for `use skill`. `--watch` run by hand with a `touch` on a fixture file -> one reload event printed, and the fixture stays unchanged in git.
    - RED step: both assertions in the new suite were shown to fail. A mutation of `fusedToolName` to `"skillz"` and `bestMatchSkillID` to `"deploy"` gave 3 failures, then the mutation was reverted. The two `SkillsTool.make` overloads the README now shows already existed (`^mx1rkqx`), thus the new suite could not start red on a missing API. It starts red only against a wrong README.
    - A script compares the README fenced block, minus its two import lines, with the block held in the test, after dedent. The two are equal character for character.
    - next: `/review`.
  timestamp: 2026-08-30T22:35:40.364111+00:00
- actor: claude-code
  id: 01m1adaprgq96gv7fhhce3qmvt
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (c6b5805) -> 0 findings, 0 confirmed, 0 refuted, 7 validator runs attempted, 0 failed, 0 skipped. 4 files reviewed. `README.md` matched no validator, thus the engine did not read it.
    - probes on the three load-bearing claims, because the engine covers no Markdown:
      - README block vs the test copy: `README.md:19-39` and `ReadmeExampleTests.swift:55-75` are equal line for line, all 21 lines. The AC asks that the test hold the exact code and compile. Both hold.
      - `--watch` reloads: `SkillsRegistry.onReload` is a computed property that answers `broadcaster.subscribe()`, thus each read gives an independent stream. The factory takes its own subscription before it reads the seed catalog and holds a `SkillsReloadFollower`, whose task runs `agent.update(items:)` for each publication and lives as long as the tool. `WatchMode.run()` holds the tool across the loop with `withExtendedLifetime`. Reloads reach the searcher, and the print subscription steals no event.
      - GPU-free: the block case makes a session but sends no prompt, and the selection closure runs only on a search. The search case uses the no-session `SkillsTool.make(registry:)` with `mode: .retrieval` and no embedder. No case needs an on-device model.
    - no document names `import FoundationModelsMetadataRegistry`.
    - open point for a person, not a finding: no test asserts that the two copies of the block stay equal. The equality was shown by a one-time script. If the README changes and the test does not, every test still passes. The Tests section asks only for a copy that compiles, thus this does not fail the card.
    - next: none. Task moved to done.
  timestamp: 2026-08-30T22:41:03.760650+00:00
- actor: claude-code
  id: 01m1adbhq22h9mesw5v2x6wr1k
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files (README.md, ReadmeExampleTests.swift, SkillsDemoAssembly.swift, ChatMode.swift, WatchMode.swift)
    - test: green — swift test, 405 tests in 32 suites, 0 failures, 0 warnings; `swift run skills-demo --chat` 2 of 2 OK on a live model
    - commit: c6b5805
    - review: clean — 0 findings, 7 validators attempted
    - next: task is in done

    The reviewer verified the three risky claims by hand, because no validator reads Markdown: the README block and the test copy are equal line for line; `SkillsRegistry.onReload` really is a multicast broadcaster, thus dropping WatchMode's hand pump did not break `--watch`; and both new cases stay GPU-free.

    It also found a residual gap that is outside this card's written criteria: nothing *asserts* that the README block and the test copy stay equal, thus a later edit to one alone would not fail the suite. Filed as `^y61tx8e`.
  timestamp: 2026-08-30T22:41:31.362161+00:00
- actor: claude-code
  id: 01m1adc2g1qyk0x8q8sapjn7bm
  text: 'Correction to the comment above: the drift-guard task is `^n49hex3`, not `^y61tx8e`. I wrote the id before the board assigned one.'
  timestamp: 2026-08-30T22:41:48.545627+00:00
depends_on:
- 01M199ZVM11XKMQ5WWSET0AR2E
- 01M19AQSGXENFA8W70RPWK3XYZ
position_column: done
position_ordinal: c380
title: Show the just-a-tool path in the README and the demo
---
## What

The README usage block and `Examples/skills-demo` both show the hand assembly of `MetadataSearcher` -> `SkillSearchAgent` -> `SkillsToolContext`, and both need `import FoundationModelsMetadataRegistry`. Show the one-call path instead.

Write every text in this task in ASD-STE100 Simplified Technical English.

### README

Replace the usage block in `README.md:15-38`. Keep the `DotfolderStack` construction — the block must be complete code, thus it cannot reference a `stack` it never builds. Task `^zde3s2t` re-exports `FoundationModelsExtras`, thus `DotfolderStack` needs no third import.

```swift
import FoundationModels
import FoundationModelsSkills

// The host selects the layer roots. The usual way is a "skills" dotfolder stack:
let stack = DotfolderStack(
    name: "skills",
    workingDirectory: projectDirectory,
    defaultsDirectory: shippedSkillsURL,
    userDirectory: userConfigURL)
let registry = SkillsRegistry(stack: stack, watch: true)

// One fused tool for the full catalog: search, list, use, resources, scripts.
// The session you supply runs the selection tier. Nothing is hardcoded.
let skillsTool = try await SkillsTool.make(
    registry: registry,
    session: { prefix in LanguageModelSession(model: .default, instructions: prefix) })

// A lean root session: one tool, preloaded bodies, no full catalog in context.
let session = LanguageModelSession(
    tools: [skillsTool],
    instructions: Instructions {
        "You use the skills tool to search and run skills from the local library."
        registry.preloadedBodies()
    })
```

Add one short paragraph below it. Say two things: `SkillsTool` gives an `OperationTool`, which conforms to the framework `Tool` protocol, thus it goes into any standard session; and the search tier takes an injected session, thus a host that wants no model at all can omit the `session:` argument and get keyword retrieval.

Keep the `Install` and `Documentation` sections as they are.

### Demo

The hand assembly is in `Examples/skills-demo/SkillsDemoAssembly.swift:21-23`. `ChatMode.swift:111` and `WatchMode.swift:22` only call `SkillsDemoAssembly.makeContext(registry:)`, thus changing the one assembly file is enough. Change it to the factory.

### Operations doc

`docs/operations.md` shows no hand assembly. Its one relevant line, 33, only names `SkillsTool.make`. Read it, and change it only if the new signature makes that line wrong. Do not make a change for its own sake.

- [x] Replace the README usage block and add the paragraph.
- [x] Change `SkillsDemoAssembly.swift` to the factory.
- [x] Read `docs/operations.md:33` and correct it only if it is wrong.
- [x] Add the README compile test.

## Acceptance Criteria

- [x] The README usage block compiles as written, with `FoundationModels` and `FoundationModelsSkills` as its only imports.
- [x] `swift build` builds `skills-demo`, and `SkillsDemoTests` passes.
- [x] `swift run skills-demo --chat` still drives the same scripted `search skill` -> `use skill` round trip.
- [x] No document in the repository tells a host to import `FoundationModelsMetadataRegistry`.

## Tests

- [x] New file `Tests/FoundationModelsSkillsTests/ReadmeExampleTests.swift`. Its imports are only `FoundationModels`, `FoundationModelsSkills`, and `Testing`.
- [x] A test case holds the exact code of the README usage block, over the `Examples/skill-library` fixture stack, and asserts the tool is built. The test compiles, thus the README cannot drift into code that does not build.
- [x] A test case dispatches `search skill` through that tool and asserts on the ranked ids.
- [x] `SkillsDemoTests` still passes with no change to its assertions.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.