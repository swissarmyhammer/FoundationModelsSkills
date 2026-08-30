---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1a7qdhagq3vypbcdrnyvqrg
  text: |-
    Picked up. Precondition verified: `git -C ../FoundationModelsMetadataRegistry fetch` then `git show origin/main:Package.swift | grep -E "FoundationModelsRouter|mlx-swift|swift-huggingface|swift-transformers|swift-jinja"` gives no match (exit 1). The sibling cleanup is on `origin/main`, thus the bump can proceed.

    Before the bump, `Package.resolved` holds 24 identities: eventsource, foundationmodelsextras, foundationmodelsmetadataregistry, foundationmodelsranker, foundationmodelsrouter, mlx-swift, mlx-swift-lm, pathkit, spectre, stencil, swift-argument-parser, swift-asn1, swift-collections, swift-crypto, swift-distributed-tracing, swift-huggingface, swift-jinja, swift-numerics, swift-service-context, swift-syntax, swift-transformers, ulid.swift, yams, yyjson.

    Prior art for the guard test: `../FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift` pins the sibling's *manifest*. This new test pins this package's *resolved graph*, which is the different thing.

    `Package.resolved` format is version 3: a top-level `pins` array of objects with an `identity` field.
  timestamp: 2026-08-30T21:03:08.842572+00:00
- actor: claude-code
  id: 01m1a90z710r2vg67vw45gp2tx
  text: |-
    TDD record.

    RED: `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift` written first. `swift test --filter DependencyGraphTests` failed and named each identity: ["foundationmodelsrouter", "mlx-swift", "mlx-swift-lm", "swift-huggingface", "swift-transformers"].

    GREEN: `swift package update`. The graph went from 24 identities to 10. Removed: foundationmodelsrouter, mlx-swift, mlx-swift-lm, swift-huggingface, swift-transformers, swift-jinja, swift-crypto, swift-asn1, swift-collections, swift-numerics, swift-distributed-tracing, swift-service-context, eventsource, yyjson. SwiftPM pruned swift-jinja too, but the test makes no claim about it.

    The sourcekit-lsp race of `^s7az6dc` did occur, two times. The first `swift package update` stopped with "'mlx-swift-lm' ... couldn't be removed because you don't have permission". `lsof` named sourcekit-lsp PID 13823, which held index-database lock files below `.build/checkouts/mlx-swift-lm`. One `kill` was not sufficient: a new sourcekit-lsp starts and writes into the tree again while `rm -rf` runs, thus the delete must run in a loop with `pkill` before each pass. Three passes cleared the checkout, and the second `swift package update` then completed.

    Absent-file behavior, proved at run time: the read is unguarded, thus an absent `Package.resolved` makes the test fail and never skip. `swift test` cannot show this, because SwiftPM writes the file again before each run -- that is the tripwire premise. The proof ran the test bundle directly, with `Package.resolved` moved away:
    `DYLD_FRAMEWORK_PATH=<platform>/Developer/Library/Frameworks swiftpm-testing-helper --test-bundle-path .../FoundationModelsSkillsTests --testing-library swift-testing -- --filter DependencyGraphTests`
    It failed with: Caught error: ... "The file "Package.resolved" couldn't be opened because there is no such file."

    Stale `.build` check: after the bump, the build directory still held `FoundationModelsRouter.o` and the mlx bundles. `.build` was deleted (the same kill/delete loop was necessary) and the package was built again from zero. `swift build` completed with no warning -- the `mlx-swift` `Cmlx.bundle` "missing creator for mutated node" warning is gone.

    `Package.resolved` stays ignored and is not staged. `.gitignore` is unchanged.
  timestamp: 2026-08-30T21:25:50.433054+00:00
