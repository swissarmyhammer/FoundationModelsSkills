---
assignees:
- claude-code
position_column: todo
position_ordinal: '9280'
title: The skills marketplace depends on FoundationModelsSkills main, which has no marketplace code yet
---
## What

`/Users/wballard/github/swissarmyhammer/skills` declares `.package(url: "git@github.com:swissarmyhammer/FoundationModelsSkills.git", branch: "main")`. A fresh `swift package resolve` gives the revision `4a4befc`, which is the head of the **published** `main`.

All the marketplace work of FoundationModelsSkills is in nine local commits (`db1aedc` to `7876a31`) that nobody pushed. Thus:

- The CI of `swissarmyhammer/skills` builds against a client that holds no marketplace code.
- The `skills marketplace add` command that the new `README.md` shows does not exist in the published client.
- A `v1.0.0` tag on the marketplace names a release that the published client cannot read.

## What to decide

A person must decide to push the FoundationModelsSkills marketplace commits to `origin/main`. The `/finish` runs made the commits local only, because the instruction was to never push.

- [ ] Decide whether to push the FoundationModelsSkills marketplace commits
- [ ] After the push, resolve `../skills` again and confirm it gives the new head
- [ ] Confirm the CI of `swissarmyhammer/skills` is green against the new client

## Acceptance Criteria
- [ ] `swift package resolve` in `../skills` gives a FoundationModelsSkills revision that holds the `skills marketplace` CLI
- [ ] The README instruction of `../skills` agrees with the published client

## Tests
- [ ] Run `swift test` in `../skills`; expect green against the new client
- [ ] Read the CI result of the `swissarmyhammer/skills` repository on GitHub #cross-repo