---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7dyg5qbh1cg0x4btzr7c3pd
  text: |-
    ### Research

    - Extras fee9093 (`.build/checkouts/FoundationModelsExtras/Sources/Operations/OperationResolver.swift`, `OperationTool.swift`): `OperationTool.resolve` unwraps a lone `arguments` object, then `matchedOpString` tries the explicit `op`, then `inferOp`, then key-fit inference, with `defaultOp` settling a tie among the fitting ops. The resolved op is private: no public API gives it.
    - On the `skills` tool, `{"id"}` fits `use skill`, `list resource` AND `remove skill` (id required, layer optional). `add skill` and `edit skill` need `content`. `{"arguments": [], "id"}` fits only `use skill` (`run script` needs `path`).
    - RED (before the change): `{"id"}` and `{"arguments": {"id"}}` answered "Unknown operation"; `perform({"id"})` threw it; `{"arguments": [], "id"}` already dispatched to `use skill` in Extras but answered a JSON string, because the old `PlainTextOperations` markers declared no parameters and key-fit inference cannot fit them. `{"arguments": {"op": "use skill", "id"}}` already passed: the matcher's own `OperationTool` unwraps too.
    - No Extras change is needed for the empty-`arguments` case: an empty array decodes as an empty argument list.
  timestamp: 2026-11-14T21:13:02.955684+00:00
- actor: claude-code
  id: 01m7dyg5qbf51fpxzpta6de2ra
  text: |-
    ### Implementation

    - `SkillsTool.makeResolver()` passes `defaultOp: UseSkill.opString`.
    - `PlainTextOperations` now mirrors EVERY operation of the fused tool (`init(mirroring:resolver:)`, built from `operationTool.operations`, so the open/sandboxed op set follows): one `PlainTextMarker<Target>` per op, opened from `AnyOperation.definitionType`. A marker carries `Target.parameterMetadata` and its `execute` returns `Target.opString`. The matcher, with the fused tool's resolver, therefore resolves to the same op as the dispatch by every rule (aliases, unwrap, key-fit inference, `defaultOp`). The answer is decoded when that op is in `plainTextOpStrings`.
    - Why the whole set and not only the plain-text markers with parameters: inference depends on the whole candidate set (`{"id"}` is a tie that `defaultOp` settles among the ops that fit), so a subset could resolve differently from the dispatch.
    - Documented in `docs/operations.md` ("A payload with no `op`") and the type docs.
  timestamp: 2026-11-14T21:13:02.955684+00:00
- actor: claude-code
  id: 01m7dyg5qbctjpc6b2yp488e9g
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsSkills/Operations/PlainTextOperations.swift, Sources/FoundationModelsSkills/Operations/SkillsCatalogTool.swift, Sources/FoundationModelsSkills/Operations/SkillsTool.swift, docs/operations.md, Tests/FoundationModelsSkillsTests/InferredOpPlainTextTests.swift. `swift build --build-tests` exit 0; `swift test` 838 tests in 71 suites passed; the only warning is the mlx-swift build-system "missing creator for mutated node", outside the touched code.
    - next: /review
  timestamp: 2026-11-14T21:13:02.955684+00:00
- actor: claude-code
  id: 01m7mr20d0ev5a78f9znpfs8nq
  text: |-
    ### Check at HEAD 3043498 (after 2d716b6 isInferable and the revert of 6df83ad)

    - Requirement 1: `SkillsTool.makeResolver()` passes `defaultOp: UseSkill.opString`. Its doc says that `{"id"}` fits `use skill`, `list resource` and `remove skill`, that `remove skill` is not inferable, and that `defaultOp` settles the tie on `use skill`. Correct.
    - Requirement 2: `PlainTextOperations` mirrors each operation of the fused tool. `PlainTextMarker.isInferable` passes on `Target.isInferable`, thus the matcher infers over the same candidate set as the dispatch. `UseSkill.isInferable` is `true` with no `ToolMode` condition, thus the inference is the same in `ToolMode.open` and `ToolMode.sandboxed`. Correct.
    - Requirement 3: `InferredOpPlainTextTests` has `{"id"}` (call and perform), `{"arguments": [], "id"}`, `{"arguments": {"op": "use skill", "id"}}`, `{"arguments": {"id"}}`, and explicit `use skill` and `list resource` (also wrapped). Correct.
    - docs/operations.md "A payload with no `op`" states the current rule: only `isInferable` operations are inferred, `remove skill` fits `{"id"}` but is not a candidate, `defaultOp` gives `use skill`. Correct.
    - Requirement 4: `swift build --build-tests` complete; `swift test` 903 tests in 73 suites passed. The only warning is the mlx-swift build-system "missing creator for mutated node", outside the touched code.
    - Note: the type doc of `PlainTextOperations` and the doc of the test suite say that `{"id"}` "fits `use skill` and `list resource`". That is the set of inferable operations that fit. docs/operations.md and `makeResolver()` give the full statement. No code change.

    ### implement — no-change
    - evidence: no file changed. `swift build --build-tests` exit 0; `swift test` 903 tests in 73 suites passed.
    - next: /review
  timestamp: 2026-11-17T12:35:08.320411+00:00
position_column: doing
position_ordinal: '80'
title: 'SK-10: an op-less skills call runs use skill, and its answer stays plain text'
---
## What

FoundationModelsExtras fee9093 (^vm78pnz) lets `OperationTool` infer a missing `op` from the payload keys, unwraps a lone `arguments` payload, and adds `OperationResolver(defaultOp:)` as the tie-break when several ops fit. The Recursive Flint model calls the `skills` tool with `{"id": "kanban"}`, and with `{"arguments": [], "id": "kanban"}`, and no `op`. On this tool `{id}` fits `use skill`, `list resource` and `remove skill`.

## Requirements

- [x] `SkillsTool.makeResolver()` passes `defaultOp: "use skill"` (as `UseSkill.opString`).
- [x] `PlainTextOperations` finds the op that the fused tool resolves, so an inferred `use skill` (and any plain-text op reached by inference or by the `arguments` unwrap) still answers plain text, not a JSON string. Document the approach.
- [x] Hermetic tests, written first and seen to fail:
  - `{"id": <skill>}` on the real skills tool dispatches to `use skill` and answers plain text;
  - `{"arguments": [], "id": <skill>}` does the same;
  - `{"arguments": {"op": "use skill", "id": <skill>}}` does the same;
  - explicit ops are unchanged.
- [x] `swift build --build-tests` and `swift test` green with zero warnings in the touched code. #sk-10 #operations