- actor: claude-code
  id: 01m1a91nppv2vpczryaxwgk9e5
  text: |-
    ### implement — changed
    - evidence: 1 file added — Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift. Commands: `swift test --filter DependencyGraphTests` (RED, 1 failure), `swift package update` (24 identities -> 10), `swift build` (clean, no warning), `swift test` (400 tests in 31 suites, 0 failures, 0 warnings, 0 skipped). Package.resolved is not staged; .gitignore is unchanged.
    - next: /review
  timestamp: 2026-08-30T21:26:13.462300+00:00
depends_on:
- 01M19AK51NF7PEDQSMWAVYCCBJ
position_column: doing
position_ordinal: '80'
title: Resolve a Router-free dependency graph and guard it with a test
---
## What

No source file or test file in this package names `FoundationModelsRouter`. All of the Router weight comes through one sibling manifest.

`Package.resolved` held 24 packages. Fourteen of them came only from the Router branch of the graph:

`foundationmodelsrouter`, `mlx-swift`, `mlx-swift-lm`, `swift-huggingface`, `swift-transformers`, `swift-jinja`, `swift-crypto`, `swift-asn1`, `swift-collections`, `swift-numerics`, `swift-distributed-tracing`, `swift-service-context`, `eventsource`, `yyjson`.

They arrived because `../FoundationModelsMetadataRegistry/Package.swift` declared `FoundationModelsRouter`, `mlx-swift-lm`, `swift-huggingface`, `swift-transformers`, and `swift-jinja`.

### The upstream change is now on `origin/main`

Verified on 2026-08-30 before the bump: `git -C ../FoundationModelsMetadataRegistry show origin/main:Package.swift` names none of those five packages.

### `swift-jinja` is a special case

`swift-jinja` was not an unused entry. The sibling's test target linked it, and the comment there said the entry existed to keep the pin marked used. Whether it leaves this package's resolved graph depends on how SwiftPM prunes a dependency that only a sibling's test target uses. Do not assert on it. It is absent from the deny list for that reason. (SwiftPM did prune it, but the test makes no claim about it.)

### `Package.resolved` is not committed

`.gitignore` ignores `Package.resolved`. Do not commit it, and do not remove it from `.gitignore`.

The guard test is therefore a **live-resolution tripwire**, not a lockfile check: `swift test` resolves the graph before it runs, thus the file is on disk when the test reads it, and the test checks the graph that the current `main` of each sibling gives. Assert only the deny list. Do not assert an exact allow list -- every sibling is pinned to `branch: "main"`, thus any upstream dependency addition would fail an allow-list case with no local change.

### Steps

1. Verify the precondition.
2. Run `swift package update`.
3. Run the full test suite.

- [x] Verify the upstream precondition. Stop if it is not met.
- [x] Write the guard test first. It fails against the graph that resolves today.
- [x] Bump the resolved graph with `swift package update`.
- [x] Run the full test suite.

## Acceptance Criteria

- [x] `git show origin/main:Package.swift` in `../FoundationModelsMetadataRegistry` names no `FoundationModelsRouter`. Verify this before the bump.
- [x] `Package.resolved` holds no entry whose identity is `foundationmodelsrouter`, `mlx-swift`, `mlx-swift-lm`, `swift-huggingface`, or `swift-transformers`.
- [x] `swift build` gives no `mlx-swift` bundle warning.
- [x] `swift build` and `swift test` both pass.
- [x] `Package.resolved` stays in `.gitignore` and is not added to the commit.

## Tests

- [x] New file `Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift`.
- [x] A test case reads `Package.resolved` from the package root, decodes it as JSON, and asserts that the five deny-list identities above are absent. Fail with a message that names each identity that was found. It locates the package root with `FixtureLibrary.packageRoot()`.
- [x] The test fails, and does not skip, when `Package.resolved` is absent. Proved at run time with the test bundle run directly.
- [x] The test's doc comment states that it is a live-resolution tripwire, and why it asserts a deny list and not an allow list.
- [x] `swift test` passes: 400 tests in 31 suites, zero failures, zero warnings.

## Workflow
- Use `/tdd` -- write failing tests first, then implement to make them pass.