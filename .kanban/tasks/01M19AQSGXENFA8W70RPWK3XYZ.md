---
assignees:
- claude-code
depends_on:
- 01M19A1WVBB8AHK15V4K8109G9
position_column: todo
position_ordinal: '8980'
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

- [ ] Amend decision 17.
- [ ] Amend decision 26.
- [ ] Correct the section 3 architecture block and the section 7 API sketch.
- [ ] Add the new dated decision.

## Acceptance Criteria

- [ ] `plan.md` states, in a dated decision, that this package no longer depends on `FoundationModelsRouter`, and that the host injects the selection session.
- [ ] Decision 17 and decision 26 each keep their original text and carry an amendment below it.
- [ ] The section 7 API sketch matches the factory signature that task `^mx1rkqx` added. A reader who copies it gets code that compiles.
- [ ] No sentence in `plan.md` says, in the present tense, that this package depends on the Router.

## Tests

- [ ] Add a test case to `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift`. It reads `plan.md` and asserts that the file holds the new dated decision heading. This pins the amendment against a later edit that drops it.
- [ ] A test case asserts that the section 7 API sketch names `SkillsTool.make(registry:session:)` and does not name `RoutedEmbedderAdapter`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.