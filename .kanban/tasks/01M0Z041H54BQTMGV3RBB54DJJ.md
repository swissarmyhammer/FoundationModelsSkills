---
assignees:
- claude-code
position_column: todo
position_ordinal: 8f80
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