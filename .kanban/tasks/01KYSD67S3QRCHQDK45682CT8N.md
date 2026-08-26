---
comments:
- actor: claude-code
  id: 01m0z0a03nxse3hcrttnzwrwd6
  text: |-
    ### implement — research
    - `ReadResource.execute(in:)` (Sources/FoundationModelsSkills/Resources/ReadResource.swift:137-157) does a stat, refuses files over `maxReadableByteSize` (1,000,000 bytes), then reads the full file with `Data(contentsOf:)` and validates UTF-8 on the full `Data`.
    - `slice(text:...)` splits the full `String` with `splitIntoLines` (ResourceSupport.swift:18). `ScriptProcessRunner` is the only other user of `splitIntoLines`.
    - `splitIntoLines` splits on the Swift `Character` "\n". Swift reads "\r\n" as one `Character`, so a CRLF file is one line there. A byte scanner splits at each LF byte. This is a known difference. The new scanner defines a line as a run of bytes that ends at a LF byte (0x0A).
    - The binary fixture `logo.bin` starts with byte 0x89. A UTF-8 validator rejects it at the first byte, so the refusal reads one chunk only.
    - Test `readResourceOnAnOversizedFileRefusesFromItsStatedSizeWithoutReadingIt` asserts the 1 MB refusal. The card removes that behavior, so that test changes to a paging test.
    - Plan: new internal `LineWindowReader` (streams 64 KiB chunks, counts LF lines, validates UTF-8 across chunk boundaries with a small state machine, keeps only the requested window). `ReadResource` uses it. `totalLines` stays exact because the scan reads to EOF (streamed, not materialized).
  timestamp: 2026-08-26T12:21:50.325945+00:00
- actor: claude-code
  id: 01m0z0b1at9jycc3a372ajb4wx
  text: |-
    Research done.

    - `ReadResource.execute(in:)` stats the file, refuses a file over `maxReadableByteSize` (1,000,000 bytes), then reads the whole file with `Data(contentsOf:)` and decodes it with `String(data:encoding:.utf8)`. `slice(text:...)` splits the full string with `splitIntoLines`.
    - `splitIntoLines` (ResourceSupport.swift) is also used by `ScriptProcessRunner`. Its doc comment says `ReadResource` shares it. After this change `ReadResource` will not use it, so that doc comment must change.
    - Discovery: `splitIntoLines` splits a Swift `String` on the `"\n"` character. A CRLF pair is one grapheme in Swift, so a CRLF file is one line today. The new byte-level scan splits on the 0x0A byte. A CRLF file will page by line with the new code.
    - The test `readResourceOnAnOversizedFileRefusesFromItsStatedSizeWithoutReadingIt` pins the defect this card removes (a 2 MB UTF-8 file is refused). That test will be replaced.
    - Platform floor is macOS 27, so `FileHandle.read(upToCount:)` is available for the streaming read.

    Plan for the semantics:
    - Read the file in fixed chunks. Validate UTF-8 per chunk, with a carry of the incomplete tail bytes (at most 3) to the next chunk. Split lines on the 0x0A byte. Count all lines for an exact `totalLines`. Keep only the lines in the requested window.
    - Keep a content byte budget per call (1,000,000 bytes, the old constant, renamed). When the next window line does not fit the budget, stop and return the lines that fit; `end` reports the last line returned. When the first window line alone exceeds the budget, return a corrective that names the line.
    - Keep the non-UTF-8 corrective. Its byte size comes from stat, not from the bytes read.
    - Memory per call: one chunk, the carry, and the window (bounded by the budget).
  timestamp: 2026-08-26T12:22:24.346268+00:00
