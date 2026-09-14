---
assignees:
- claude-code
depends_on:
- 01M2H0Q56QJCW8KNEVFM0S1TZE
position_column: todo
position_ordinal: '8580'
title: Copy the 24 sah skills and 8 partials into ../skills and convert the templates
---
## What

**Cross-repository task.** Run it from a session opened in `/Users/wballard/github/swissarmyhammer/skills`. The `/finish` pipeline in FoundationModelsSkills cannot do it. Steps marked **(operator)** need the network and a person's approval.

marketplace.md §3.4 and §3.5. This is a **copy**. Read from `/Users/wballard/github/swissarmyhammer/swissarmyhammer/builtin`, and do not change anything in sah.

- Before you start, record `git -C ../swissarmyhammer rev-parse HEAD` and `git -C ../swissarmyhammer status --porcelain`.
- Copy each folder in `builtin/skills/` (24 skills, with `references/` and every other file) to `skills/<name>/`.
- Copy the 8 partials that skills include to `skills/_partials/sah-<name>.md`: `findings-are-requirements`, `architecture-awareness`, `task-standards`, `task-double-check`, `record-progress`, `step-record`, `card-report`, `review-column`. Do not copy `_partials/project-types/`.
- Change each `{% include "_partials/<name>" %}` to `{% include "_partials/sah-<name>" %}`. This applies in the skill files, in `plan/references/PLANNING_GUIDE.md`, and inside the partials if one partial includes another.
- Change `metadata.version: "{{version}}"` to `metadata.version: "1.0.0"` in each `SKILL.md`.
- In `ci/SKILL.md` and `map/SKILL.md`, change the `{% if arguments %}…{{arguments}}…{% endif %}` block to this package's `$ARGUMENTS` form (plan.md §5).
- Keep every frontmatter field as it is, including `agent:`, `context:`, `background:`, and `hooks:`.

- [ ] Copy the skill folders
- [ ] Copy and rename the 8 partials, and rewrite the include names
- [ ] Replace `{{version}}`, and convert the `arguments` blocks in `ci` and `map`
- [ ] Extend `SkillLibraryTests`, and commit
- [ ] **(operator)** `git push`

## Acceptance Criteria
- [ ] `skills/` has exactly the 24 sah skill folders plus `_partials/`
- [ ] No file under `skills/` contains `{{version}}`, `{{ arguments`, `{{arguments`, or an include of a name without the `sah-` prefix
- [ ] Every skill loads with no `.skip` and no `.warning` diagnostic, and renders on the untrusted path with no error
- [ ] The sah `HEAD` and the sah `git status --porcelain` output are the same after the task as before it

## Tests
- [ ] `Tests/SkillsMarketplaceTests/SkillLibraryTests.swift` in `../skills`: `copiesAllSkills` (the 24 ids equal a checked-in list); `libraryHasNoBlockingDiagnostics`; `everySkillRendersUntrusted` (for each id, `registry.call(id:arguments: [])` returns a body with no `{%` and no `{{`); `noLiquidLeftovers` (scan every text file under `skills/`)
- [ ] Run `swift test` in `../skills`; expect green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cross-repo