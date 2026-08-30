---
assignees:
- claude-code
depends_on:
- 01M19AK51NF7PEDQSMWAVYCCBJ
position_column: todo
position_ordinal: '8580'
title: Resolve a Router-free dependency graph and guard it with a test
---
## What

No source file or test file in this package names `FoundationModelsRouter`. All of the Router weight comes through one sibling manifest.

`Package.resolved` holds 24 packages today. Fourteen of them come only from the Router branch of the graph:

`foundationmodelsrouter`, `mlx-swift`, `mlx-swift-lm`, `swift-huggingface`, `swift-transformers`, `swift-jinja`, `swift-crypto`, `swift-asn1`, `swift-collections`, `swift-numerics`, `swift-distributed-tracing`, `swift-service-context`, `eventsource`, `yyjson`.

They arrive because `../FoundationModelsMetadataRegistry/Package.swift:187-201` declares `FoundationModelsRouter` (188), `mlx-swift-lm` (190), `swift-huggingface` (191), `swift-transformers` (192), and `swift-jinja` (200).

### DO NOT START. The upstream change does not exist yet.

Checked on 2026-08-30: the sibling cleanup is **not written**, in any branch. `../FoundationModelsMetadataRegistry/Package.swift` still declares all five. That repository has 9 unpushed commits, and not one of them touches those lines. This package resolves the sibling at `branch: "main"`, which is 9 commits behind even that local tree.

Thus no `swift package update` run from here can remove the Router today. Verify the precondition first, and stop if it is not met. Do not edit the sibling repository from this task.

### `swift-jinja` is a special case

`swift-jinja` is not an unused entry. The sibling's test target links it at `../FoundationModelsMetadataRegistry/Package.swift:238`, and the comment at lines 227-232 says the entry exists to keep the pin marked used. Whether it leaves this package's resolved graph depends on how SwiftPM prunes a dependency that only a sibling's test target uses. Do not assert on it. It is absent from the deny list below for that reason.

### `Package.resolved` is not committed

`.gitignore:4` ignores `Package.resolved`. Do not commit it, and do not remove it from `.gitignore`.

The guard test is therefore a **live-resolution tripwire**, not a lockfile check: `swift test` resolves the graph before it runs, thus the file is on disk when the test reads it, and the test checks the graph that the current `main` of each sibling gives. Record that in the test's doc comment. Assert only the deny list. Do not assert an exact allow list — every sibling is pinned to `branch: "main"`, thus any upstream dependency addition would fail an allow-list case with no local change.

### Steps

1. Verify the precondition: `git -C ../FoundationModelsMetadataRegistry fetch && git -C ../FoundationModelsMetadataRegistry show origin/main:Package.swift | grep FoundationModelsRouter` gives nothing. Stop if it gives a match.
2. Run `swift package update`.
3. Run the full test suite.

- [ ] Verify the upstream precondition. Stop if it is not met.
- [ ] Write the guard test first. It fails against the graph that resolves today.
- [ ] Bump the resolved graph with `swift package update`.
- [ ] Run the full test suite.

## Acceptance Criteria

- [ ] `git show origin/main:Package.swift` in `../FoundationModelsMetadataRegistry` names no `FoundationModelsRouter`. Verify this before the bump.
- [ ] `Package.resolved` holds no entry whose identity is `foundationmodelsrouter`, `mlx-swift`, `mlx-swift-lm`, `swift-huggingface`, or `swift-transformers`.
- [ ] `swift build` gives no `mlx-swift` bundle warning. That warning is recorded in `docs/development.md:60-66`.
- [ ] `swift build` and `swift test` both pass.
- [ ] `Package.resolved` stays in `.gitignore` and is not added to the commit.

## Tests

- [ ] New file `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift`.
- [ ] A test case reads `Package.resolved` from the package root, decodes it as JSON, and asserts that the five deny-list identities above are absent. Fail with a message that names each identity that was found. Locate the package root the same way `Tests/FoundationModelsSkillsTests/FixtureLibrary.swift` does.
- [ ] The test must fail, not skip, when `Package.resolved` is absent. A silent skip would let the guard rot.
- [ ] The test's doc comment states that it is a live-resolution tripwire, and why it asserts a deny list and not an allow list.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #blocked-upstream