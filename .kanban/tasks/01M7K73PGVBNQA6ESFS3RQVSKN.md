---
assignees:
- claude-code
position_column: done
position_ordinal: ffb980
title: use skill is inferable only in ToolMode.sandboxed
---
testudoapp-75 decides: a guessed call must never have a side effect. In `ToolMode.open` the body of a skill can run its shell commands, thus an op-less `{"id"}` must not run `use skill` there. The call gets the corrective that tells the model to name `use skill`.

Do:
- `UseSkill` keeps `isInferable = false`. The internal `InferableUseSkill` (same verb, noun, parameters and work, `isInferable = true`) is in place of it in `ToolMode.sandboxed`.
- `ListResource` is not inferable. Else `{"id"}` in `.open` runs `list resource` in place of the corrective.
- docs/operations.md and the resolver doc state the rule.

Acceptance: guard tests in `.open` (plain and in `arguments`) give the corrective; the op-less tests pass in `.sandboxed`; `swift test` passes.