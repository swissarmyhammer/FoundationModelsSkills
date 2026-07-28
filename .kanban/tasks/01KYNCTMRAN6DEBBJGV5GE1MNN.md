---
depends_on:
- 01KYNCS3K5T60E4JQAJ8JQWXC5
- 01KYNCRS3QJFK120446YNXYAH7
position_column: todo
position_ordinal: 8a80
title: 'Render pass 1: argument + variable substitution'
---
## What
Implement §5 pass 1 (Claude-compatible substitution), replacing the identity transform.

- `Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift`:
  - `$ARGUMENTS` — all args joined as typed; when the body has no `$ARGUMENTS` and args were supplied, append `ARGUMENTS: <value>` (the no-data-loss fallback).
  - `$ARGUMENTS[N]` and `$N` — 0-based positional; arguments are pre-split with shell-style quoting (a small tokenizer: double/single quotes, backslash escapes).
  - `$name` — named args resolved through the §6.1 parameter model (`arguments:` frontmatter order).
  - `${SKILL_DIR}` — the skill's directory path; leave room for more special vars behind one table.
  - `\$` escapes a literal `$`; escaped dollars never substitute.
  - Single-shot: substituted output is not re-scanned (values containing `$0` stay literal).
  - Missing positional/named reference with no supplied value → substitute empty + note (the ops layer decides correctives from the §6.1 required flags).

## Acceptance Criteria
- [ ] `commit` fixture renders its `$0`/`$ARGUMENTS` body correctly for quoted multi-word args
- [ ] `\$HOME` survives as `$HOME`; `$HOME` (not an arg name) is untouched by pass 1 (env is pass 3's job)
- [ ] Auto-append fires only when args are supplied AND the body lacks `$ARGUMENTS`
- [ ] A substituted value containing `$1` is not re-substituted

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/ArgumentSubstitutionTests.swift` — table-driven: every token form, quoting cases, escape cases, auto-append matrix, no-re-scan case
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.