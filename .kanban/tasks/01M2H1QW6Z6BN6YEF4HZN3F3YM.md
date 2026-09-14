---
assignees:
- claude-code
depends_on:
- 01M2H13QJ24K9102WB19Z3SQS1
position_column: todo
position_ordinal: '9980'
title: Add a skills-demo --marketplace mode
---
## What

marketplace.md MK6 (the `--marketplace` mode in `skills-demo`). The compiled demo shows the marketplace commands in the same way it shows `--chat` and `--watch`.

- `Examples/skills-demo/SkillsDemoMain.swift`: add a `--marketplace` flag next to `--chat` and `--watch`. It passes the remaining arguments to `MarketplaceCLI`, with the demo's fixture stack (`Examples/skills-demo/FixtureStack.swift`) as the config stack. The cache folder comes from `SKILLS_MARKETPLACE_CACHE`.
- Update the doc comment on the demo entry point that lists the modes.

- [ ] The `--marketplace` flag and the dispatch
- [ ] The doc comment
- [ ] The subprocess test

## Acceptance Criteria
- [ ] `skills-demo --marketplace list` runs as a subprocess with `SKILLS_MARKETPLACE_CACHE` set to a temporary folder, exits with 0, and prints the configured sources
- [ ] The existing `SkillsDemoTests` cases still pass

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillsDemoTests.swift`: a subprocess case for `--marketplace list`, and one for an unknown subcommand (non-zero exit)
- [ ] Run `swift test --filter SkillsDemoTests`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace