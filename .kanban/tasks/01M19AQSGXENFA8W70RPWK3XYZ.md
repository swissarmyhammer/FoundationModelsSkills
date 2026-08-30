---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1aavmte4xrn0scg5dgg9fw8
  text: |-
    Picked up. Research done.

    Facts found:
    - `plan.md` names the Router in prose at four places: the section 3 box (SkillSearchAgent line), the section 7 prose ("selection session on a Router model", "cheaper Router-selected model"), decision 17's "Reaffirmed after #26" paragraph, decision 26, and the API sketch.
    - The API sketch is under the heading `## 10. Public API sketch (illustrative)`, not section 7. The card calls it "section 7's public API sketch". Both places get corrected; the sketch itself is in section 10.
    - The last decision is #29, thus the new decision is #30.
    - The shipped factory (`Sources/FoundationModelsSkills/Operations/SkillsToolAssembly.swift`) gives three `async throws` overloads: `make(registry:session:embedder:followReloads:visibilityPredicate:)` with `session: @escaping @Sendable (String) -> any AgentSession`, the same with `session: any AgentSession`, and `make(registry:embedder:followReloads:visibilityPredicate:)` with no session.
    - `SeamReexports.swift` records that `FoundationModelsMetadataRegistry` re-exports `FoundationModelsRanker`, which carries the ungated `extension LanguageModelSession: AgentSession` conformance. This is why the fused tool works on a standard `LanguageModelSession`.
    - The macOS 27 floor now comes from `FoundationModelsExtras` and FoundationModels v2 (`Package.swift` says this).

    Sketch corrections necessary for "a reader who copies it gets code that compiles":
    - `try SkillsRegistry(stack:...)` -- the initializer does not throw.
    - `policy: .init(disableShellExecution: false)` -- the field is `RenderPolicy.isShellExecutionDisabled`.
    - The hand-built `SkillsToolContext` + `OperationTool` block -- replaced by `try await SkillsTool.make(registry:session:)`.
    - `OperationCLIDriver(tool: skillsTool)` + `cli.run(CommandLine.arguments)` -- the shipped door is `SkillsCLI.makeDriver(registry:)` and `await driver.run(arguments:)`.
  timestamp: 2026-08-30T21:57:53.102206+00:00
- actor: claude-code
  id: 01m1ab8gszk54z7s3s7e941rk1
  text: |-
    Implementation landed. TDD order kept: the two new cases went in first and failed with 3 issues (no decision 30, no `SkillsTool.make(registry:session:)` in the sketch, `RoutedEmbedderAdapter` still in the sketch). Then plan.md was amended.

    What changed in plan.md:
    - Section 3 box: the `SkillSearchAgent` line now reads "(#26/#30, an injected selection session + rank-fusion; never the root session)". Both lines keep the box width of 78 characters, the same as their neighbours.
    - Section 7 prose: the selection session is now "the host injects", the output is constrained by guided generation, and no sentence names a Router model.
    - Decision 17 and decision 26: original text untouched, one "**Amended 2026-08-30 by #30:**" paragraph added below each.
    - New decision 30, "Router-free package; the host injects the selection session", dated 2026-08-30.
    - Section 10 API sketch: rewritten around `try await SkillsTool.make(registry:session:)`.
    - Section 13, last paragraph: the gated integration case no longer names "the Router/MetadataRegistry tiny-model pattern". `HotReloadLiveTests` states it never imports the Router and drives a plain `LanguageModelSession` over `SystemLanguageModel`, thus that sentence was the last stale present-tense Router claim in the file. It now names the on-device model and its one gate.

    The sketch was proved to compile, not assumed. A script cut the fenced block out of plan.md verbatim, wrapped it in `enum SketchCompileCheck { static func run(cwd:shippedSkillsURL:) async throws { ... } }` in the test target, and `swift build --build-tests` reported "Build complete!" with no error. The scratch file was then deleted; `git status` confirms it is gone.

    Three further errors in the sketch had to be corrected for that build to pass, all in the passage the card names:
    - `try SkillsRegistry(stack:...)` -- the initializer does not throw.
    - `policy: .init(disableShellExecution: false)` -- the field is `RenderPolicy.isShellExecutionDisabled`.
    - `OperationCLIDriver(tool:)` + `cli.run(CommandLine.arguments)` -- the shipped door is `SkillsCLI.makeDriver(registry:)` and `await driver.run(arguments:)`.

    Note for the next agent: the card calls the sketch "section 7's public API sketch". In the file it sits under `## 10. Public API sketch (illustrative)`. The new test pins that heading text, thus a renumbering of the section fails the case with `MissingSectionError` and not with a silent pass.

    `swift test`: 403 tests in 31 suites passed, zero failures, zero warnings.
  timestamp: 2026-08-30T22:04:54.975561+00:00
