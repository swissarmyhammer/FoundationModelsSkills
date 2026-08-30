---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19drfk1xa7654dfdr32vw0x
  text: |-
    ### plan correction — locate the package root through FixtureLibrary

    The board review found that this task and `^02wba0s` named two different
    mechanisms for the same job, in the same test target. This task said "in the
    same way the sibling suite does" (the sibling derives the root from `#filePath`
    with three `deletingLastPathComponent()` calls). `^02wba0s` said "the same way
    `FixtureLibrary.swift` does".

    **Use `FixtureLibrary.root(thisFile:)`.** It is already in this test target, and
    `^mx1rkqx` has since added `FixtureLibrary.stack(thisFile:)` beside it. Two new
    test files must not resolve one root two ways.

    Second correction: the task says "Copy the structure of the sibling suite". The
    sibling has three cases and no `concurrency` case. This task asks for four,
    including `concurrency` and the `on:` block. That is deliberate — it makes the
    trigger acceptance criterion machine-checkable. Copy the sibling's shape, then
    add the two extra cases.
  timestamp: 2026-08-30T13:29:20.737156+00:00
- actor: claude-code
  id: 01m19e0fbz7xe15eqyqqz0akfa
  text: |
    ### research and one naming note on the plan correction

    Discoveries:

    - The gated suite named in the header comment is `HotReloadLiveTests`
      (`@Suite("Gated live-model hot-reload twin (plan.md §13)")`). It lives in the
      same `FoundationModelsSkillsTests` target as the unit tests, not in a nested
      package. Each of its tests carries a two-part `.enabled(if:)` gate:
      `SKILLS_INTEGRATION_TESTS == "1"` and
      `SystemLanguageModel.default.isAvailable`. Thus a plain `swift test` reports
      it as skipped, never as a failure.
    - The sibling `FoundationModelsExtras` names its single job `unit:`, the
      sibling `FoundationModelsMetadataRegistry` and `FoundationModelsRanker` name
      it `ci:`. This task copies the MetadataRegistry file, so the job is `ci:`.
    - `.gitignore` holds eight lines and ignores nothing below `.github`, as the
      card says. No ignore change was made.

    Naming note on the plan correction:

    The correction says "Use `FixtureLibrary.root(thisFile:)`". `FixtureLibrary`
    has two accessors: `packageRoot(thisFile:)` returns the package root, and
    `root(thisFile:)` returns `Examples/skill-library`, which is the fixture
    library root below it. `ci.yml` sits at the package root, so the test calls
    `FixtureLibrary.packageRoot()`. This obeys the correction: the test target
    still resolves the root in exactly one place, and no second `#filePath` walk
    was added. A call to `root()` would have needed two more
    `deletingLastPathComponent()` calls, which is the duplication the correction
    prohibits.
  timestamp: 2026-08-30T13:33:42.655639+00:00
