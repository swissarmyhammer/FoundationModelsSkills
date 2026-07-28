---
depends_on:
- 01KYNCPTS07BHG6PQS17PE17T4
position_column: todo
position_ordinal: '8180'
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
- [ ] The directory tree above exists with syntactically valid frontmatter (except designed-broken fixtures)
- [ ] Fixtures are addressable from tests via a helper that resolves `Examples/skill-library` relative to `#filePath` (hermetic — never the real home directory, plan §11)
- [ ] Each §5/§6 feature in this slice appears exactly once

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/FixtureLibraryTests.swift` — helper resolves each fixture path; frontmatter of the happy-path fixtures parses with Yams
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.