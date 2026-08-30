---
assignees:
- claude-code
position_column: todo
position_ordinal: '8580'
title: Resolve a Router-free dependency graph and guard it with a test
---
## What

No source file or test file in this package names `FoundationModelsRouter`. All of the Router weight comes through one sibling manifest.

`Package.resolved` holds these 24 packages today. Fourteen of them come only from the Router branch of the graph:

`foundationmodelsrouter`, `mlx-swift`, `mlx-swift-lm`, `swift-huggingface`, `swift-transformers`, `swift-jinja`, `swift-crypto`, `swift-asn1`, `swift-collections`, `swift-numerics`, `swift-distributed-tracing`, `swift-service-context`, `eventsource`, `yyjson`.

They arrive because `../FoundationModelsMetadataRegistry/Package.swift` still declares `FoundationModelsRouter`, `mlx-swift-lm`, `swift-huggingface`, `swift-transformers`, and `swift-jinja` in its `dependencies:` list, although no target of that package links any of them.

### Package.resolved is not committed

`.gitignore:4` ignores `Package.resolved`. Do not try to commit it, and do not remove it from `.gitignore`.

This does not stop the guard test. `swift test` resolves the graph before it runs, thus the file is present on disk in CI and on a developer machine when the test reads it. The test therefore checks the graph that the current `main` of each sibling gives, which is a stronger guard than a pinned file.

### External block

This task cannot finish until the sibling manifest cleanup is on `swissarmyhammer/FoundationModelsMetadataRegistry` `main`. As of 2026-08-30 that repository has 8 unpushed commits and a dirty working tree. Do not edit the sibling repository from this task.

### Steps

1. Run `swift package update` to move onto the cleaned `main` of `FoundationModelsMetadataRegistry` and `FoundationModelsRanker`.
2. Repair the API drift the bump exposes. `Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift:83` calls `SelectionConfig(model: { instructions, _ in ... })` with a two-argument closure. The current `SelectionConfig.init(model:)` takes `@Sendable (String) -> any AgentSession`, one argument (`../FoundationModelsRanker/Sources/FoundationModelsRanker/Selection/SelectionConfig.swift:90`). Drop the second closure parameter. Check every other call site as well.

- [ ] Write the guard test first. It fails against the graph that resolves today.
- [ ] Bump the resolved graph with `swift package update`.
- [ ] Repair the `SelectionConfig` closure arity drift.
- [ ] Run the full test suite.

## Acceptance Criteria

- [ ] `Package.resolved` holds no entry whose identity is `foundationmodelsrouter`, `mlx-swift`, `mlx-swift-lm`, `swift-huggingface`, `swift-transformers`, or `swift-jinja`.
- [ ] `swift build` gives no `mlx-swift` bundle warning. That warning is recorded in `docs/development.md:60-66`.
- [ ] `swift build` and `swift test` both pass.
- [ ] The whole suite compiles against the bumped `FoundationModelsRanker` API.
- [ ] `Package.resolved` stays in `.gitignore` and is not added to the commit.

## Tests

- [ ] New file `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift`.
- [ ] A test case reads `Package.resolved` from the package root, decodes it as JSON, and asserts that the six forbidden identities above are absent. Fail with a message that names each identity that was found. Locate the package root the same way `Tests/FoundationModelsSkillsTests/FixtureLibrary.swift` does.
- [ ] The test must fail, not skip, when `Package.resolved` is absent. A silent skip would let the guard rot.
- [ ] A test case asserts that the resolved identity set is exactly the expected allow list, thus a new transitive dependency is a visible, deliberate change and never a silent one.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.