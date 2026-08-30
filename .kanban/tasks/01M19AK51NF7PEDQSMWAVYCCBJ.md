---
assignees:
- claude-code
position_column: todo
position_ordinal: '8880'
title: Bump the sibling packages to current main and repair the API drift
---
## What

`Package.resolved` pins `FoundationModelsRanker` and `FoundationModelsMetadataRegistry` to revisions that are older than the `main` of each. The pinned Ranker has a two-argument `SelectionConfig.init(model:)`. The `main` of Ranker has a one-argument form.

This bump is independent of the Router work. Ranker `main` is clean and pushed. Do this task first, thus every later task is written against one API.

### Steps

1. Run `swift package update`. This moves `FoundationModelsRanker` and `FoundationModelsMetadataRegistry` to the current `main` of each.
2. Repair each `SelectionConfig(model:)` call site. The current signature is `@Sendable (String) -> any AgentSession`, one argument (`../FoundationModelsRanker/Sources/FoundationModelsRanker/Selection/SelectionConfig.swift:90`). There are two sites:
   - `Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift:83` — `SelectionConfig(model: { instructions, _ in ... })`
   - `Tests/FoundationModelsSkillsTests/HotReloadTests.swift:122` — `SelectionConfig(model: { _, _ in sessionFactory.makeSession() })`
3. Correct the stale sentence at `Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift:29-33`. It says the closure "ignores the `Grammar` argument". There is no second argument any more.
4. Repair any other compile error the bump exposes.

Do not touch `.gitignore`. `Package.resolved` is ignored at `.gitignore:4` and stays ignored.

- [ ] Run `swift package update`.
- [ ] Repair the two `SelectionConfig` call sites.
- [ ] Correct the stale doc sentence.
- [ ] Run the full test suite.

## Acceptance Criteria

- [ ] `swift build` and `swift test` both pass against the bumped graph.
- [ ] No `SelectionConfig(model:)` call site passes a two-argument closure.
- [ ] `grep -rn "Grammar" Tests/ Sources/` gives no sentence that says a selection closure takes a `Grammar` argument.
- [ ] The Router is still in the graph after this task. Removing it is a separate task.

## Tests

- [ ] `HotReloadTests` passes with no change to its assertions. Only the closure shape changes.
- [ ] `HotReloadLiveTests` compiles. It skips on a host with no on-device model.
- [ ] `swift test` passes with zero failures and zero warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.