---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2n6rz3s5sjkz4b7qg7dwvy6
  text: |-
    Research and implementation notes for the copy into `/Users/wballard/github/swissarmyhammer/skills`.

    Source state, recorded before and after the copy, and the same at both times:
    - `git -C ../swissarmyhammer rev-parse HEAD` = `9e6fbd8168e5f803b9d3cc7ba6517126cb3c161d`
    - `git -C ../swissarmyhammer status --porcelain` = empty

    Template survey of the source, made before the copy. The whole `builtin/skills/` tree plus the 8 partials use only these Liquid constructs:
    - `{% include "_partials/<name>" %}` (8 distinct names, 26 sites)
    - `{% if arguments %}` / `{% endif %}` (only `ci` and `map`)
    - `{{version}}` (one site in each of the 24 `SKILL.md` files)
    - `{{arguments}}` / `{{ arguments }}` (only `ci` and `map`)

    There is no filter anywhere, thus the untrusted render path needs no other conversion. Nothing could not be converted.

    Discoveries that changed how the work was done:
    - No partial includes another partial. Only `plan/references/PLANNING_GUIDE.md` includes a partial from outside a `SKILL.md`.
    - `_partials/project-types/` and `_partials/validator-tools.md` are not included by any skill, thus neither was copied.
    - `builtin/skills/README.md` is a file, not a skill folder. It describes the sah `.skills/` store, thus it was not copied: the acceptance criterion asks for exactly the 24 folders plus `_partials/`.
    - `finish/SKILL.md` and `kanban/SKILL.md` hold text like `` `!` `` in a filter-DSL table. This looked like shell injection at first read. It is not: the `ShellInjection` grammar needs `(?<![^\s])` before the `!`, and a backtick sits there. No skill triggers pass 2.
    - No skill body uses `$0` or `$1`. The `$name` forms it does use (`$HOME`, `$REPO`, `${ARG:?...}`) are left as written by pass 1, because no skill declares `arguments:` frontmatter.
    - 9 skills already use the `$ARGUMENTS` form, thus the `ci` and `map` conversion follows a pattern the library already holds.
    - `SkillsRegistry.init(roots:)` labels each root `.project`, and `StencilPass` maps a non-`.defaults` layer to `.untrusted`. Thus the suite renders on the untrusted path with no extra setup.

    Conversion applied:
    - 24 skill folders copied whole, with `references/` and `tdd/writing-good-tests.md`. 42 Markdown files in total.
    - 8 partials copied to `skills/_partials/sah-<name>.md`, and all 26 include sites rewritten to the `sah-` name.
    - `metadata.version` pinned to `"1.0.0"` in each of the 24 `SKILL.md` files.
    - `ci/SKILL.md` and `map/SKILL.md`: the `{% if arguments %}` block replaced by the `$ARGUMENTS` form. Because the tag is gone, each place now says in plain words what to do when the text is empty.
    - `skills/_partials/.gitkeep` removed: the folder holds 8 partials now.
  timestamp: 2026-09-16T13:33:51.609138+00:00
- actor: claude-code
  id: 01m2n6tnf1fnb9m35negd78f6v
  text: |-
    TDD record. Each new test was made to fail first, and each failed for the correct reason.

    - Move `skills/tdd` away: `copiesAllSkills` fails on the id list, `libraryHasNoBlockingDiagnostics` fails, and `everySkillRendersUntrusted` fails with `UnknownSkillError(id: "tdd")`.
    - Append `{{version}}` to `skills/tdd/SKILL.md`: `noLiquidLeftovers` fails on the forbidden fragment.
    - Change one include to `_partials/findings-are-requirements`: `noLiquidLeftovers` fails on the include count, and `everySkillRendersUntrusted` fails with `partial "_partials/findings-are-requirements" not found`.

    Each sabotage was reverted, and the suite is green again.

    ### implement — changed
    - evidence: 24 skill folders and 8 partials copied, 44 files added in `/Users/wballard/github/swissarmyhammer/skills`; local commit `86ce9ceb789934ed772f86349889322e53ba6432`; `swift test` = 4 tests in 1 suite passed, 0 failures, 0 warnings; sah `HEAD` `9e6fbd8168e5f803b9d3cc7ba6517126cb3c161d` and an empty `git status --porcelain`, the same as before the task.
    - next: `/review`. The `git push` subtask stays open for the operator.
  timestamp: 2026-09-16T13:34:47.265339+00:00
