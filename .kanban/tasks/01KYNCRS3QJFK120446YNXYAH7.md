---
comments:
- actor: claude-code
  id: 01kynvmn4rptp6vfhkt076f74s
  text: |-
    Implemented per plan §6.1, TDD (RED confirmed via compile failure before types existed, then GREEN):

    - Sources/FoundationModelsSkills/Listing/SkillParameter.swift — name/position/required/variadic/placeholder, exactly as spec'd.
    - Sources/FoundationModelsSkills/Listing/SkillListing.swift — id/displayName/description/license/compatibility/parameters/acceptsTrailingArguments, plus init(id:frontmatter:body:) and init(id:decodedSkill:) convenience initializers that derive parameters/acceptsTrailingArguments via ParameterInference.
    - Sources/FoundationModelsSkills/Listing/ParameterInference.swift — ParameterInference.infer(frontmatter:body:) -> Result{parameters, acceptsTrailingArguments, diagnostics}. Precedence arguments: > argument-hint: > body inference. Hint grammar: <x> required, [x] optional, trailing "..." variadic (works on bracketed or bare tokens); bare/unbracketed tokens default required=true (documented design decision — no source marks them optional). Body inference scans $N and $ARGUMENTS[N] via regex, synthesizes positions 0...max (gap-filled) with synthesized "argN" names when neither arguments: nor argument-hint: is present. acceptsTrailingArguments is true only for a bare $ARGUMENTS reference (regex excludes $ARGUMENTS[N] via negative lookahead). Arity mismatches between arguments: and argument-hint: produce a diagnostic string, never a failure.

    Tests (TDD, written first, watched RED via compile failure, then GREEN):
    - Tests/FoundationModelsSkillsTests/ParameterInferenceTests.swift — table-driven: each source alone, arguments:+hint: merge (matching and mismatched arity), hint grammar (<a> [b] c... plus bracketed-variadic siblings <files>... [more]...), body gap-filling ($0 + $2 -> positions 0,1,2), and the acceptsTrailingArguments siblings (bare $ARGUMENTS true; $ARGUMENTS[N] alone false; no body false).
    - Tests/FoundationModelsSkillsTests/SkillListingTests.swift — snapshot over the existing fixture stack (commit, deploy, lint, spec-clean) plus a displayName-nil case for a Claude-style input without name:.

    swift test: 52/52 passed, exit 0, no warnings beyond the pre-existing (unrelated) SwiftPM package-identity conflict notices for foundationmodelsoperationtool.

    No new fixtures were needed — the commit fixture already had arguments:/argument-hint:/$0/$ARGUMENTS in its body per its own fixture-task description. The body-only and mismatch cases are covered with inline SkillFrontmatter/body text in ParameterInferenceTests rather than new fixture files.
  timestamp: 2026-07-29T02:35:43.128621+00:00
- actor: claude-code
  id: 01kynw0d2s83snj6fbac0156zb
  text: |-
    really-done verification: fresh `swift test` run, exit 0.

    Adversarial double-check round 1: REVISE — no functional bugs found in ParameterInference's regex/grammar logic (traced by hand and confirmed correct), but flagged 4 test-coverage gaps for sibling/edge cases the task brief called out: argument-hint: longer than arguments: (only shorter was tested), $ARGUMENTS embedded in a longer word (e.g. $ARGUMENTSX) not falsely tripping acceptsTrailingArguments, multi-digit body-inference positions ($10), and degenerate hint tokens (<>, [], bare too-short <). Plus one non-blocking FYI: document the literal-dollar-amount false-positive limitation of the $N regex.

    Fixed all 5: added hintLongerThanArgumentsProducesDiagnosticAndIgnoresExtraTokens, acceptsTrailingArgumentsIsFalseForArgumentsEmbeddedInLongerWord, bodyInferenceHandlesMultiDigitPositions, and hintParsesDegenerateEmptyBracketAndTooShortTokensWithoutCrashing to ParameterInferenceTests.swift; added a doc comment on ParameterInference.positionalReferencePattern documenting the dollar-amount limitation.

    Adversarial double-check round 2 (final, bounded): PASS. Re-traced all 4 new tests against the real implementation and confirmed each is non-tautological and asserts correct expected values; fresh swift test run confirmed by the checker itself: 56 tests, 3 suites, all passed, exit 0.

    Task is green and complete, left in doing for /review per the implement skill's contract.
  timestamp: 2026-07-29T02:42:08.089079+00:00
depends_on:
- 01KYNCR37A3M7MYKAH7T0QREYS
position_column: doing
position_ordinal: '80'
title: Parsed parameter model + SkillListing (§6.1)
---
## What
Build the structured parameter model and listing row from plan §6.1.

- `Sources/FoundationModelsSkills/Listing/SkillParameter.swift` — `name`, `position` (0-based), `required`, `variadic`, `placeholder` exactly as §6.1.
- `Sources/FoundationModelsSkills/Listing/SkillListing.swift` — `id`, `displayName` (frontmatter `name`, optional for Claude-style inputs), `description`, `license`, `compatibility`, `parameters`, `acceptsTrailingArguments`.
- `Sources/FoundationModelsSkills/Listing/ParameterInference.swift` — merge three sources by position, precedence `arguments:` > `argument-hint:` > body inference:
  - `arguments:` gives authoritative names/order.
  - `argument-hint:` parsing: `<x>` required, `[x]` optional, trailing `...` variadic; contributes placeholders + optionality.
  - Body inference: scan for `$0`/`$N`/`$ARGUMENTS[N]` when neither is present; synthesize positional params.
  - `acceptsTrailingArguments` true ONLY when the body references `$ARGUMENTS` (the §5 auto-append fallback never sets it).
  - Source-mismatch diagnostics (e.g. hint arity ≠ arguments arity).

## Acceptance Criteria
- [x] `commit` fixture yields named params with hint placeholders and correct optionality
- [x] A body-only skill (`$0`, `$2` present) synthesizes positions 0–2 (gaps filled)
- [x] `acceptsTrailingArguments` is false when the body lacks `$ARGUMENTS`
- [x] Mismatched sources produce a diagnostic, not a failure

## Tests
- [x] `Tests/FoundationModelsSkillsTests/ParameterInferenceTests.swift` — table-driven merge matrix over all three sources; hint-grammar cases (`<a> [b] c...`)
- [x] `Tests/FoundationModelsSkillsTests/SkillListingTests.swift` — listing snapshot for the fixture stack
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.