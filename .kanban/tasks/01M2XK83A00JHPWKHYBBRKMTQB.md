---
assignees:
- claude-code
position_column: todo
position_ordinal: '9380'
title: The demo chat mode writes to standard out with print
---
## What

`Examples/skills-demo/ChatMode.swift` writes four lines with `print(...)`:

- `printUnavailable(reasonText:)` — the "Foundation Models unavailable" line.
- The `catch` of the live validation — "Live validation failed: ...".
- The `[OK]`/`[MISS]` line of each scripted turn.
- The `[ERROR]` line of a scripted turn that throws.

The rule `code-hygiene/disallowed-constructs-swift` -- `no_direct_standard_out_logs` -- forbids `print(…)`, `debugPrint(…)`, `dump(…)` and `_printChanges()` in code that is committed. The review of card ^977h3a0 named the same cause in `WatchMode.swift`, and that file now writes through `FileHandle.standardOutput`, the way `SkillsDemoMain` writes the output of a mode. `ChatMode.swift` was not in the scope of that finding, thus it still holds `print`.

## Acceptance Criteria

- [ ] `Examples/skills-demo/ChatMode.swift` holds no `print(…)`, `debugPrint(…)`, `dump(…)` or `_printChanges()`.
- [ ] Each line it wrote before goes to standard output with the same text.
- [ ] `WatchMode`, `ChatMode` and `SkillsDemoMain` share one writer instead of three copies, or the duplication is shown to be none.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

#skills #code-hygiene
