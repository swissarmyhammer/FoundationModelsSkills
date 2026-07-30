---
comments:
- actor: claude-code
  id: 01kyrk18vgcnmncxk8q9mhc19w
  text: |-
    All four §7.3 fidelity holes closed:

    1. **`durationMs` truncated to whole seconds.** `Int(elapsed.components.seconds * 1000)` dropped the attoseconds remainder entirely — a 400ms script reported `0`. Fixed to include the sub-second term (`attoseconds / 1_000_000_000_000_000`). Pinned by a real `sleep 0.3` fixture asserting `durationMs` lands in `[200, 2000)`, plus a bounded assertion in the golden `RunScriptResult` test.

    2. **`list resource`'s 100-row cap was asserted only via `total: 150`**, never confirming `resources.count` was actually truncated to 100 rather than silently returning all 150. Added the row-count assertion (counts `"path":` occurrences in the raw JSON).

    3. **Hidden-file skipping had no test** — only the symlink-escape half of §7.3's passive-read exclusions was covered (the `.skipsHiddenFiles` option itself was already correct, just unverified). Added a dotfile fixture case.

    4. **`read resource` fully materialized a file via `Data(contentsOf:)` before ever checking UTF-8 validity** — a multi-GB binary asset would be loaded whole just to produce a refusal. Now stats the file first (`URL.resourceValues([.fileSizeKey])`, no content read) and refuses immediately, citing the stat'd size, for anything over 1,000,000 bytes. Pinned with a 2MB fixture.

    Fixing `durationMs`'s precision exposed a pre-existing test design flaw: `SkillsCLITests.scriptRunVerbRoundTripsToTheIdenticalModelDispatchOutput` asserted full JSON equality between two independent subprocess executions (the CLI path and the model path), which only ever passed because the truncation bug coincidentally zeroed both out for this fixture's sub-second script. Fixed at the root: strip the genuinely time-variant `durationMs` field before comparing, while still asserting both payloads carry one.

    Three review rounds on this task's checkpoints:
    - Round 1: `writeMinimalSkillFile` duplicated near-identically between `ResourceOpsTests.swift`/`RunScriptTests.swift` → extracted into shared `ResourceTestSupport.swift`.
    - Round 2: `makeContext` also duplicated between the same two files (same fix pattern) → consolidated into `ResourceTestSupport.makeContext(roots:policy:)`; plus a path-separator guard on `writeExecutableShebangScript`'s `name` param. (Two other findings in this round — asking to document `- Parameter x:` doc comments by external label rather than internal name — were declined: this project's own pre-existing production code, `SkillWatcher.swift`'s `watchTree(at directory: URL)`, already documents by internal name, matching Swift's official API Design Guidelines/DocC convention; applying the suggested change would have made these two files the only ones in the codebase using the non-standard convention.)
    - Round 3: the same guard pattern requested for `writeMinimalSkillFile`'s `id` param, `scriptsDirectory`'s `id` param, and `allowedTools` (YAML-structural characters) → applied, even though every call site in both files passes a fixed literal (no real untrusted-input reachability) — cheap and mechanical, so applied as asked.

    Final review: 0 findings, 14/14 validators attempted, 0 failed. 311/311 tests green, confirmed stable across multiple consecutive full-suite runs (occasional flakes in *pre-existing*, unrelated watcher/reload tests under background system load — not a regression from this work).
  timestamp: 2026-07-30T04:03:02.640965+00:00
position_column: done
position_ordinal: a280
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