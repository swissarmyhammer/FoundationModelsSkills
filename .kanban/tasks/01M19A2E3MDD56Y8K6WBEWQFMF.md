---
assignees:
- claude-code
depends_on:
- 01M199ZVM11XKMQ5WWSET0AR2E
- 01M19AQSGXENFA8W70RPWK3XYZ
position_column: todo
position_ordinal: '8780'
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

- [ ] Replace the README usage block and add the paragraph.
- [ ] Change `SkillsDemoAssembly.swift` to the factory.
- [ ] Read `docs/operations.md:33` and correct it only if it is wrong.
- [ ] Add the README compile test.

## Acceptance Criteria

- [ ] The README usage block compiles as written, with `FoundationModels` and `FoundationModelsSkills` as its only imports.
- [ ] `swift build` builds `skills-demo`, and `SkillsDemoTests` passes.
- [ ] `swift run skills-demo --chat` still drives the same scripted `search skill` -> `use skill` round trip.
- [ ] No document in the repository tells a host to import `FoundationModelsMetadataRegistry`.

## Tests

- [ ] New file `Tests/FoundationModelsSkillsTests/ReadmeExampleTests.swift`. Its imports are only `FoundationModels`, `FoundationModelsSkills`, and `Testing`.
- [ ] A test case holds the exact code of the README usage block, over the `Examples/skill-library` fixture stack, and asserts the tool is built. The test compiles, thus the README cannot drift into code that does not build.
- [ ] A test case dispatches `search skill` through that tool and asserts on the ranked ids.
- [ ] `SkillsDemoTests` still passes with no change to its assertions.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.