- actor: claude-code
  id: 01m2n70jvn2t3xgvashbgqtqsb
  text: |
    ### review — clean
    - scope: `/Users/wballard/github/swissarmyhammer/skills` at commit `86ce9ce`
    - method: every check made directly. The `review` MCP engine is bound to the FoundationModelsSkills root, thus it cannot read this sibling repository.
    - evidence: 0 findings. 24 skill folders plus `_partials/` (the 24 names equal sah `builtin/skills/`); 8 `sah-*.md` partials, each byte-identical to its source; 24 `include` tags and no other tag, no filter, and no `{{ }}`; each include names a partial that is present; `diff -r` shows 105 changed lines, all of them planned (24 version, 24 include rename, 2 `arguments` blocks); sah source clean at `9e6fbd8`; `swift package clean && swift test` gives 4 tests in 1 suite passed, 0 warnings; secret scan found nothing.
    - next: move to done. The `(operator) git push` mark is still open, but `origin/main` equals `86ce9ce`, thus the push is complete on the remote. A person sets the mark.
  timestamp: 2026-09-16T13:38:01.205082+00:00
depends_on:
- 01M2H0Q56QJCW8KNEVFM0S1TZE
position_column: done
position_ordinal: e480
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

- [x] Copy the skill folders
- [x] Copy and rename the 8 partials, and rewrite the include names
- [x] Replace `{{version}}`, and convert the `arguments` blocks in `ci` and `map`
- [x] Extend `SkillLibraryTests`, and commit
- [ ] **(operator)** `git push`

## Acceptance Criteria
- [x] `skills/` has exactly the 24 sah skill folders plus `_partials/`
- [x] No file under `skills/` contains `{{version}}`, `{{ arguments`, `{{arguments`, or an include of a name without the `sah-` prefix
- [x] Every skill loads with no `.skip` and no `.warning` diagnostic, and renders on the untrusted path with no error
- [x] The sah `HEAD` and the sah `git status --porcelain` output are the same after the task as before it

## Tests
- [x] `Tests/SkillsMarketplaceTests/SkillLibraryTests.swift` in `../skills`: `copiesAllSkills` (the 24 ids equal a checked-in list); `libraryHasNoBlockingDiagnostics`; `everySkillRendersUntrusted` (for each id, `registry.call(id:arguments: [])` returns a body with no `{%` and no `{{`); `noLiquidLeftovers` (scan every text file under `skills/`)
- [x] Run `swift test` in `../skills`; expect green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cross-repo

## Review Findings (2026-09-16 08:40)

Scope: `/Users/wballard/github/swissarmyhammer/skills` at commit `86ce9ce`. The
`review` engine is bound to the FoundationModelsSkills root and cannot read a
sibling repository, thus each check below was made directly.

Zero findings. No item to act on.

Evidence:
- `skills/` holds 24 skill folders plus `_partials/`, and the 24 names equal the
  24 folders of sah `builtin/skills/`.
- `skills/_partials/` holds the 8 `sah-*.md` partials, each byte-identical to
  its sah source. `_partials/project-types/` was not copied.
- The only template tag in the whole tree is `include`: 8 distinct tags, 24
  occurrences, each one naming a partial that is present. No `if`, no `for`, no
  filter, and no `{{ }}` output tag anywhere.
- `diff -r` against sah `builtin/skills/` shows 105 changed lines, and each one
  is a planned conversion: 24 `version` replacements, 24 include renames, and
  the two `arguments` blocks in `ci/SKILL.md` and `map/SKILL.md`. No skill lost
  content, and no file is missing or surplus.
- The sah source tree is unmodified: `HEAD` is `9e6fbd8` and
  `git status --porcelain` is empty.
- `swift package clean && swift test` in `../skills`: 4 tests in 1 suite pass,
  with 0 warnings.
- A scan for a key, a credential, a token, a private key, and a personal path
  found nothing. The three hits are prose about CI secrets and a `/Users/me/...`
  placeholder, all of which come from the sah source.
- `origin/main` equals `86ce9ce`, thus the operator push step is complete on the
  remote. The mark stays for the operator to set.
