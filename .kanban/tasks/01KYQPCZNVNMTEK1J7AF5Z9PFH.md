---
position_column: todo
position_ordinal: a180
title: 'Resource op fidelity: durationMs, cap/hidden-file tests, bounded read'
---
## What
Small §7.3 fidelity holes in the resource ops and their tests:

1. **`durationMs` truncates to whole seconds**: `Int(components.seconds * 1000)` drops attoseconds (`Resources/ScriptProcessRunner.swift:96`) — a 400 ms script reports `0`, a 1.9 s script reports `1000`. Fix: include the sub-second term. No test asserts `durationMs` anywhere — add one (bounded-range assertion) including in the golden `RunScriptResult` case (`RunScriptTests.swift:200-205`).
2. **The 100-row cap is never asserted**: the >100-file test checks `total: 150` but not that `resources.count == 100` (`ResourceOpsTests.swift:186-204`; truncation at `ListResource.swift:106`). Add the row-count assertion.
3. **Hidden-file skipping untested** (§7.3 mandates it; only the symlink half is covered). Add a dot-file fixture case to `ResourceOpsTests`.
4. **`read resource` materializes the whole file before refusing**: full `Data` read then `data.count` (`ReadResource.swift:140-144`). Acceptable for the corrective's byte size, but bound the cost: read incrementally/stat first so a multi-GB binary asset is not fully loaded to produce a refusal.

## Acceptance Criteria
- [ ] A ~300 ms script reports `durationMs` in [200, 2000), asserted in tests
- [ ] `list resource` over 150 files returns exactly 100 rows with `total: 150`
- [ ] A `.hidden` file is absent from `list resource` output (test)
- [ ] `read resource` on a large binary refuses without reading the full file into memory (stat-based size in the corrective)

## Tests
- [ ] Extend `RunScriptTests.swift` (durationMs + golden), `ResourceOpsTests.swift` (cap rows, hidden file, large-binary refusal)
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.