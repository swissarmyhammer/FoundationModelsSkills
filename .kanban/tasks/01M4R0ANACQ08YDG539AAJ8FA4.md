---
assignees:
- claude-code
depends_on:
- 01M4R0NQVS6M1G3SBMXHH71NX8
position_column: todo
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
- [ ] `read resource` with `path: "references/changelog.md"` gives the same result as now.
- [ ] `read resource` with the absolute path of that file gives the same content, and the result `path` is `references/changelog.md`.
- [ ] The `/private/tmp` form and the `/tmp` form of the same absolute path give the same result.
- [ ] An absolute path into a lower layer, when a higher layer holds a different copy, gives the higher-layer copy.
- [ ] Each of these gives the denied corrective message: `/etc/hosts`; a file of a different skill; a sibling directory with the same name prefix (`.../release-notes-extra/x`); an absolute path with `..` that goes out of the skill; a symlink in the skill that points outside it.
- [ ] `run script` accepts an absolute path to a file in `scripts/` of the skill, and refuses an absolute path outside the skill. A disabled host policy still refuses first.
- [ ] `LoadingBoundaryTests` passes.

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillOverlayTests.swift`: unit tests of `relativePath(for:)` for each case above.
- [ ] `Tests/FoundationModelsSkillsTests/ReadResourceTests.swift`: a relative read and an absolute read of the same file give equal content; an absolute path outside the skill gives the denied message.
- [ ] `Tests/FoundationModelsSkillsTests/RunScriptTests.swift`: an absolute script path in the skill runs; an absolute path outside the skill is denied; host policy refuses before the path check.
- [ ] `swift test` passes with no failure.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.