---
assignees:
- claude-code
position_column: todo
position_ordinal: 8b80
title: 'Add tests for SkillFrontmatter: the .double decode branch and the non-tokenizing default'
---
`Sources/FoundationModelsSkills/Frontmatter/SkillFrontmatter.swift`

Coverage: 95.8% (159/166 lines)

Uncovered lines: 37, 45-48, 82

Add these tests. Do not change `SkillFrontmatter.swift`.

1. Line 37 -- the `.double(value)` branch of
   `FrontmatterValue.init(from:)`.
   No test decodes a YAML float. Write a SKILL.md whose frontmatter holds
   a float value, for example `metadata:` with a key set to `1.5`. Decode
   it. Make sure the value is `.double(1.5)`, not `.int` and not
   `.string`.

2. Lines 45-48 -- the `DecodingError.dataCorrupted` throw at the end of
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

3. Line 82 -- the `default: return []` branch of
   `spaceSeparatedOrListTokens`.
   The branch runs for a value that is not `.string` and not `.array`.
   Write a SKILL.md whose `arguments:` field holds a bare integer, for
   example `arguments: 42`. Decode it. Make sure the tokens are an empty
   array, and that decoding does not fail.

Line 228 -- `AnyCodingKey.init?(intValue:)` -- always gives `nil` and no
YAML key is an integer. It is boilerplate. Leave it uncovered.

Put the tests in `Tests/FoundationModelsSkillsTests/`, next to the
frontmatter tests that are there. #coverage-gap