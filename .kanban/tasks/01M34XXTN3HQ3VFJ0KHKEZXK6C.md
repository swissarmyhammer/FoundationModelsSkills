---
position_column: todo
position_ordinal: '80'
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

- [ ] Each `SlashCommand` from `commands(workingDirectory:)` carries a `.rendered` body.
- [ ] The `commit` command rendered with the typed text `"fix the off-by-one bug"` (the quotation marks are part of the typed text) gives the same text as `registry.call(id: "commit", arguments: ["\"fix the off-by-one bug\""])`: the body holds `using the message: fix the off-by-one bug`, holds the typed text with its quotation marks, and holds no `$0` and no `$ARGUMENTS`.
- [ ] The `commit` command rendered with the typed text `fix the bug` (no quotation marks) gives a body that holds `using the message: fix` and holds `fix the bug` on the `$ARGUMENTS` line.
- [ ] The `commit` command rendered with an empty typed text gives the same text as a call with no arguments, and the body holds no `ARGUMENTS:`.
- [ ] The `git-context` command body holds `on branch main, working tree clean` and no `` !` ``. The `env-report` command body holds `Shared Header` and no `{% include`.
- [ ] `rg -in "coordination item|passes 1.2 ever run|completely inert|data only\)" plan.md Sources/` finds no line. `rg -n "rendered" CHANGELOG.md` finds a line under Unreleased.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/SlashCommandProvidingTests.swift`: `commandBodyRendersTheTypedTextAsTheOneArgumentOfCall`, `commandBodyWithNoTypedTextRendersWithNoArgumentsAppend`, `commandBodyRunsShellInjection`, `commandBodyRunsStencil` (in the working tree).
- [ ] New in the same file: `commandBodyWithUnquotedTextGivesTheFirstWordToDollarZero`, typed text `fix the bug`, expects `using the message: fix` and `ARGUMENTS`-line text `fix the bug`.
- [ ] `swift test` passes with no failure and no warning.

## Workflow

- Use `/tdd` — write failing tests first, then implement to make them pass. #skills