- actor: claude-code
  id: 01m0z0kbhtxn040bp0k5t4d05p
  text: |-
    ### BLOCKER — two agents work this task at the same time
    - A second `claude` session (cwd is this repository) writes the same files at the same time as this session. Its comment "Research done." (12:22:24 UTC) plans a different design: a 1,000,000-byte content budget per call, and a corrective for a single line over the budget.
    - That session rewrote `Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift` at 12:23 UTC (tests `readResourceCutsAWindowAtTheContentByteBudget...`, `readResourceOnASingleOversizedLineDrawsACorrectiveNamingTheLine`).
    - This session wrote `Sources/FoundationModelsSkills/Resources/LineWindowReader.swift` (new), rewrote `Sources/FoundationModelsSkills/Resources/ReadResource.swift`, and edited `ResourceSupport.swift` and `README.md` at 12:24-12:25 UTC. This design has no content budget: it streams 64 KiB chunks, keeps only the window, and refuses non-UTF-8 at the first invalid byte.
    - The two designs conflict. Each write replaces the other's work. A build or a commit now mixes two implementations and gives a false result.
    - This session stops here. It does not revert its files, so no work is lost twice. A person must pick one design, stop the other session, and start the work again from one working tree.
    - Files this session touched: `Sources/FoundationModelsSkills/Resources/LineWindowReader.swift`, `Sources/FoundationModelsSkills/Resources/ReadResource.swift`, `Sources/FoundationModelsSkills/Resources/ResourceSupport.swift`, `README.md`. It did not change the test file.
  timestamp: 2026-08-26T12:26:56.954053+00:00
- actor: claude-code
  id: 01m0z0kea0zx4ghzrqxhkk669x
  text: |-
    ### finish iteration 1 — stuck (blocker: a second session edits the same task and files at the same time)
    - implement: stuck — 4 files written (LineWindowReader.swift new, ReadResource.swift, ResourceSupport.swift, README.md); the test file was rewritten by the other session with a conflicting design before this session could edit it
    - test: not run
    - commit: none
    - review: not run

    step: implement
    outcome: stuck
    evidence: concurrent writer on ResourceOpsTests.swift (12:23 UTC) with a conflicting design; see the BLOCKER comment
    task: ^682ct8n
  timestamp: 2026-08-26T12:26:59.776048+00:00
