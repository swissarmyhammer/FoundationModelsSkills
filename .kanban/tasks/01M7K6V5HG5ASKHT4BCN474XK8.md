---
assignees:
- claude-code
position_column: done
position_ordinal: ffb880
title: Only read-only skills operations are inferable (Extras 2b8ee77)
---
foundationmodelsextras-0a and testudoapp-75 ask for this. Extras 2b8ee77 runs an op-less call only for an operation that declares `isInferable` (default false). Four tests of InferredOpPlainTextTests fail against it.

Do:
- `isInferable = true` on the read-only operations: SearchSkill, ListSkill, UseSkill, ListResource, ReadResource. No write operation is inferable.
- `PlainTextMarker` passes on `Target.isInferable`.
- docs/operations.md and the resolver doc state the new rule.

Decision: `use skill` stays inferable also in `.open` mode. Its body can run the shell commands of the skill, the same as for a call that names `use skill` (^vm78pnz).

Acceptance: an op-less call that fits only a write operation runs nothing (guard tests); `swift test` passes.