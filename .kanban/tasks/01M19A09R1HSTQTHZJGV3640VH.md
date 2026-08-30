---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
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

Add `Tests/FoundationModelsSkillsTests/CIWorkflowTests.swift`. Copy the structure of `../FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/CIWorkflowTests.swift`.

- [ ] Add `.github/workflows/ci.yml` with its header comment.
- [ ] Add `CIWorkflowTests` with the three test cases below.
- [ ] Run the full test suite.

## Acceptance Criteria

- [ ] `.github/workflows/ci.yml` exists and calls `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main`.
- [ ] `ci.yml` declares no repository-local job that runs tests. Every test run is delegated.
- [ ] A push to a branch and a pull request both start the workflow.
- [ ] `swift test` passes at the repository root, and it runs every unit test.

## Tests

- [ ] New file `Tests/FoundationModelsSkillsTests/CIWorkflowTests.swift`. Locate `ci.yml` from the package root, in the same way the sibling suite does.
- [ ] A test case asserts that `ci.yml` holds the `uses:` line for the shared workflow at `@main`.
- [ ] A test case asserts that `ci.yml` declares exactly one job, and that the job has no `steps:` key. This pins the delegation.
- [ ] A test case asserts that `ci.yml` sets the `concurrency` group and `cancel-in-progress: true`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.