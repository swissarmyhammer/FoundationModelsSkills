---
comments:
- actor: claude-code
  id: 01m34zm4fe17m7rk77mzrxmyx9
  text: |-
    Picked up. The `.rendered` body, the removal of `rawBody(id:)` and four tests were in the working tree. This round added the open items:

    - `Tests/FoundationModelsSkillsTests/SlashCommandProvidingTests.swift`: new test `commandBodyWithUnquotedTextGivesTheFirstWordToDollarZero`. It renders `commit` with `fix the bug`, compares with `call(id:arguments:)`, and asserts `using the message: fix\n` and one body line equal to `fix the bug`.
    - `plan.md` §6 bullet: the caveat is replaced with the `.rendered` behavior.
    - `plan.md` §7.1 diagram: the UI row says that a `/` command renders through `call(id:arguments:)`. The row is two lines; each row line is 84 columns, the same as the other rows.
    - `plan.md` decision #29: Extras item `c2pad49` is delivered as `SlashCommand.Body.rendered`, and this package uses it.
    - `CHANGELOG.md`: one "Changed" entry at the top of Unreleased, in the shape of the entry below it.

    Discoveries:

    - The `commit` fixture (`Examples/skill-library/project/.skills/commit/SKILL.md`) has `$0` on the `using the message:` line and `$ARGUMENTS` alone on its own line. Thus the "ARGUMENTS line" of the card is a body line that holds the typed text alone, and the test asserts it as one line of `split(separator: "\n")`.
    - The acceptance grep `rg -in "coordination item|passes 1.2 ever run|completely inert|data only\)" plan.md Sources/` finds no line now. It found three lines before (plan.md 251, 391, 743).
    - `swift test --filter SlashCommandProvidingTests`: 14 tests, 14 passed, no warning.
  timestamp: 2026-09-22T16:36:44.142742+00:00
- actor: claude-code
  id: 01m34zrtpvfa68pw92n1p2g6qn
  text: |-
    Rules applied before the edit (`dump validators` over the Swift and Markdown files): the `duplication` rule says that near-verbatim copies that differ by one literal are one function with an argument, and that the fix goes in the changed code. The five body tests of this change repeated the same three-line lookup of one command. They now call one helper, `command(named:in:)`, which reads `commands(workingDirectory:)` and unwraps the match with `try #require`. The tests that existed at HEAD keep their shape, because the rule says not to edit the counterpart.

    `swift test --filter SlashCommandProvidingTests` after the helper: 14 tests, 14 passed, no warning.

    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsSkills/Registry/SkillsRegistry+SlashCommands.swift, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Tests/FoundationModelsSkillsTests/SlashCommandProvidingTests.swift, plan.md, CHANGELOG.md
    - next: /test, the full `swift test`
  timestamp: 2026-09-22T16:39:17.979710+00:00
- actor: claude-code
  id: 01m34ztr8m6dxc5nwk2m45xazj
  text: |-
    ### test — green
    - evidence: `swift test` — 564 tests in 53 suites passed, 0 failed, 0 skipped, no warning
    - next: /commit
  timestamp: 2026-09-22T16:40:21.012192+00:00
- actor: claude-code
  id: 01m34zvb8a18vkrffxawztayej
  text: |-
    ### commit — changed
    - evidence: 9901b19 feat(slash-commands): render the typed text through the full pipeline
    - next: /review 01M34XXTN3HQ3VFJ0KHKEZXK6C HEAD~1..HEAD
  timestamp: 2026-09-22T16:40:40.458974+00:00
- actor: claude-code
  id: 01m34zymhfg1nygvcg9cbz1vqm
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 7 validator runs attempted, 0 failed; 3 files reviewed (the two Swift sources and the test file); CHANGELOG.md and plan.md matched no validator; .kanban/ is in .reviewignore
    - next: move to done
  timestamp: 2026-09-22T16:42:28.271788+00:00