- actor: claude-code
  id: 01m1ab8msn40hbwq35c01ydb1a
  text: |-
    ### implement — changed
    - evidence: 2 files — plan.md, Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift. `swift test`: 403 tests in 31 suites passed, 0 failures, 0 warnings. `swift build --build-tests` over the verbatim section 10 sketch: Build complete, 0 errors.
    - next: ready for /review
  timestamp: 2026-08-30T22:04:59.061074+00:00
depends_on:
- 01M19A1WVBB8AHK15V4K8109G9
position_column: doing
position_ordinal: '80'
title: Amend the plan.md decision record for the Router removal
---
## What

`plan.md` is this package's decision record. Two of its decisions rest on a dependency the package no longer has. Amend them. Do not rewrite the history of a decision — add the amendment below the original text, in the style the file already uses for decision 15 and decision 18, which both carry a "Superseded by" note.

Write every text in this task in ASD-STE100 Simplified Technical English.

### The passages

- **Decision 17** ("no target split") — its "Reaffirmed after 26" paragraph says the whole package carries the `FoundationModelsMetadataRegistry` to `FoundationModelsRouter` dependency and its macOS 27 floor. The conclusion holds, the reason changed: the floor now comes from `FoundationModelsExtras` and FoundationModels v2.
- **Decision 26** ("Search: depend on FoundationModelsMetadataRegistry") — it says the selection session is Router-backed and that the package therefore depends on `FoundationModelsRouter`. The selection tier now takes any `AgentSession`, and `FoundationModelsRanker` conforms `LanguageModelSession` to it. Record that the host injects the session.
- **The layered architecture block in section 3** — the `SkillSearchAgent` line names a "separate Router session".
- **Section 7's public API sketch** — it shows `selection: .init(model: profile.flash)` with a `// FoundationModelsRouter` comment, and `RoutedEmbedderAdapter`. Replace with the injected-session form the new factory takes.

Add one new dated decision that records the change itself: the package is Router-free, the selection session is injected by the host, and the fused tool is usable on a standard `LanguageModelSession`. Number it after the last existing decision.

- [x] Amend decision 17.
- [x] Amend decision 26.
- [x] Correct the section 3 architecture block and the section 7 API sketch.
- [x] Add the new dated decision.

## Acceptance Criteria

- [x] `plan.md` states, in a dated decision, that this package no longer depends on `FoundationModelsRouter`, and that the host injects the selection session.
- [x] Decision 17 and decision 26 each keep their original text and carry an amendment below it.
- [x] The section 7 API sketch matches the factory signature that task `^mx1rkqx` added. A reader who copies it gets code that compiles.
- [x] No sentence in `plan.md` says, in the present tense, that this package depends on the Router.

## Tests

- [x] Add a test case to `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift`. It reads `plan.md` and asserts that the file holds the new dated decision heading. This pins the amendment against a later edit that drops it.
- [x] A test case asserts that the section 7 API sketch names `SkillsTool.make(registry:session:)` and does not name `RoutedEmbedderAdapter`.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.