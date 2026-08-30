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
- actor: claude-code
  id: 01m1abw596zp909tn2ey31htgb
  text: |
    ### review — findings
    - evidence: 2 findings, 2 confirmed, 1 refuted — Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift:206, Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift:223 (scope: review sha HEAD~1..HEAD, backend local)
    - acceptance criteria: verified independently, all four hold. Decision 17 hunk (@@ -563,6 +564,12 @@) and decision 26 hunk (@@ -613,6 +620,15 @@) are purely additive — zero deleted lines, the original wording is intact. The section 10 sketch was extracted verbatim and type-checked against the built modules with zero errors; every symbol matches the shipped API, including SkillsTool.make(registry:session:) at Sources/FoundationModelsSkills/Operations/SkillsToolAssembly.swift:92 and SkillsCLI.makeDriver(registry:) at Sources/FoundationModelsSkills/CLI/SkillsCLI.swift:32. plan.md holds nine Router mentions, all historical or amended; RoutedEmbedderAdapter and profile.flash have zero hits.
    - guard tests: neither case can pass vacuously. planSection(startingWith:) throws MissingSectionError when the heading is absent instead of returning an empty string, planText() uses an unguarded throwing read, and each case pairs its negative assertion with a positive one.
    - next: apply the two findings in DependencyGraphTests.swift, then request a new review pass.
  timestamp: 2026-08-30T22:15:38.534202+00:00
- actor: claude-code
  id: 01m1abymxh60x3awypfpq85gw3
  text: |-
    ### findings addressed — static members qualified with `Self.`

    Both findings are fixed, and the cause is removed from the whole file, not only the two flagged lines. Five unqualified static references were in static methods; all five now carry `Self.`:

    - `:206` `planFileName` — the finding.
    - `:223` `planText()` — the finding.
    - `:228` `sectionHeadingPrefix` — same cause, same file, not flagged.
    - `:321` `resolutionFileName` — same cause, same file, not flagged.

    `removedIdentities`'s initializer at `:58` is left as it is. It is a static stored property, not a static method, thus it is outside the class of the two findings.

    `swift test`: 403 tests in 31 suites pass, 0 failures.

    **One correction to the record, for the next reader.** Each finding says the unqualified form "is not in scope" and "will not compile". That reason is not correct: Swift lets a static method name another static member of the same type without a qualifier, and the file compiled and passed 403 tests before this change. The remedy is still applied, because the explicit form is clearer and costs nothing. Only the stated reason is wrong, not the request.
  timestamp: 2026-08-30T22:17:00.081135+00:00
depends_on:
- 01M19A1WVBB8AHK15V4K8109G9
position_column: review
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

## Review Findings (2026-08-30 17:06)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 1 file(s) reviewed, 7 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift:206` `swift/idioms` — Static property access within a static method requires qualification with `Self.` or the type name; unqualified `planFileName` is not in scope. Change `planFileName` to `Self.planFileName` on line 206.
- [x] `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift:223` `swift/idioms` — Static method call within a static method requires qualification with `Self.` or the type name; unqualified `planText()` is not in scope and will not compile. Change `try planText()` to `try Self.planText()` on line 223.

Both are fixed. The cause is removed from the whole file: four unqualified static references in static methods now carry `Self.` — `:206` `planFileName`, `:223` `planText()`, `:228` `sectionHeadingPrefix`, and `:321` `resolutionFileName`. The last two were not flagged but share the cause. `removedIdentities`'s initializer at `:58` is a static stored property, not a static method, thus it is outside the class of these findings and is unchanged. `swift test`: 403 tests in 31 suites pass.