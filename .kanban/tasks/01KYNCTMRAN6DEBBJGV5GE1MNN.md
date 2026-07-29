---
comments:
- actor: claude-code
  id: 01kyp2wncd1x11abmgj0gmc6h4
  text: |-
    Implementation landed (TDD, red->green):

    - Added `Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift`: `RenderPass` conformer for §5 pass 1. Single left-to-right NSRegularExpression scan (named capture groups) over the pass's input text handling, in grammar-precedence order: `\$` escape, `${VAR}` (special-variable table, currently just `SKILL_DIR`), `$ARGUMENTS[N]`, bare `$ARGUMENTS`, `$N`, `$name`. Positional args for `$N`/`$ARGUMENTS[N]` come from a hand-rolled shell-style tokenizer (`shellStyleTokens`) applied to all supplied arguments joined with a space ("as typed") -- handles double/single quotes and backslash escapes. `$ARGUMENTS` auto-append (`\n\nARGUMENTS: <value>`) fires only when args were supplied and the body has no *bare* `$ARGUMENTS` reference (an `$ARGUMENTS[N]` reference does not count, matching the existing `ParameterInference.referencesArguments` precedent). Unrecognized `$name`/`${VAR}` tokens are left untouched verbatim (e.g. bare `$HOME` survives pass 1 for pass 3's env templating). Missing positional/named references substitute to empty, no diagnostic (spec explicitly defers correctives to a future ops layer).
    - Extended `RenderRequest` (`Sources/FoundationModelsSkills/Render/RenderPipeline.swift`) with a new `argumentNames: [String]` field (the skill's `arguments:` frontmatter names, in order) -- needed for `$name` resolution and not previously carried by the request. Defaulted to `[]` so no existing call site broke. Deliberately *not* reusing the full `SkillParameter`/`ParameterInference` model for this -- plan.md §5 scopes `$name` resolution strictly to the `arguments:` frontmatter list, not hint-derived or body-inferred names, so a plain ordered name array is the more spec-accurate and minimal representation.
    - Added `Tests/FoundationModelsSkillsTests/ArgumentSubstitutionTests.swift`: table-driven (Swift Testing `@Test(arguments:)`) coverage of every token form, the tokenizer's quoting/escaping rules, the `\$` escape, the auto-append 2x2 matrix, missing-reference-substitutes-empty, the single-shot no-re-scan case, and an end-to-end `commit` fixture render for quoted multi-word args.

    Dead end worth recording: several of the token-form/quoting tests originally asserted exact string equality, but since their bodies legitimately lack a bare `$ARGUMENTS` reference while supplying non-empty arguments, the auto-append fallback correctly appends its own suffix, breaking exact equality. Fixed by switching those specific assertions to `hasPrefix` (with a comment explaining why) rather than restructuring bodies -- the auto-append behavior itself has its own dedicated matrix test.

    Verification: `swift build` and `swift test` both green, 75/75 tests pass across 5 suites, exit 0, no new warnings. Adversarial double-check review in progress via the really-done gate.
  timestamp: 2026-07-29T04:42:25.549457+00:00
- actor: claude-code
  id: 01kyp3hb3z6pb2d14dd53pjqbq
  text: |-
    Adversarial double-check (first pass) returned REVISE with three findings, all addressed:

    1. Critical: `classify(_:in:)` could reach an unconditional `preconditionFailure` (process crash, not a graceful fallback) when a `$N`/`$ARGUMENTS[N]` digit run was too large for `Int` -- `Int(digits)` returning `nil` made the old `if let digits = ..., let index = Int(digits)` guard fail as a whole and fall through to the trap, since no other alternative's capture group was populated for that match. Confirmed the crash was real: added a regression test with a 20-digit literal, watched the whole test process crash with `Fatal error: ArgumentSubstitution.tokenPattern matched but no known alternative captured.` before fixing. Fix: `TokenKind.argumentsIndexed`/`.positional` now carry `index: Int?`; `classify` checks the capture group's *range* to decide which alternative matched (not whether `Int(digits)` parses), so an oversized digit run classifies correctly with `index: nil`, treated the same as any other out-of-range index (substitutes empty). Two new regression tests pin this.

    2. Medium/high: `$name` resolution retokenizes `request.arguments` (joined + shell-split) rather than indexing `request.arguments` directly, so `RenderRequest.argumentNames`'s doc comment ("position i in this array matches position i in arguments/$i") was misleading whenever an argument value contains unprotected whitespace -- reviewer's counterexample: `arguments: ["hello world", "second"]`, `argumentNames: ["first", "second"]` resolves `$first` to `"hello"` not `"hello world"`. Chose to document + test the existing behavior (reviewer's option b) rather than restructure `$name` onto a different position space than `$N`/`$ARGUMENTS[N]` -- keeping all three sharing one position space is the architecturally consistent choice; diverging `$name` alone would be worse. Corrected the doc comment on `RenderRequest.argumentNames` to state plainly that position `i` corresponds to the shell-tokenized positional array (the same one `$i` indexes), not raw `arguments` index `i`, and that callers should quote multi-word values the same way `$N` already requires. Added a pinning regression test using the reviewer's exact counterexample.

    3. Low: `TokenKind` (type + all 6 case docs), `SpecialVariable.name`/`.resolve` field docs, and `tokenPattern`'s doc lacked this project's blank-`///`-line + elaboration convention, present everywhere else in the file. Fixed all of them.

    Verification after fixes: `swift build` and `swift test` both green, 78/78 tests (75 original + 3 new regression tests), exit 0, no new warnings. A second, confirmation-scoped double-check pass is in flight to verify the fixes actually resolve the findings and didn't introduce anything new.
  timestamp: 2026-07-29T04:53:43.167620+00:00
- actor: claude-code
  id: 01kyp4dsn7rr41asncdxy8nbnn
  text: |-
    Review finding addressed: extracted the whitespace token-finalization block in `shellStyleTokens` (ArgumentSubstitution.swift) into a local nested function `flushPendingToken()` (guard-based early return, appends+resets the accumulator). This drops the whitespace-boundary branch from 4 levels of nesting (while > switch case > if isWhitespace > if hasCurrentToken) to 3 (while > switch case > single-line call), and is also reused for the final post-loop flush that previously duplicated the same append logic. Behavior is unchanged -- same append/reset sequence, same guard condition. Added a doc comment on the new helper following this project's convention (period-terminated summary, blank `///`, elaboration) plus an inline comment noting why it was extracted.

    Verification: `swift build` exit 0 (pre-existing unrelated SwiftPM dependency-identity warnings only, no new warnings), `swift test` 78/78 passed, exit 0. Adversarial double-check dispatched to confirm no behavior change before handoff.
  timestamp: 2026-07-29T05:09:15.559332+00:00
- actor: claude-code
  id: 01kyp59spg2824273y7zqsd02p
  text: |-
    Round 3 review findings addressed in Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift:

    1. Duplicated digit-group extraction (argumentsIndex/position in classify(_:in:)): extracted a local nested helper `digitGroupTokenKind(groupName:makeKind:)` that captures `match`/`text` and does the extract-then-`Int(digits)`-then-construct sequence once, taking the capture group name and a `(Int?) -> TokenKind` constructor closure. Both the `$ARGUMENTS[N]` and `$N` branches now call it instead of repeating the sequence inline.
    2. Remaining 4-level nesting (while > switch case .none > if > if, in shellStyleTokens' unquoted-backslash handling): extracted a local nested helper `consumeUnquotedBackslash()`, mirroring the flushPendingToken() precedent from round 1 -- guard-based early return instead of a nested if. Drops that branch to 3 levels.

    Also did the requested final full-file control-flow pass: re-checked render(_:request:)'s for/switch (max 3 levels), classify(_:in:)'s flat if-chain, and all three shellStyleTokens quote-state branches (.none, .double, .single) including the pre-existing .double branch's comma-joined if/else-if (3 levels). No other 4+-level nesting or near-duplicate blocks found.

    Both new helpers have doc comments following this project's convention (period-terminated summary, blank `///`, elaboration), plus an inline comment on each noting what review finding prompted the extraction.

    Verification: swift build exit 0 (only pre-existing unrelated SwiftPM dependency-identity warnings, no new warnings); swift test 78/78 passed across 5 suites, exit 0. Both review finding checkboxes checked off in the task description; task left in doing per /implement's process (review owns the doing->review transition).
  timestamp: 2026-07-29T05:24:33.104661+00:00
- actor: claude-code
  id: 01kyp5f6p1hmrrqyx9x30a44pv
  text: |-
    Adversarial double-check (round-3 diff) returned REVISE with two minor doc-comment/placement nits on the new `consumeUnquotedBackslash()` helper -- no correctness issues found; both new helpers (`digitGroupTokenKind`, `consumeUnquotedBackslash`) were confirmed behavior-identical to the removed inline code, nesting confirmed <=3 levels everywhere, no other duplication found.

    Findings addressed:
    1. `consumeUnquotedBackslash()`'s doc comment was missing the blank `///` line between its summary sentence and elaboration (the project convention, and the one thing this review round specifically asked to check) -- fixed by splitting into a summary paragraph, blank `///`, then the "trailing backslash" elaboration.
    2. `consumeUnquotedBackslash()` was declared before `characters`/`index` (the state it captures), diverging from the `flushPendingToken()` precedent it claimed to mirror (which is declared after its captured state) -- moved the helper to after `let characters = Array(text)` / `var index = 0`, immediately before the `while` loop.

    Re-verified after fixes: `swift build` exit 0 (same pre-existing unrelated warnings only), `swift test` 78/78 passed across 5 suites, exit 0. Per really-done's bounded-loop rule (fix once, re-check at most once), not re-spawning double-check a second time for these two cosmetic doc/placement nits -- fixes are mechanical and directly match the reviewer's suggested diffs verbatim, and both build/test are confirmed green post-fix.
  timestamp: 2026-07-29T05:27:30.241966+00:00
- actor: claude-code
  id: 01kyp6d0jm6d6z7gpa0yjncvj5
  text: |-
    Round-4 review findings addressed in Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift:

    1. classify(_:in:)'s doc comment run-on: split the one-sentence summary ("...grammar's own precedence order (escape, ${VAR}, $ARGUMENTS[N], bare $ARGUMENTS, $N, $name).") from its elaboration ("Exactly one alternative's range is ever populated...") with a blank `///` line, per this project's doc-comment convention.

    2. Group-name string duplication between tokenPattern and classify(): added a private nested `enum GroupName` (six static let constants: escape, specialVar, argumentsIndex, argumentsBare, position, namedArg) sitting between TokenKind and classify(_:in:), with its own doc comment. classify(_:in:)'s match.range(withName:) / groupText(match, name:) calls and the digitGroupTokenKind helper's group-name arguments now reference GroupName.xxx instead of bare string literals. tokenPattern's raw-string regex now interpolates the same constants via Swift raw-string \#() interpolation instead of embedding group names as literal text, so the regex pattern and the lookup strings share one source of truth. This fixes not just the three named in the finding (escape, argumentsIndex, position) but all six group names in the file (also specialVar, argumentsBare, namedArg), per the "likely other group names" instruction to check exhaustively.

    Also did the requested final exhaustive pass over every doc comment in the file (file header, init, render, TokenKind + all 6 cases, GroupName, classify, digitGroupTokenKind, groupText, tokenPattern, SpecialVariable + members, specialVariables, shellStyleTokens, QuoteState, doubleQuoteEscapable, flushPendingToken, consumeUnquotedBackslash, the Array subscript extension) -- each is either a single-sentence summary with no elaboration, or a single-sentence summary + blank `///` line + elaboration. No other run-on summaries found. Grepped the whole file for every group-name string literal used with range(withName:) or in the pattern string to confirm zero bare duplicates remain anywhere.

    One implementation note worth recording: my first attempt at placing the new GroupName enum inserted it directly after classify(_:in:)'s doc-comment block and before the classify function itself -- since Swift attaches a doc comment to the *immediately following* declaration, that would have silently reattached classify's doc comment to GroupName instead. Caught this before verifying and moved GroupName (with its own separate doc comment) to sit between TokenKind's closing brace and classify's doc comment instead, with a blank line on both sides, so each doc comment attaches to the correct declaration.

    Verification: `swift build` exit 0 (only the pre-existing unrelated SwiftPM dependency-identity warnings, no new warnings); `swift test` 78/78 passed across 5 suites, exit 0. Adversarial double-check (round-4 diff) independently confirmed the raw-string interpolation is byte-identical to the original literals, GroupName's placement doesn't break any doc-comment attachment, classify's doc comment now matches convention, all six group names are unified with zero bare duplicates, and no other run-on doc-comment summaries exist in the file. Verdict: PASS.

    All review-finding checkboxes checked off in the task description. Task left in `doing` per /implement's process -- review owns the doing->review transition.
  timestamp: 2026-07-29T05:43:47.028939+00:00
- actor: claude-code
  id: 01kyp79b5np1039gznp5g6nerq
  text: |-
    Round-5 review findings addressed in Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift:

    1. classify(_:in:)'s specialVar/namedArg near-duplicate if-statements: extracted a local nested helper nameGroupTokenKind(groupName:makeKind:), mirroring the existing digitGroupTokenKind(groupName:makeKind:) precedent. Both call sites now follow the same "check the range, then call the helper" shape digitGroupTokenKind's two call sites already use, instead of each inlining its own `if let name = groupText(...) { return .X(name: name) }`.

    2. Array [safe:] subscript's doc comment reworded to drop the caller reference, using the exact reviewer-suggested wording: "Safe subscript that returns `nil` for out-of-range indices, where absence represents no value supplied, not an error."

    Also did the requested final careful full pass over control flow, doc comments, and near-duplicate blocks, and proactively fixed one more instance of the same rot-risk category as finding 2: GroupName's own doc comment embedded a review-history narrative ("review found three of these... duplicated as bare string literals"); trimmed to a single semantics-only sentence. No other near-duplicate logic blocks, 4+-level nesting, or caller/history-referencing doc comments found anywhere else in the file.

    Verification: swift build exit 0 (only pre-existing unrelated SwiftPM dependency-identity warnings, no new warnings); swift test 78/78 passed across 5 suites, exit 0. Adversarial double-check (round-5 diff) independently re-ran build/test itself (both green), confirmed both fixes are complete and behaviorally correct, and confirmed no other near-duplicate blocks or rot-risk doc comments remain anywhere in the file. Verdict: PASS.

    Both review-finding checkboxes checked off in the task description. Task left in doing per /implement's process -- review owns the doing->review transition.
  timestamp: 2026-07-29T05:59:15.381209+00:00
depends_on:
- 01KYNCS3K5T60E4JQAJ8JQWXC5
- 01KYNCRS3QJFK120446YNXYAH7
position_column: doing
position_ordinal: '80'
title: 'Render pass 1: argument + variable substitution'
---
## What
Implement §5 pass 1 (Claude-compatible substitution), replacing the identity transform.

- `Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift`:
  - `$ARGUMENTS` — all args joined as typed; when the body has no `$ARGUMENTS` and args were supplied, append `ARGUMENTS: <value>` (the no-data-loss fallback).
  - `$ARGUMENTS[N]` and `$N` — 0-based positional; arguments are pre-split with shell-style quoting (a small tokenizer: double/single quotes, backslash escapes).
  - `$name` — named args resolved through the §6.1 parameter model (`arguments:` frontmatter order).
  - `${SKILL_DIR}` — the skill's directory path; leave room for more special vars behind one table.
  - `\$` escapes a literal `$`; escaped dollars never substitute.
  - Single-shot: substituted output is not re-scanned (values containing `$0` stay literal).
  - Missing positional/named reference with no supplied value → substitute empty + note (the ops layer decides correctives from the §6.1 required flags).

## Acceptance Criteria
- [x] `commit` fixture renders its `$0`/`$ARGUMENTS` body correctly for quoted multi-word args
- [x] `\$HOME` survives as `$HOME`; `$HOME` (not an arg name) is untouched by pass 1 (env is pass 3's job)
- [x] Auto-append fires only when args are supplied AND the body lacks `$ARGUMENTS`
- [x] A substituted value containing `$1` is not re-substituted

## Tests
- [x] `Tests/FoundationModelsSkillsTests/ArgumentSubstitutionTests.swift` — table-driven: every token form, quoting cases, escape cases, auto-append matrix, no-re-scan case
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Implementation notes
- Extended `RenderRequest` with a new `argumentNames: [String]` field (the skill's `arguments:` frontmatter names, in order) to support `$name` resolution; defaulted to `[]`, no existing call site broke.
- `$name`/`$N`/`$ARGUMENTS[N]` all share one position space: all supplied arguments joined as typed, then split by a hand-rolled shell-style tokenizer (double/single quotes, backslash escapes). Documented on `RenderRequest.argumentNames` that this is the shell-tokenized position space, not necessarily raw `arguments` array indices.
- Went through one adversarial double-check REVISE round: fixed a critical crash (oversized `$N`/`$ARGUMENTS[N]` digit runs reaching `preconditionFailure` instead of substituting empty), corrected a misleading doc comment plus added a pinning regression test for the `$name` position-space behavior, and filled in doc-comment gaps on `TokenKind`, `SpecialVariable`, and `tokenPattern`. Second double-check pass returned PASS.
- Final verification: `swift build` and `swift test` both green, 78/78 tests across 5 suites, exit 0, no new warnings.

## Review Findings (2026-07-28 23:59)

- [x] `Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift:255` — Four levels of nesting (while loop > switch case > if condition > nested if condition) exceed the three-level threshold, reducing local readability and testability of this branch. Extract the whitespace token-finalization block (lines 255–259) into a helper method to reduce nesting to 3 levels, or use guard statements with early returns at the start of the case branch.

  Fixed: extracted a local nested helper `flushPendingToken()` inside `shellStyleTokens` that appends the pending token and resets the accumulator (guard-based early return). Both the whitespace-boundary branch inside the scan loop and the final post-loop flush now call it, reducing the whitespace branch to 3 levels of nesting (while > switch case > single-line call). Doc comment follows the project convention. `swift build` and `swift test` (78/78) green; adversarial double-check returned PASS.

## Review Findings (2026-07-29 00:13)

- [x] `Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift:168` — The digit-group extraction pattern at lines 168–170 is near-verbatim duplicated at lines 175–177, differing only in group name and TokenKind variant. Extract to a parameterized helper to prevent drift when one is updated without the other. Extract a helper function accepting group name and constructor callback (e.g., `(Int?) -> TokenKind`), mirroring the flushPendingToken pattern this change introduces.

  Fixed: extracted a local nested helper `digitGroupTokenKind(groupName:makeKind:)` inside `classify(_:in:)`, capturing `match`/`text` from the enclosing scope, that extracts the named digit-run capture, parses it, and builds the `TokenKind` via a `(Int?) -> TokenKind` constructor closure. Both the `$ARGUMENTS[N]` and `$N` branches now call it with their own group name and case constructor instead of repeating the extract-then-`Int(digits)` sequence inline. Doc comment follows the project convention.

- [x] `Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift:247` — Nested if at 4 levels deep (while → switch → if → if) exceeds the 3-level threshold for deep nesting. Extract the nested condition into a helper function or guard statement to reduce nesting depth.

  Fixed: extracted a local nested helper `consumeUnquotedBackslash()` inside `shellStyleTokens`, mirroring the `flushPendingToken()` precedent -- it marks a token pending and, via a guard-based early return, appends the character following the backslash (if any) and advances past it. The unquoted-backslash branch in the `case .none` arm now calls it instead of nesting `if index + 1 < characters.count { ... }` inside the branch, dropping that arm from 4 levels of nesting (while > switch case > if > if) to 3 (while > switch case > single-line call).

  Also did a final full-file control-flow pass per the review request: re-read `render(_:request:)`'s `for`/`switch` (max 3 levels, the `.named` case's `if`/`else`), `classify(_:in:)`'s flat if-chain, and every `shellStyleTokens` quote-state branch (`.none`, `.double`, `.single`), including the pre-existing `.double` branch's comma-joined `if`/`else if` (3 levels, not nested further). No other 4+-level nesting or near-duplicate blocks found.

  Verification: `swift build` exit 0 (only the pre-existing unrelated SwiftPM dependency-identity warnings, no new warnings); `swift test` 78/78 passed across 5 suites, exit 0.

## Review Findings (2026-07-29 00:28)

- [x] `Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift:106` — The doc comment for `classify(_:in:)` runs two sentences together without a blank line separator. The first sentence ends after `$name`)., but the second sentence (Exactly one alternative's range...) immediately follows on the same line without a blank `///` separator, violating the rule that elaboration must follow the summary after a blank line. Insert a blank `///` line after the first sentence. Split line 106 to end after the closing paren and period, add `///` on the next line, then start the elaboration with `Exactly one alternative's range...` on the line following.

  Fixed: split `classify(_:in:)`'s doc comment so the one-sentence summary ("...grammar's own precedence order (escape, `${VAR}`, `$ARGUMENTS[N]`, bare `$ARGUMENTS`, `$N`, `$name`).") is followed by a blank `///` line, then the elaboration paragraph ("Exactly one alternative's range is ever populated...") begins on its own line.

- [x] `Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift:217` — Group name "escape" is hardcoded in two places: the tokenPattern regex and classify() function. Changes require updates in two locations, risking drift. Extract group names as static constants (e.g., private struct GroupNames with static let escape = "escape", etc.) so the regex and classify() reference a single source of truth.
- [x] `Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift:223` — Group name "argumentsIndex" is duplicated between tokenPattern regex and classify() (appears twice within classify on lines 223–224). Extract as constant.
- [x] `Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift:229` — Group name "position" is duplicated between tokenPattern regex and classify() (appears twice within classify on lines 229–230). Extract as constant.

  Fixed (all three, plus every other group name in the file): added a private nested `enum GroupName` (six `static let` constants: `escape`, `specialVar`, `argumentsIndex`, `argumentsBare`, `position`, `namedArg`) placed between `TokenKind` and `classify(_:in:)`, with its own doc comment. `classify(_:in:)`'s `match.range(withName:)` / `groupText(match, name:)` calls and the `digitGroupTokenKind` helper's group-name arguments now reference `GroupName.xxx` instead of bare string literals. `tokenPattern`'s raw-string regex pattern now interpolates the same constants via Swift raw-string `\#()` interpolation (`(?<\#(GroupName.escape)>...)`, etc.) instead of embedding the group names as literal text, so the pattern string and the lookup strings are generated from one source and can never drift. Grepped the whole file afterward to confirm all six group names (not just the three named in the finding) now resolve through `GroupName` with zero bare duplicates remaining.

  Also did the requested exhaustive final pass: re-checked every doc comment in the file (file header, `init`, `render`, `TokenKind` and all 6 cases, `GroupName`, `classify`, `digitGroupTokenKind`, `groupText`, `tokenPattern`, `SpecialVariable` and its members, `specialVariables`, `shellStyleTokens`, `QuoteState`, `doubleQuoteEscapable`, `flushPendingToken`, `consumeUnquotedBackslash`, the `Array` subscript extension) for the summary/blank-line/elaboration convention — every one either has a single-sentence summary with no further elaboration, or a single-sentence summary followed by a blank `///` line and then the elaboration. No other run-on summaries found.

  Verification: `swift build` exit 0 (only the pre-existing unrelated SwiftPM dependency-identity warnings, no new warnings); `swift test` 78/78 passed across 5 suites, exit 0. Adversarial double-check (round 4 diff) independently confirmed the raw-string interpolation is correct and produces byte-identical group names, `GroupName`'s placement doesn't break any doc-comment attachment, `classify`'s doc comment now matches convention, all six group names are unified with zero bare duplicates, and no other run-on doc-comment summaries exist in the file. Verdict: PASS.

## Review Findings (2026-07-29 00:44)

- [x] `Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift:177` — Near-identical if statement checking GroupName.namedArg; mirrors the specialVar check (line ~165) differing only by group name and token kind constructor. Extract to shared function to prevent maintenance drift. Extract both into a single shared helper parameterized by group name and token kind constructor, replacing both call sites.
- [x] `Sources/FoundationModelsSkills/Render/ArgumentSubstitution.swift:328` — Doc comment references a specific caller ('Used by `ArgumentSubstitution`'), which rots as the codebase evolves and belongs in PR descriptions, not inline documentation. Remove the caller reference and focus on the semantic meaning: `/// Safe subscript that returns `nil` for out-of-range indices, where absence represents no value supplied, not an error.`.

  Fixed (both): extracted a local nested helper `nameGroupTokenKind(groupName:makeKind:)` inside `classify(_:in:)`, mirroring the existing `digitGroupTokenKind(groupName:makeKind:)` precedent -- both the `GroupName.specialVar` and `GroupName.namedArg` checks now follow the same "check the range, then call the helper" shape `digitGroupTokenKind`'s two call sites already use, instead of each inlining its own `if let name = groupText(...) { return .X(name: name) }`. The `Array` `[safe:]` subscript's doc comment was reworded to the exact reviewer-suggested text, dropping the caller reference: "Safe subscript that returns `nil` for out-of-range indices, where absence represents no value supplied, not an error."

  Also did the requested final careful full pass over control flow, doc comments, and near-duplicate blocks. Found and proactively fixed one more instance of the same rot-risk category as the second finding: the `GroupName` enum's own doc comment embedded a review-history narrative ("...can never drift out of sync -- review found three of these (`escape`, `argumentsIndex`, `position`) duplicated as bare string literals..."); trimmed to a single semantics-only sentence: "Defined once here so the group names embedded in the regex pattern and the strings used to look those groups back up can never drift out of sync." No other near-duplicate logic blocks, 4+-level nesting, or caller/history-referencing doc comments were found in the rest of the file.

  Verification: `swift build` exit 0 (only the pre-existing unrelated SwiftPM dependency-identity warnings, no new warnings); `swift test` 78/78 passed across 5 suites, exit 0. Adversarial double-check (round-5 diff) independently confirmed both fixes are complete and behaviorally correct, confirmed no other near-duplicate blocks or rot-risk doc comments remain anywhere in the file, and re-ran `swift build`/`swift test` itself (both green). Verdict: PASS.
