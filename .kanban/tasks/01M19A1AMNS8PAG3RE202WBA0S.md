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
- actor: claude-code
  id: 01m1a985mehra9t1vwkwzn51e6
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (78df64a) — 0 findings, 0 confirmed, 0 refuted, 7 validators attempted, 0 failed. 1 file reviewed (`Tests/FoundationModelsSkillsTests/DependencyGraphTests.swift`); 2 `.kanban/` files excluded by `.reviewignore`.
    - verified independently: `Package.resolved` holds 10 pins (foundationmodelsextras, foundationmodelsmetadataregistry, foundationmodelsranker, pathkit, spectre, stencil, swift-argument-parser, swift-syntax, ulid.swift, yams). None of the five deny-list identities is present. `swift-jinja` is also gone, and the test makes no claim about it.
    - verified independently: the read at `DependencyGraphTests.swift:69` is an unguarded `try Data(contentsOf:)`, thus an absent file throws and the test fails. It does not skip. The doc comment says why the read stays unguarded.
    - verified independently: the doc comment names the suite a live-resolution tripwire and gives the reason for a deny list and not an allow list -- every sibling is pinned to `branch: "main"`.
    - verified independently: the test calls `FixtureLibrary.packageRoot()` at `DependencyGraphTests.swift:68`. It adds no second `#filePath` walk.
    - verified independently: `.gitignore:4` still ignores `Package.resolved`, `git ls-files` shows it untracked, and the commit does not hold it.
    - verified independently: `swift test --filter DependencyGraphTests` -> 1 test in 1 suite passed. The build gave no warning, thus no `mlx-swift` bundle warning.
    - next: none. Task moved to done.
  timestamp: 2026-08-30T21:29:46.382005+00:00
- actor: claude-code
  id: 01m1a98ycj83bbmmvhr04bsd02
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 1 file (DependencyGraphTests.swift); `swift package update` took the graph from 24 identities to 10
    - test: green — swift test, 400 tests in 31 suites, 0 failures, 0 warnings, 0 skipped
    - commit: 78df64a
    - review: clean — 0 findings, 7 validators attempted; the reviewer read Package.resolved itself and confirmed all five deny-list identities are absent
    - next: task is in done; ^k8109g9 is now unblocked

    The Router is out of this package's graph. `swift build` no longer emits the mlx-swift bundle warning that docs/development.md records — ^k8109g9 deletes that note.
  timestamp: 2026-08-30T21:30:11.730826+00:00
depends_on:
- 01M19AK51NF7PEDQSMWAVYCCBJ
position_column: done
position_ordinal: c080
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