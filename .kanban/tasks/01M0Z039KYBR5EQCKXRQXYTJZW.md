---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0z6h6nvxwmbh4kv25vxcdqg
  text: |-
    Research notes:
    - `SkillDiscovery.discover()` accepts a candidate when `FileManager.fileExists(atPath:)` is true for `SKILL.md`. A directory named `SKILL.md` also passes this check.
    - `SkillsRegistry.validate(discovered:diagnostics:)` (lines 484-497) catches the read error, appends a `.skip` diagnostic with message prefix "SKILL.md could not be read:", and returns `nil`.
    - `Tests/FoundationModelsSkillsTests/ReadResourceTests.swift` already has the pattern for an unreadable file: `unreadableMode = 0o000`, `isRoot` from `geteuid() == 0`, and `FileManager.setAttributes([.posixPermissions:])`.
    - `SkillsRegistryTests.swift` has the helpers `writeSkillFixture(id:skillMarkdown:in:)` and `makeTempDirectory()`. The new test uses them.
    - Plan: write a real `SKILL.md`, then set its mode to `0o000`. When the process is root, replace the file with a directory named `SKILL.md`. Put a second healthy skill in the same root.
  timestamp: 2026-08-26T14:10:37.883703+00:00
- actor: claude-code
  id: 01m0z6j78qnzfz2vt9aw9yfd4g
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsSkillsTests/SkillsRegistryTests.swift. Added `unreadableMode`, `isRoot`, `writeUnreadableSkill(id:in:)`, and the test `anUnreadableSkillFileDropsThatSkillWithASkipDiagnosticAndLeavesTheHealthySiblingLoaded`. `swift test --filter SkillsRegistryTests`: 22 tests passed.
    - next: test, commit, review
  timestamp: 2026-08-26T14:11:11.255940+00:00
- actor: claude-code
  id: 01m0z7t5shfzdzjp3m2pv7hb16
  text: |-
    ### test — green
    - evidence: `swift test` — 369 tests in 25 suites passed, 0 failed, 0 warnings. 1 skipped: the env-gated live-model test (tracked as ^tb86z9q). A first full run hung behind a stale `swift-test` process; after that process was killed, the rerun passed.
    - next: commit
  timestamp: 2026-08-26T14:33:00.465231+00:00
- actor: claude-code
  id: 01m0z7tnprv6wry0s4hhydhg5m
  text: |-
    ### commit — changed
    - evidence: 9336663 test(registry): cover the unreadable SKILL.md skip diagnostic
    - next: review
  timestamp: 2026-08-26T14:33:16.760048+00:00
- actor: claude-code
  id: 01m0z7xrxrbvptxne63e06yj7y
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 7 validators attempted, 0 failed. Only Tests/FoundationModelsSkillsTests/SkillsRegistryTests.swift was in scope.
    - next: task moved to done
  timestamp: 2026-08-26T14:34:58.360073+00:00
- actor: claude-code
  id: 01m0z7xxvzb7bt4xz4935y5221
  text: |-
    ### finish iteration 1 — review clean, task in done
    - implement: changed — Tests/FoundationModelsSkillsTests/SkillsRegistryTests.swift (unreadable SKILL.md test and fixture helpers)
    - test: green — swift test, 369 passed, 0 failed, 0 warnings, 1 env-gated skip (^tb86z9q)
    - commit: 9336663
    - review: clean — 0 findings on HEAD~1..HEAD
  timestamp: 2026-08-26T14:35:03.423754+00:00
position_column: done
position_ordinal: b180
title: 'Add test for SkillsRegistry.validate: the unreadable SKILL.md diagnostic'
---
`Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`

Coverage: 97.6% (279/286 lines)

Uncovered lines: 489-495

Add this test. Do not change `SkillsRegistry.swift`.

Lines 489-495 are the `catch` branch of
`validate(discovered:diagnostics:)`. The branch runs when
`String(contentsOf:encoding:)` fails on a SKILL.md that discovery already
found. It appends a `.skip` diagnostic and gives back `nil`, so the
skill drops out of the catalog instead of the load failing.

Write the test like this:

1. Build a skill directory that holds a SKILL.md file discovery accepts.
2. Make that SKILL.md unreadable. Set its mode to `0o000` with
   `FileManager`. A directory named `SKILL.md` also works, and does not
   depend on the file mode.
3. Load the registry.
4. Make sure the skill id is not in `metadata()`.
5. Make sure the diagnostics hold one entry whose severity is `.skip`,
   whose `skillID` is the dropped skill's id, and whose message starts
   with "SKILL.md could not be read:".
6. Make sure the registry loads without an error, and that a second,
   healthy skill in the same root is still in the catalog. This proves
   one bad skill does not stop the load.

If the test runs as root, a `0o000` file mode can still be readable. In
that condition, use the directory-named-SKILL.md form.

Put the test in `Tests/FoundationModelsSkillsTests/`, next to the
registry tests that are there. #coverage-gap