---
assignees:
- claude-code
position_column: todo
position_ordinal: 9a80
title: 'MarketplaceCache: let a ref name hold a slash again, one safe component at a time'
---
## Why

`MarketplaceCache.validated(ref:)` now refuses every ref that holds a `/`, because the path-traversal findings on card ^rnerbsj asked for one validator that refuses a path separator. Git permits a branch name with a `/` in it, for example `feature/login`. A user who writes `ref: feature/login` in `marketplaces.yaml` now gets an error.

## What

- Split the ref on `/` and check each part with the same rules, in place of a refusal of the whole value.
- Keep the refusal of an empty part, of `..`, of a part that starts with a dot, and of a control character.
- `write(sha:toValidatedRef:)` must make the folders of the file again.

## Tests
- A ref `feature/login` writes `refs/feature/login` and reads back.
- `../x`, `a/../b`, `/etc/passwd`, and `.hidden/x` stay refused.

#marketplace