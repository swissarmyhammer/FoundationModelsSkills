---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0z6ae0hr5xxpq40dhjbx38h
  text: |-
    Research result for item 2 (lines 45-48, the `dataCorrupted` throw):

    A probe test decoded these YAML shapes directly into `FrontmatterValue` with `YAMLDecoder`: `2026-08-26T00:00:00Z`, `2026-08-26`, `12:30:00`, `!!binary ...`, `!custom foo`, `.inf`, `.nan`, `0x1F`, `0o17`, `1_000`, a mapping with a mapping key, and a mapping with a sequence key. None of them throws. Yams decodes each scalar as `String` when `Bool`, `Int` and `Double` do not accept it (a timestamp gives `.string`, not a `Date`). Each sequence decodes as `.array`. Each mapping decodes as `.dictionary` (keys that are not scalars are dropped, the decode does not fail).

    Conclusion: no YAML input reaches lines 45-48 through Yams. The lines are unreachable. The source is not changed. A test `metadataBareTimestampDecodesAsString` records this behavior.

    Item 3 note: `arguments: 42` decoded through `init(from:)` is dropped by `validatedTopLevelArguments`, so `arguments` gives `[]` through `argumentsRaw == nil`, not through line 82. To reach line 82, the test also builds `SkillFrontmatter(argumentsRaw:)` with the public initializer for `.int`, `.double`, `.bool`, `.dictionary` and `.null`, and checks that `arguments` is `[]`. No `@testable import` is necessary.

    The probe test file was deleted after the research.
  timestamp: 2026-08-26T14:06:56.017664+00:00
- actor: claude-code
  id: 01m0z6afqnr2tyzeagt7vkkngs
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsSkillsTests/FrontmatterDecoderTests.swift (4 new tests: metadataFloatDecodesAsDouble, metadataBareTimestampDecodesAsString, bareIntegerArgumentsDecodesAndTokenizesToEmpty, nonTokenizableArgumentsRawTokenizesToEmpty x5 cases). `swift test --filter FrontmatterDecoderTests`: 32 tests passed.
    - next: test
  timestamp: 2026-08-26T14:06:57.781886+00:00
position_column: doing
position_ordinal: '80'
title: 'Add tests for SkillFrontmatter: the .double decode branch and the non-tokenizing default'
---
`Sources/FoundationModelsSkills/Frontmatter/SkillFrontmatter.swift`

Coverage: 95.8% (159/166 lines)

Uncovered lines: 37, 45-48, 82

Add these tests. Do not change `SkillFrontmatter.swift`.

- [x] 1. Line 37 -- the `.double(value)` branch of
   `FrontmatterValue.init(from:)`.
   No test decodes a YAML float. Write a SKILL.md whose frontmatter holds
   a float value, for example `metadata:` with a key set to `1.5`. Decode
   it. Make sure the value is `.double(1.5)`, not `.int` and not
   `.string`.

- [x] 2. Lines 45-48 -- the `DecodingError.dataCorrupted` throw at the end of
   `FrontmatterValue.init(from:)`.
   The branch runs for a YAML shape that none of the seven earlier
   branches accept. Find a value Yams gives that is not null, bool, int,
   double, string, array or dictionary. A YAML timestamp
   (`2026-08-26T00:00:00Z` without quotation marks) is one candidate,
   because Yams decodes it as a `Date`. Make sure decoding throws, and
   that the message holds "Could not decode FrontmatterValue".
   If no input can reach this branch, write that finding in a comment on
   this task and mark the lines as unreachable. Do not change the source
   to make the branch reachable.
   Result: no input reaches the branch. Lines 45-48 are unreachable. See the comment on this task.

- [x] 3. Line 82 -- the `default: return []` branch of
   `spaceSeparatedOrListTokens`.
   The branch runs for a value that is not `.string` and not `.array`.
   Write a SKILL.md whose `arguments:` field holds a bare integer, for
   example `arguments: 42`. Decode it. Make sure the tokens are an empty
   array, and that decoding does not fail.

Line 228 -- `AnyCodingKey.init?(intValue:)` -- always gives `nil` and no
YAML key is an integer. It is boilerplate. Leave it uncovered.

Put the tests in `Tests/FoundationModelsSkillsTests/`, next to the
frontmatter tests that are there. #coverage-gap