- actor: claude-code
  id: 01m19e9w88h8tqa03kxajkmd2j
  text: |
    ### implement — changed

    TDD record, in order:

    1. RED. `CIWorkflowTests.swift` was written first. `swift test --filter
       CIWorkflowTests` failed with 4 tests / 4 issues, each one an
       `NSCocoaErrorDomain Code=260` for the absent
       `.github/workflows/ci.yml`. The failure also proved the path resolution:
       the reported `NSFilePath` was the package root plus
       `.github/workflows/ci.yml`.
    2. GREEN. `.github/workflows/ci.yml` was added. The same filter passed 4/4.
    3. Mutation proof. A wrong `ci.yml` was written on purpose (`@v1` instead of
       `@main`, `branches: [develop]`, no `workflow_dispatch:`, `group: ci-fixed`,
       `cancel-in-progress: false`, and a second `local:` job with `steps:`). The
       run gave 7 issues, one for each assertion, each with its own message. Thus
       no assertion passes for the wrong reason. The good file was then restored
       and the suite is green again.

    Files:

    - `.github/workflows/ci.yml` (new, 35 lines).
    - `Tests/FoundationModelsSkillsTests/CIWorkflowTests.swift` (new, 161 lines).

    Notes for the reviewer:

    - The suite uses two private static helpers. `workflowLines()` reads the file
      through `FixtureLibrary.packageRoot()`, which is the accessor
      `SkillsRegistryTests` already uses for a package-root path.
      `block(under:in:)` returns the lines nested below a top-level key, so the
      `on:` assertions read indentation and not a flat text search. This is why
      `    branches: [main]` is proven to be a child of `push:`.
    - The `ci.yml` header comment first claimed that `CIWorkflowTests` pins "the
      absence of every `integration-*` input". The card asks for four test cases
      and that case is not one of them, so the claim was false. The comment now
      lists only what the four cases prove.

    Evidence: `swift build` clean; `swift test` = 390 tests in 29 suites passed,
    0 failures. The only skip is the pre-existing gated
    `HotReloadLiveTests` test, which needs `SKILLS_INTEGRATION_TESTS=1`. The only
    build warning is the accepted mlx-swift `missing creator for mutated node`
    warning (see archived `^vwthc4s`). `diagnostics check working` reports 0
    errors and 0 warnings.

    ### implement — changed
    - evidence: 2 files — /Users/wballard/github/swissarmyhammer/FoundationModelsSkills/.github/workflows/ci.yml, /Users/wballard/github/swissarmyhammer/FoundationModelsSkills/Tests/FoundationModelsSkillsTests/CIWorkflowTests.swift; `swift test` 390 passed / 0 failed / 1 gated skip
    - next: /review
  timestamp: 2026-08-30T13:38:50.760456+00:00
position_column: doing
position_ordinal: '80'
title: Add the CI workflow that delegates to the shared swift-ci workflow
---
## What

This package has no `.github` directory. Every sibling package has one. Add the same CI that `FoundationModelsRanker`, `FoundationModelsMetadataRegistry`, and `FoundationModelsExtras` use.

Add `.github/workflows/ci.yml`. Copy the shape of `../FoundationModelsMetadataRegistry/.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ci:
    uses: swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main
```

Pass no input in this task. The unit job is the whole of CI for now. A later task adds the integration job for the gated live suite.

Write a header comment that says which suites the unit job runs, and that the `SKILLS_INTEGRATION_TESTS` gated suite is not yet wired. Follow the header comment style of the sibling file.

The shared workflow runs on `[self-hosted, macOS]`. This package resolves three `git@github.com:swissarmyhammer/` dependencies over SSH, and `FoundationModelsMetadataRegistry` already resolves the same way on the same pool. Thus no new secret is needed.

`.gitignore` holds seven lines and ignores nothing under `.github`. No ignore change is needed.

Add `Tests/FoundationModelsSkillsTests/CIWorkflowTests.swift`. Copy the structure of `../FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/CIWorkflowTests.swift`.

- [x] Add `.github/workflows/ci.yml` with its header comment.
- [x] Add `CIWorkflowTests` with the four test cases below.
- [x] Run the full test suite.

## Acceptance Criteria

- [x] `.github/workflows/ci.yml` exists and calls `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main`.
- [x] `ci.yml` declares no repository-local job that runs tests. Every test run is delegated.
- [x] `ci.yml` declares `on:` with `push` on `main`, `pull_request`, and `workflow_dispatch`.
- [x] `swift test` passes at the repository root, and it runs every unit test.

## Tests

- [x] New file `Tests/FoundationModelsSkillsTests/CIWorkflowTests.swift`. Locate `ci.yml` from the package root, in the same way the sibling suite does.
- [x] A test case asserts that `ci.yml` holds the `uses:` line for the shared workflow at `@main`.
- [x] A test case asserts that `ci.yml` declares exactly one job, and that the job has no `steps:` key. This pins the delegation.
- [x] A test case asserts that the `on:` block declares `push` with `branches: [main]`, `pull_request`, and `workflow_dispatch`. This makes the trigger acceptance criterion machine-checkable.
- [x] A test case asserts that `ci.yml` sets the `concurrency` group and `cancel-in-progress: true`.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.