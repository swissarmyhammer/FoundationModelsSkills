---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0z8xma7gj8vqcb4g8hz6q01
  text: 'Research: `ResourceSupport.swift` line 120 is the `validIDs` filter in `unusableIDMessage(id:context:)`. The guard on line 121 returns the empty-catalog message when the filter gives no id. `ListResource`, `ReadResource` and `RunScript` all go through `ResourceIDLookup.withResolvedDirectory`, so one call through each of two operations covers the line. A registry over an empty temp root holds no skill, so `ResourceTestSupport.makeContext(roots: [emptyRoot])` gives the empty catalog. `ReadResourceTests` already calls `execute(in:)` directly and compares `.corrective(_:)`; the new tests use the same shape. Implementation: new file `Tests/FoundationModelsSkillsTests/ResourceIDLookupTests.swift` with two tests, one through `ListResource` and one through `ReadResource`, plus one shared helper that builds the empty-catalog context and returns the corrective message. `swift test --filter ResourceIDLookupTests`: 2 tests, 2 passed. `ResourceSupport.swift` is not changed.'
  timestamp: 2026-08-26T14:52:22.215054+00:00
- actor: claude-code
  id: 01m0z8xnn8rvd8w1sz8sjr2vj1
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsSkillsTests/ResourceIDLookupTests.swift (new, 2 tests; `swift test --filter ResourceIDLookupTests` passed 2 of 2)
    - next: run the full test suite, then commit and review
  timestamp: 2026-08-26T14:52:23.592868+00:00
- actor: claude-code
  id: 01m0z9v8t1r5n22mt6at3pqsqa
  text: |-
    ### test — green
    - evidence: swift test — 374 tests in 26 suites passed, 0 failed; 1 gated live-model test skipped (^tb86z9q). The first full run hung; a stale swift-test process (pid 25147) was killed and the run was repeated.
    - next: commit
  timestamp: 2026-08-26T15:08:33.473108+00:00
- actor: claude-code
  id: 01m0z9v9frzx2xpcssa7zh8k6q
  text: |-
    ### commit — changed
    - evidence: f2f0db5 test(resources): cover the empty-catalog corrective of ResourceIDLookup
    - next: review HEAD~1..HEAD
  timestamp: 2026-08-26T15:08:34.168464+00:00
- actor: claude-code
  id: 01m0z9xmaftwmf89z8dr946r5j
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — 0 findings (7 attempted, 0 confirmed, 0 refuted); 1 file reviewed: Tests/FoundationModelsSkillsTests/ResourceIDLookupTests.swift
    - next: move to done
  timestamp: 2026-08-26T15:09:50.799399+00:00
- actor: claude-code
  id: 01m0z9y2799men36w7jbaryda2
  text: |-
    ### finish iteration 1 — review clean, task moved to done
    - implement: changed — new file Tests/FoundationModelsSkillsTests/ResourceIDLookupTests.swift (2 tests through ListResource and ReadResource against an empty catalog)
    - test: green — swift test, 374 tests in 26 suites passed, 0 failed; 1 gated live-model test skipped (^tb86z9q)
    - commit: f2f0db5
    - review: clean — review sha HEAD~1..HEAD, 0 findings
  timestamp: 2026-08-26T15:10:05.033594+00:00
position_column: done
position_ordinal: b480
title: 'Add test for ResourceSupport.unusableIDMessage: the empty-catalog message'
---
`Sources/FoundationModelsSkills/Resources/ResourceSupport.swift`

Coverage: 96.9% (31/32 lines)

Uncovered line: 120

Add this test. Do not change `ResourceSupport.swift`.

Line 120 is the empty-catalog branch of
`unusableIDMessage(id:context:)`. The branch runs when no skill passes
`context.visibilityPredicate`. It gives the message "The skill id `<id>`
is not currently usable, and no skills are currently usable." The
existing tests always hold at least one usable skill, so they reach the
other branch only.

Write the test like this:

1. Build a registry that holds no skill. A registry whose every skill the
   visibility predicate rejects also works.
2. Call `ListResource(id: "missing").execute(in:)` against that context.
3. Make sure the result is `.corrective(_:)`, and that the message is
   exactly "The skill id `missing` is not currently usable, and no skills
   are currently usable."
4. Make sure the message does not hold "Currently usable ids:".

`ReadResource` and `RunScript` share this helper. One test through any
one of them covers the line. A second test through `ReadResource` proves
the message is shared, and is worth adding.

Put the test in `Tests/FoundationModelsSkillsTests/`, next to the
resource-operation tests that are there. #coverage-gap