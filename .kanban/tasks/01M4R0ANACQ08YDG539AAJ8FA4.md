---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4r4b1nz002sy5b6fasrq0hr
  text: |-
    Research done.
    - Extras at 6ac66c1 gives `PathConfinement.relativePath(of:in:)`. It resolves the symbolic links of the existing prefix of both URLs and compares whole components. It gives `nil` for the root itself, for a path outside the root, for `..` that goes out, and for a link that goes out.
    - `SkillOverlay.directories` is lowest first, thus `relativePath(for:)` walks `directories.reversed()`.
    - `ReadResource.execute(in:)` and `RunScript.execute(in:)` each use `path` in each step inside `withResolvedOverlay`. The plan: find the relative path first, then run the old steps on the relative path. The denied message keeps the path that the model gave.
    - `RunScript`: the host policy gate stays before `withResolvedOverlay`, thus the order of the gates does not change.
    - Test fixtures: `LayerFixtureSupport.makeLayerDirectories` (temporary directory), `ReadResourceTests.read(...)`, `RunScriptTests` with the `release-notes` fixture.
  timestamp: 2026-10-12T13:20:25.279694+00:00
- actor: claude-code
  id: 01m4r4s43d68jjjb2cv7e66wws
  text: |-
    Implementation landed (TDD: each new test failed first, then passed).
    - `SkillOverlay.relativePath(for:)`: a path with no leading `/` comes back with no change; an absolute path goes to `PathConfinement.relativePath(of:in:)` for each layer directory, highest first. No symlink resolution in this package; `LoadingBoundaryTests` passes.
    - `ReadResource` and `RunScript`: `execute(in:)` now calls `relativePath(for:)` first inside `withResolvedOverlay`, and gives `deniedMessage(path:)` with the path of the model on `nil`. The old steps moved to a private `read(_:in:)` / `run(_:in:context:)` that take the relative path. Results and later correctives name the relative path. The host policy gate of `RunScript` stays before `withResolvedOverlay`.
    - `ResourcePathRules.pathParameterDescription` holds the card text for the `path` parameter; both operations use it.
    - `ResourceTestSupport.successResult(of:)` and `correctiveMessage(of:)` are now generic over `CorrectiveOutcome`, thus `ReadResourceTests` reuses them. Callers in `RunScriptTests` compile with no change.
    - `DocumentationTests` holds `docs/operations.md` to two new phrases: "an absolute path in a layer directory of the skill" and "each other absolute path is refused".
    - Discovery: before this change, `read resource` of `/etc/hosts` already gave the denied message (the text check refused it), thus that test passed at RED time and stays as a guard.
    - The `/tmp` test makes its directory under the literal `/tmp` and checks both forms against both forms of the overlay directory.
    - The build prints `warning: missing creator for mutated node: ... mlx-swift_Cmlx.bundle` from SwiftPM. It is not from this change and was there before.
  timestamp: 2026-10-12T13:28:06.509440+00:00
- actor: claude-code
  id: 01m4r4s6706eaj2wstc14rkdvq
  text: |-
    ### implement — changed
    - evidence: `swift test` — 579 tests in 55 suites passed, 0 failures. 11 files: Sources/FoundationModelsSkills/Resources/SkillOverlay.swift, ReadResource.swift, RunScript.swift, ResourceSupport.swift; Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift, ReadResourceTests.swift, RunScriptTests.swift, ResourceOpsTests.swift, ResourceTestSupport.swift, DocumentationTests.swift; docs/operations.md. Not committed.
    - next: /review
  timestamp: 2026-10-12T13:28:08.672086+00:00
depends_on:
- 01M4R0NQVS6M1G3SBMXHH71NX8
position_column: doing
position_ordinal: '80'
title: 'Resource paths: accept an absolute path that is in a layer directory of the skill'
---
## What
The model sometimes gives an absolute path, for example after `read resource` gives the absolute path of a binary file. `read resource` and `run script` must accept it, but only when the path is in a layer directory of the skill. A path relative to the skill must work as it does now.

This package must not resolve symlinks itself: `Tests/FoundationModelsSkillsTests/LoadingBoundaryTests.swift` forbids `resolvingSymlinksInPath` in `Sources/FoundationModelsSkills/`. Use `PathConfinement.relativePath(of:in:)` of FoundationModelsExtras (from the dependency task).

- `Sources/FoundationModelsSkills/Resources/SkillOverlay.swift`: add `internal func relativePath(for path: String) -> String?`.
  - A path that does not start with `/` comes back with no change. `ResourcePathRules.isWellFormedRelativePath(_:)` checks it later, as now.
  - An absolute path: call `PathConfinement.relativePath(of: URL(fileURLWithPath: path), in: directory)` for each URL in `directories`, highest first. Return the first result that is not `nil`. If no directory holds the path, return `nil`.
- After the relative path is found, the overlay always reads the winning copy. Thus an absolute path into a lower layer reads the copy of the highest layer that holds that relative path.
- `Sources/FoundationModelsSkills/Resources/ReadResource.swift`: in `execute(in:)`, inside `withResolvedOverlay`, call `overlay.relativePath(for: path)` first. Use the relative path for `resolve`, `size` and `scan`, and as the `path` of `ReadResourceResult`. If the result is `nil`, give `ResourcePathRules.deniedMessage(path:)` with the path that the model gave.
- `Sources/FoundationModelsSkills/Resources/RunScript.swift`: apply the same rule inside `withResolvedOverlay`, after gate 1 (host policy), and before the `scripts/` prefix check. The order of the gates does not change.
- Update the `path` parameter description in `ReadResource.parameterMetadata` and `RunScript.parameterMetadata`: "The path of the file, relative to the skill directory, for example `references/guide.md`. An absolute path in the skill directory also works."
- `docs/operations.md`: in the operations table, say that `read resource` and `run script` accept an absolute path in a layer directory of the skill, and that each other absolute path is refused.

## Acceptance Criteria
- [x] `read resource` with `path: "references/changelog.md"` gives the same result as now.
- [x] `read resource` with the absolute path of that file gives the same content, and the result `path` is `references/changelog.md`.
- [x] The `/private/tmp` form and the `/tmp` form of the same absolute path give the same result.
- [x] An absolute path into a lower layer, when a higher layer holds a different copy, gives the higher-layer copy.
- [x] Each of these gives the denied corrective message: `/etc/hosts`; a file of a different skill; a sibling directory with the same name prefix (`.../release-notes-extra/x`); an absolute path with `..` that goes out of the skill; a symlink in the skill that points outside it.
- [x] `run script` accepts an absolute path to a file in `scripts/` of the skill, and refuses an absolute path outside the skill. A disabled host policy still refuses first.
- [x] `LoadingBoundaryTests` passes.

## Tests
- [x] `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift`: unit tests of `relativePath(for:)` for each case above.
- [x] `Tests/FoundationModelsSkillsTests/ReadResourceTests.swift`: a relative read and an absolute read of the same file give equal content; an absolute path outside the skill gives the denied message.
- [x] `Tests/FoundationModelsSkillsTests/RunScriptTests.swift`: an absolute script path in the skill runs; an absolute path outside the skill is denied; host policy refuses before the path check.
- [x] `swift test` passes with no failure.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.