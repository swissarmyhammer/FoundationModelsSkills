---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0zc2zsxsw58h6ktmtt5j07k
  text: |-
    Research and implementation notes.

    - Cause: `resolvingSymlinksInPath()` normalizes a path that exists (removes `/private` on macOS) but leaves a path that does not exist unchanged. The skill directory always exists, so the candidate and the directory get different normalization when the candidate is missing.
    - Fix in `PathConfinement.swift`: new private helper `resolvingSymlinksOfExistingPrefix(_:)`. It walks up from the candidate to the longest prefix that exists, resolves that prefix, and appends the missing components unchanged. A dangling link does not exist for `fileExists(atPath:)`, so the link name is appended unchanged and the read then fails at the open, which draws the unreadable corrective. A symlink in the middle of the path that points outside the skill still resolves outside and is denied.
    - Callers of `resolvedURL` (`ListResource`, `ReadResource`, `RunScript`) keep the same signature. The only behavior change is for a path that does not exist.
    - Tests in `ReadResourceTests.swift`: `makeScratchRoot(under:)` now takes a parent, `read(...)` takes an optional `scratchParent`. Two new tests read a missing file and a dangling link under `FileManager.default.temporaryDirectory` and expect the unreadable corrective. The stale comment that referred to this card is replaced.
    - `swift test`: 377 tests in 26 suites passed. The first run hung inside `swiftpm-testing-helper` after all tests had passed (output stopped at the pass lines); helpers were killed and the second run completed in 9 s.
  timestamp: 2026-08-26T15:47:43.549663+00:00
- actor: claude-code
  id: 01m0zc30wqhjvxjv787btyksy0
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsSkills/Resources/PathConfinement.swift, Tests/FoundationModelsSkillsTests/ReadResourceTests.swift; `swift test` 377 tests passed
    - next: test, commit, review
  timestamp: 2026-08-26T15:47:44.663641+00:00
- actor: claude-code
  id: 01m0zc3fy0hsdfst0k7wxjwdyv
  text: |-
    ### test — green
    - evidence: `timeout 300 swift test` — 377 tests in 26 suites passed, 0 failed; one pre-existing env-gated skip (`SKILLS_INTEGRATION_TESTS`); no warning in project source. The first run hung in `swiftpm-testing-helper` after all tests passed; helpers were killed and the re-run completed in 9 s.
    - next: commit
  timestamp: 2026-08-26T15:48:00.064237+00:00
- actor: claude-code
  id: 01m0zc42g38tq5m6j90ryapfh9
  text: |-
    ### commit — changed
    - evidence: 9748095 fix(resources): normalize a missing path through its existing prefix in PathConfinement (local commit, not pushed; includes the pending `.kanban` state of ^2045jq7 from the previous task)
    - next: review
  timestamp: 2026-08-26T15:48:19.075672+00:00
- actor: claude-code
  id: 01m0zc6mc18vng16ahe5wv8d69
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 7 validator runs attempted, 0 failed; 2 files reviewed (PathConfinement.swift, ReadResourceTests.swift), 4 `.kanban` files excluded by `.reviewignore`
    - next: done
  timestamp: 2026-08-26T15:49:42.913353+00:00
- actor: claude-code
  id: 01m0zc6pc4cp6718z0ghx7hzm8
  text: |-
    ### finish iteration 1 — review clean, task moved to done
    - implement: changed — PathConfinement.swift resolves the longest existing prefix of the candidate; ReadResourceTests.swift adds two temp-root tests
    - test: green — `timeout 300 swift test`, 377 passed, 0 failed (first run hung in swiftpm-testing-helper after all tests passed; re-run completed in 9 s)
    - commit: 9748095
    - review: clean — 0 findings on HEAD~1..HEAD
  timestamp: 2026-08-26T15:49:44.964135+00:00
position_column: done
position_ordinal: b780
title: PathConfinement denies a missing path under a /private-prefixed skill root instead of the unreadable corrective
---
`Sources/FoundationModelsSkills/Resources/PathConfinement.swift`

On macOS, `SkillDiscovery` lists skill directories with `FileManager.contentsOfDirectory(at:)`, which gives a `/private/var/...` path for a root under the temp directory. `PathConfinement.resolvedURL(relativePath:in:)` then calls `resolvingSymlinksInPath()` on the skill directory. Foundation removes the `/private` prefix from a path that exists, but it leaves a path that does not exist (a missing file, a dangling symbolic link) unchanged. The two paths then do not share a prefix, and `isContained` says `false`.

Result: a `read resource` call for a missing file or a dangling symbolic link under such a root draws the confinement corrective (\"is not accessible\") in place of the unreadable corrective (\"could not be read\"). The refusal is safe, but the message is wrong.

Measured with a probe script on 2026-08-26: listed directory `/private/var/.../dangling`, resolved directory `/var/.../dangling`, dangling candidate `/private/var/.../dangling/dangling-link`, contained `false`.

Fix: compare the two paths after the same normalization, for example resolve the parent directory of the candidate and append the last component, or remove the `/private` prefix from both sides. Add a test that reads a missing file under a temp root and expects \"could not be read\".

## Acceptance

- [x] `PathConfinement.resolvedURL` normalizes the candidate through the same call as the skill directory: it resolves the longest prefix that exists and appends the remaining components.
- [x] A test reads a missing file under a temp root and expects \"could not be read\".
- [x] A test reads a dangling symbolic link under a temp root and expects \"could not be read\". #bug