- actor: claude-code
  id: 01m0z0st4h29dtjarwbf41fntj
  text: |-
    Implementation record (this session, dispatched by the user with "implement in Resources/ReadResource.swift").

    What was done, in TDD order:
    1. RED: replaced the test that pinned the 1 MB refusal with eight tests in `ResourceOpsTests.swift`: first/middle/last windows over a 5.2 MB, 100,000-line fixture; a window past the last line; a window cut by the content byte budget (`end` = 3 of 10 lines); a single 2 MB line (corrective names line 1); invalid UTF-8 found after the first chunk and after the window (corrective with the stat'd size); multi-byte characters that straddle chunk boundaries. All eight failed on the old "exceeding the 1000000-byte limit" corrective; the fifteen other tests passed.
    2. GREEN: rewrote `ReadResource.swift`. `execute(in:)` stats the file, then a file-private `LineWindowScanner` streams it with `FileHandle.read(upToCount:)` in 65,536-byte chunks, validates UTF-8 per chunk (a carry of at most 3 bytes for a scalar split by a chunk boundary, `String(validating:as:)` on the complete prefix), splits lines at the 0x0A byte, counts every line, and keeps only the window lines up to `maxContentBytesPerCall` (1,000,000). A window the budget cuts stops at the last line that fits; a first window line over the budget throws out early with `oversizedLine`; invalid bytes throw out early with `nonUTF8`. `totalLines` is exact.
    3. Docs: the op doc comment states the paging semantics; the `end` parameter description and `ReadResourceResult.end` doc state the budget cut; README "Known deviations" has a bullet for the byte budget; the `splitIntoLines` doc no longer claims `ReadResource` shares it.
    4. `swift test`: 325 tests in 23 suites passed, exit 0. `grep` finds no `Data(contentsOf:)` or `String(data:)` under `Sources/`.

    Discoveries:
    - The first version of the late-binary test used one 1,200,000-byte line. The budget corrective fired before the scan reached the invalid bytes. The fixture now spreads the prefix over 12,000 lines of 100 bytes.
    - The README op-table row for `read resource` was already rewritten by the other session (it says "no size limit", CRLF note). This session did not change that row. It does not mention the byte budget; the "Known deviations" bullet does.

    Conflict state, for the person who decides:
    - `Sources/FoundationModelsSkills/Resources/LineWindowReader.swift` (untracked) is the other session's design. Nothing references it. With this session's `ReadResource.swift` it is dead code. This session did not delete it.
    - The other session's `ReadResource.swift` was replaced by this session's whole-file write at 07:27 local. Its content is not recoverable from the working tree.
    - Option A: delete `LineWindowReader.swift`, keep this tree (green, all card criteria met).
    - Option B: keep the other design; its `ReadResource.swift` must be written again, and the eight tests here must change (no byte budget, no oversized-line corrective).
  timestamp: 2026-08-26T12:30:28.497125+00:00
- actor: claude-code
  id: 01m0z0t5qpzkprcxt4gcrak9a0
  text: |-
    ### implement — stuck
    - evidence: 6 files changed — Sources/FoundationModelsSkills/Resources/ReadResource.swift, Sources/FoundationModelsSkills/Resources/ResourceSupport.swift, Sources/FoundationModelsSkills/Resources/ResourceRow.swift, README.md, Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift, plus the other session's untracked Sources/FoundationModelsSkills/Resources/LineWindowReader.swift (unreferenced). `swift test`: 325 tests in 23 suites passed, exit 0, no Swift source warning.
    - blocker: two sessions worked this card at the same time. The other session's design survives only as `LineWindowReader.swift`, which nothing references. A person must pick a design: Option A deletes `LineWindowReader.swift` and keeps this tree; Option B discards this design. This session does not delete another session's file.
    - next: a person picks Option A or B. For Option A, delete the file and run `/review`.

    step: implement
    outcome: stuck
    evidence: tree is green with this session's design; the other session's `LineWindowReader.swift` is unreferenced and needs a decision
    task: ^682ct8n
  timestamp: 2026-08-26T12:30:40.374156+00:00
- actor: claude-code
  id: 01m0z0vmnvhhmx7q40cr80p10m
  text: |-
    ### finish — blocker resolved (Option A)
    - The blocker is not a rule conflict. The second writer stopped at 12:27 UTC. No writer is active now.
    - The working tree has one complete design (`ReadResource.swift` with the file-private scanner) and it is green.
    - `Sources/FoundationModelsSkills/Resources/LineWindowReader.swift` was untracked and not referenced. It is deleted.
    - The `stuck` tag is removed. The loop continues with the `test` step.
  timestamp: 2026-08-26T12:31:28.443689+00:00
- actor: claude-code
  id: 01m0z0w95rnbxm8tw1c2f5sjsy
  text: |-
    ### Blocker resolved
    - The orchestrator identified the second writer: it was an orphaned implementer sub agent from the orchestrator's own first launch, not an outside person. It has finished and is stopped. No other agent edits the tree now.
    - Decision: keep the design in the tree now (the implementer's `ReadResource.swift` with the 1,000,000-byte content budget, the file-private `LineWindowScanner`, and the eight new tests). That tree was green: 325 tests passed.
    - This session deleted its stray `Sources/FoundationModelsSkills/Resources/LineWindowReader.swift` (nothing referenced it) and aligns `README.md` to the one chosen design. The `stuck` tag is removed. The loop continues from the test step.
  timestamp: 2026-08-26T12:31:49.432431+00:00
position_column: doing
position_ordinal: '80'
title: 'ReadResource: page large text resources instead of 1 MB hard refusal'
---
## What
New defect introduced by the bounded-read fix (ef80be5): `read resource` now stat-checks size and HARD-REFUSES any file over 1,000,000 bytes (`Resources/ReadResource.swift:126, 145-148`). §7.3's paging contract — "at most 500 lines per call; `totalLines` tells the model to page via `start`/`end`" — is thereby unsatisfiable for any legitimate UTF-8 text resource over 1 MB (large changelogs, logs, CSVs) that was previously pageable. Undocumented and untested.

Fix: keep memory bounded WITHOUT refusing large text — read incrementally (streaming line scan) up to the requested `start`/`end` window plus enough to compute `totalLines` cheaply (or report `totalLines` as a lower bound when scanning is capped, with the cap documented). Preserve the stat-first refusal only for the non-UTF-8/binary corrective path (its byte size can come from stat, no full materialization). Choose and document exact semantics on the op; note them in README's op table if they deviate from §7.3's letter.

## Acceptance Criteria
- [ ] A 5 MB UTF-8 text fixture pages successfully with correct slice content for windows at the start, middle, and end
- [ ] Memory stays bounded (no full-file `Data(contentsOf:)` for text reads — verify by code inspection/greppable absence + a large-file test that completes quickly)
- [ ] Binary refusal still stat-based, no full read
- [ ] Chosen semantics documented on the op and in README

## Tests
- [ ] Extend `Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift` — large-text paging matrix; binary refusal unchanged
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.