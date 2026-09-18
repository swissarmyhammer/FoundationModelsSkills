---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2qzq2h5afzbtm06mqjsfb8g
  text: |-
    ### finish — stuck, a person must decide

    This card asks a person to decide whether to push the FoundationModelsSkills marketplace commits to origin/main. The loop cannot decide it.

    The user approved three network steps by name: create swissarmyhammer/skills as a public repository and push it, push the ACPAgent fix, and tag v1.0.0. All three are done. That approval did not name a push of FoundationModelsSkills, and an approval of one action does not carry to another. Thus the loop stops here.

    The state, as measured:
    - FoundationModelsSkills holds 10 local commits that nobody pushed, db1aedc through 441ba4d.
    - `swift package resolve` in ../skills gives FoundationModelsSkills at 4a4befc, the head of the published main.
    - Thus the CI of swissarmyhammer/skills builds a client that holds no marketplace code, and the `skills marketplace add` line of the new README names a command the published client does not have.
    - The CI of swissarmyhammer/skills is green on all six pushes, because the marketplace tests need only SkillsRegistry, which the old client has.

    The card stays in todo. It needs one word from a person: push, or do not push.
  timestamp: 2026-09-17T15:28:12.837340+00:00
position_column: done
position_ordinal: eb80
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