- actor: claude-code
  id: 01m34zz41mxfwvh19jfvv9zp6z
  text: |-
    ### finish iteration 1 — review clean
    - implement: changed — Sources/FoundationModelsSkills/Registry/SkillsRegistry+SlashCommands.swift, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Tests/FoundationModelsSkillsTests/SlashCommandProvidingTests.swift, plan.md, CHANGELOG.md
    - test: green — `swift test`, 564 tests in 53 suites passed, 0 failed, 0 skipped, no warning
    - commit: 9901b19
    - review: clean — no finding
  timestamp: 2026-09-22T16:42:44.148165+00:00
position_column: done
position_ordinal: ff9180
title: Render the slash-command text into $ARGUMENTS through the pipeline
---
## What

When a user runs `/name text`, the skill body must get `text`. Today `Sources/FoundationModelsSkills/Registry/SkillsRegistry+SlashCommands.swift` gives each command a `.prompt(template:)` body that holds the raw skill text. The harness renders that body with Stencil only. Pass 1 (`$ARGUMENTS`, `$N`, `$name`) and pass 2 (shell injection) never run.

Extras has a `SlashCommand.Body.rendered` case (FoundationModelsExtras commit 95a66e7, in the pinned revision). Use it.

The typed text goes into `call(id:arguments:)` as ONE argument. Thus `$ARGUMENTS` gets the full text as typed, and pass 1 splits the text into positions with shell-style quoting. For `/commit fix the bug`, `$ARGUMENTS` is `fix the bug` and `$0` is `fix`. For `/commit "fix the bug"`, `$0` is `fix the bug`. This is a decision, and a test pins it.

Files:

- `Sources/FoundationModelsSkills/Registry/SkillsRegistry+SlashCommands.swift`: `slashCommand(for:)` returns a `.rendered` body. The closure captures `detachedReader`, not `self`, and calls `reader.call(id:arguments:)` with the typed text as ONE argument. Text that is empty or whitespace only gives `[]`, thus no `ARGUMENTS:` fallback. Rewrite the file header: the §7.1 caveat is gone.
- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: remove `rawBody(id:)`. It has no other caller.
- `plan.md`, three places: §6, the "Harness delivery channel" bullet (replace the caveat with the `.rendered` behavior); §7.1, the channel diagram (the UI channel renders a `/` command through `call(id:arguments:)`); decision (Extras item `c2pad49` is delivered as `SlashCommand.Body.rendered`, and this package uses it).
- `CHANGELOG.md`: one "Changed" entry under Unreleased for the `.rendered` body.

The code and the tests of this task are in the working tree, uncommitted, except the unquoted-text test. The plan.md and CHANGELOG.md items are not done.

## Acceptance Criteria

- [x] Each `SlashCommand` from `commands(workingDirectory:)` carries a `.rendered` body.
- [x] The `commit` command rendered with the typed text `"fix the off-by-one bug"` (the quotation marks are part of the typed text) gives the same text as `registry.call(id: "commit", arguments: ["\"fix the off-by-one bug\""])`: the body holds `using the message: fix the off-by-one bug`, holds the typed text with its quotation marks, and holds no `$0` and no `$ARGUMENTS`.
- [x] The `commit` command rendered with the typed text `fix the bug` (no quotation marks) gives a body that holds `using the message: fix` and holds `fix the bug` on the `$ARGUMENTS` line.
- [x] The `commit` command rendered with an empty typed text gives the same text as a call with no arguments, and the body holds no `ARGUMENTS:`.
- [x] The `git-context` command body holds `on branch main, working tree clean` and no `` !` ``. The `env-report` command body holds `Shared Header` and no `{% include`.
- [x] `rg -in "coordination item|passes 1.2 ever run|completely inert|data only\)" plan.md Sources/` finds no line. `rg -n "rendered" CHANGELOG.md` finds a line under Unreleased.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/SlashCommandProvidingTests.swift`: `commandBodyRendersTheTypedTextAsTheOneArgumentOfCall`, `commandBodyWithNoTypedTextRendersWithNoArgumentsAppend`, `commandBodyRunsShellInjection`, `commandBodyRunsStencil` (in the working tree).
- [x] New in the same file: `commandBodyWithUnquotedTextGivesTheFirstWordToDollarZero`, typed text `fix the bug`, expects `using the message: fix` and `ARGUMENTS`-line text `fix the bug`.
- [x] `swift test` passes with no failure and no warning.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass. #skills