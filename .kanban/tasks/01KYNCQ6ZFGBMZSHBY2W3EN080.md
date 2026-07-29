---
comments:
- actor: claude-code
  id: 01kynp823n09w8qpcwsqesf7rr
  text: |-
    Implemented via TDD.

    RED: Wrote `Tests/FoundationModelsSkillsTests/FixtureLibrary.swift` (helper, `#filePath`-relative resolution mirroring the family's `PackageRootValidation.packageRoot` pattern from FoundationModelsExtras/FoundationModelsShelltool) and `FixtureLibraryTests.swift` (fixture-existence checks + Yams frontmatter-decode assertions for the 6 happy-path SKILL.md fixtures). Ran `swift test` before creating any fixtures — confirmed 17 failures, all for the correct reason (missing files / "No such file or directory").

    Dead end caught during RED: my first hermetic-resolution test asserted `!root.path.hasPrefix(homeDirectoryForCurrentUser.path)` — this is wrong, since the repo itself legitimately lives under `$HOME` on disk, so the assertion is unsatisfiable regardless of implementation correctness. Replaced it with a test that proves resolution is a pure function of the injectable `thisFile` parameter (an unrelated fake path resolves deterministically with no env dependency) — that's the actual hermeticity guarantee plan.md §11 asks for.

    GREEN: Created the full fixture tree exactly matching the task's bullet list — `defaults/base-style`, `user/base-style` (full-replace override, decision #3), `user/_partials/header.md` (not a skill dir), `project/.skills/{commit,deploy,lint,spec-clean}` (arguments+hint+$0/$ARGUMENTS; disable-model-invocation; user-invocable:false; pure-spec top level with metadata.* extensions per decision #27), plus `Examples/skill-library/broken/{bad-colon-description,missing-description,name-mismatch,partial-flag}` for later lenient-validation tests. `swift test`: 11/11 pass, exit 0, no new warnings. `swift build`: clean.

    Spawned the `double-check` adversarial reviewer per really-done before handoff.
  timestamp: 2026-07-29T01:01:27.541462+00:00
- actor: claude-code
  id: 01kynpgw8rch94yh28x190h80p
  text: |-
    double-check adversarial review: PASS, no findings. It independently re-verified (not just trusted): every fixture's frontmatter shape and name==directory match; the bad-colon-description fixture's invalidity by actually running it through PyYAML (`mapping values are not allowed here`); FixtureLibrary's path math and hermeticity by running the tests and reading the source (confirmed no FileManager.homeDirectoryForCurrentUser/$HOME/env usage); the fixture tree against plan.md §11 lines 697-730 and decision #3; and confirmed git-context/env-report/release-notes (later-task fixtures) are correctly absent.

    Final state: `swift test` 11/11 pass, exit 0, no new warnings; `swift build` clean. Leaving task in `doing` for `/review` per the implement workflow (implement does not move tasks to review).
  timestamp: 2026-07-29T01:06:16.472159+00:00
- actor: claude-code
  id: 01kynq6fcrhvzf4p59vtb6c02h
  text: |-
    Addressed both review findings.

    1. `Tests/FoundationModelsSkillsTests/FixtureLibrary.swift` `url(_:thisFile:)`: added a `precondition` before appending `relativePath` to the resolved root -- splits on `/` (omitting empty subsequences) and traps if any component is `".."`, or if the raw string starts with `"/"` or `"~"`. Closes the path-traversal/absolute-path hole the finding described, while every existing fixture path (e.g. `project/.skills/commit/SKILL.md`, `user/_partials/header.md`) still resolves normally. Updated the function's doc comment to note the constraint.

    2. `Tests/FoundationModelsSkillsTests/FixtureLibraryTests.swift`: split the `SkillFrontmatter` doc comment so the "Test-local -- the real decode type lands with `SkillsRegistry` in a later task." elaboration sits after a blank `///` line instead of being crammed onto the same line as the summary's last sentence, per Swift doc-comment convention.

    Verified: `swift build` exit 0 (only pre-existing unrelated SwiftPM dependency-identity warnings, no new warnings). `swift test` 11/11 pass, exit 0, no warnings. Spawned the `double-check` adversarial reviewer per really-done; awaiting its verdict before finalizing.
  timestamp: 2026-07-29T01:18:04.184917+00:00
- actor: claude-code
  id: 01kynqgfy8k684tgvdm4nc8xxx
  text: |-
    double-check adversarial review: PASS. Independently traced the precondition against traversal (`../../etc/passwd`), absolute (`/etc/passwd`), and home-relative (`~/x`) inputs -- all correctly trap -- confirmed every real fixture path used by the existing tests still resolves unchanged, confirmed the doc-comment split matches Swift convention with no content lost, and independently re-ran `swift build` (exit 0, only the two pre-existing unrelated `foundationmodelsoperationtool` identity-conflict warnings) and `swift test` (11/11 pass, exit 0).

    Checked off both review-finding checkboxes via `update task` (full-body replace, since this store uses replace-not-merge semantics). Follow-up `get task` confirms the description is intact otherwise (both checkboxes now `[x]`, no other content changed) and the update did not touch anything else.

    Tag-hazard note: investigated the "verify tags 27/3 intact" instruction before acting on it. Tags `27` and `3` were created in this repo's kanban store at the same instant as this task (suggesting they were meant for it), but neither this task's `.md`/`.jsonl` history nor tags `27`'s/`3`'s own `.jsonl` history contains any assignment event linking them to this task -- `tags` has read `[]` since before I touched anything, including in the very first `get task` I ran this session. This looks like a pre-existing gap from task creation (possibly conflated with sibling task `01KYNCPTS07BHG6PQS17PE17T4`, which genuinely does carry tags `26`/`29`), not something dropped by a review-cycle `update task` call. I did not fabricate a `27`/`3` assignment that has no evidence of ever existing -- left `tags: []` as found, and passed `tags: []` explicitly on my `update task` call so the omission couldn't be misread as an implicit wipe. Flagging for the user/orchestrator to decide whether `27`/`3` should be assigned now.

    Final state: `swift build` exit 0 (no new warnings), `swift test` 11/11 pass exit 0. Both review-finding checkboxes are `[x]`. Leaving task in `doing` for `/review` per the implement workflow.
  timestamp: 2026-07-29T01:23:32.424188+00:00
depends_on:
- 01KYNCPTS07BHG6PQS17PE17T4
position_column: doing
position_ordinal: '80'
title: Build the Examples/skill-library fixture stack (M1 slice)
---
## What
Create the fixture skill library from plan.md §11 — the M1 slice used as test data for discovery and frontmatter decoding. Later tasks extend it; this task lands the layered layout and the simple fixtures.

Create under `Examples/skill-library/`:
- `defaults/base-style/SKILL.md` — plain valid skill (spec `name` + `description`)
- `user/base-style/SKILL.md` — full-replace override that shadows the defaults copy (decision #3)
- `user/_partials/header.md` — a partials file, NOT a skill directory (target of a later Stencil task; harmless now)
- `project/.skills/commit/SKILL.md` — `arguments:` + `argument-hint:` + `$0`/`$ARGUMENTS` in the body
- `project/.skills/deploy/SKILL.md` — `disable-model-invocation: true`
- `project/.skills/lint/SKILL.md` — `user-invocable: false`
- `project/.skills/spec-clean/SKILL.md` — pure-spec frontmatter: `license`, `compatibility`, extensions under `metadata.*` (decision #27)

Also add invalid/edge fixtures for the lenient-validation tests in a sibling folder `Examples/skill-library/broken/` (kept out of the three-layer stack so happy-path tests stay clean): unquoted-colon-in-description YAML, missing `description`, `name` ≠ directory name, `partial: true`.

## Acceptance Criteria
- [x] The directory tree above exists with syntactically valid frontmatter (except designed-broken fixtures)
- [x] Fixtures are addressable from tests via a helper that resolves `Examples/skill-library` relative to `#filePath` (hermetic — never the real home directory, plan §11)
- [x] Each §5/§6 feature in this slice appears exactly once

## Tests
- [x] `Tests/FoundationModelsSkillsTests/FixtureLibraryTests.swift` — helper resolves each fixture path; frontmatter of the happy-path fixtures parses with Yams
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-07-28 20:10)

- [x] `Tests/FoundationModelsSkillsTests/FixtureLibrary.swift:56` — Path traversal: the `url()` function accepts a `relativePath` parameter and appends it directly without validating for `..` sequences or absolute paths. Calling `FixtureLibrary.url("../../etc/passwd")` would construct a URL that resolves outside the intended `Examples/skill-library` directory when passed to file operations. Validate `relativePath` to reject path traversal sequences.
- [x] `Tests/FoundationModelsSkillsTests/FixtureLibraryTests.swift:14` — Doc comment contains two sentences without a blank `///` separator; the rule requires elaboration to follow a summary after a blank line. Add a blank `///` line between the summary and the second sentence.
