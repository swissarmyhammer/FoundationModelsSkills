---
assignees:
- claude-code
depends_on:
- 01M199ZVM11XKMQ5WWSET0AR2E
- 01M19A1WVBB8AHK15V4K8109G9
position_column: todo
position_ordinal: '8780'
title: Show the just-a-tool path in the README and the demo
---
## What

The README usage block and `Examples/skills-demo` both show the hand assembly of `MetadataSearcher` -> `SkillSearchAgent` -> `SkillsToolContext`, and both need `import FoundationModelsMetadataRegistry`. Show the one-call path instead.

### README

Replace the usage block in `README.md:15-38`. The new block shows a host that already holds a `LanguageModelSession` and gives it to the tool:

```swift
import FoundationModels
import FoundationModelsSkills

// The host selects the layer roots. The usual way is a "skills" dotfolder stack.
let registry = SkillsRegistry(stack: stack, watch: true)

// One fused tool for the full catalog: search, list, use, resources, scripts.
// The session you supply runs the selection tier. Nothing is hardcoded.
let skillsTool = try SkillsTool.make(
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

Change `Examples/skills-demo` to build its tool with the factory. Read `Examples/skills-demo/ChatMode.swift` and find each place that assembles the context by hand.

### Operations doc

Correct `docs/operations.md` if it shows the hand assembly.

- [ ] Replace the README usage block and add the paragraph.
- [ ] Change the demo to the factory.
- [ ] Correct `docs/operations.md`.
- [ ] Add the README compile test.

## Acceptance Criteria

- [ ] The README usage block compiles as written, with `FoundationModels` and `FoundationModelsSkills` as its only imports.
- [ ] `swift build` builds `skills-demo`, and `SkillsDemoTests` passes.
- [ ] `swift run skills-demo --chat` still drives the same scripted `search skill` -> `use skill` round trip.
- [ ] No document in the repository tells a host to import `FoundationModelsMetadataRegistry`.
- [ ] Every text written in this task is ASD-STE100 Simplified Technical English.

## Tests

- [ ] New file `Tests/FoundationModelsSkillsTests/ReadmeExampleTests.swift`. Its imports are only `FoundationModels`, `FoundationModelsSkills`, and `Testing`.
- [ ] A test case holds the exact code of the README usage block, over the `Examples/skill-library` fixture stack, and asserts the tool is built. The test compiles, thus the README cannot drift into code that does not build.
- [ ] A test case dispatches `search skill` through that tool and asserts on the ranked ids.
- [ ] `SkillsDemoTests` still passes with no change to its assertions.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.