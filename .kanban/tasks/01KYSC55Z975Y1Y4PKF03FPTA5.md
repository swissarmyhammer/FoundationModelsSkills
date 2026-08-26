---
comments:
- actor: claude-code
  id: 01m0z32s93kjcy14fcrw6seycm
  text: |-
    Research: `DecodedSkill.notes` holds three note kinds: a mistyped `metadata.*` value, a both-spellings conflict, and the quoting-fallback retry. `SkillValidator.RuleContext` did not carry the notes. A `Rule` returns at most one diagnostic, but notes can be many, so the notes are not a `Rule` row. They are a separate step after the rule loop.

    Implementation:
    - `SkillValidator.swift`: `RuleContext.notes`, `decoderNoteDiagnostics(_:)` emits one `.advisory` per note with the note text as the message and the winning-root provenance. Appended after the rule-table diagnostics. Table doc comment has a new row.
    - `SkillFrontmatter.swift`: doc comment on `notes` now describes both note kinds. `FrontmatterDecoder.swift` and `SkillDiagnostic.swift` doc comments updated to match.
    - Tests: `SkillValidatorTests` gets a `notes:` parameter on the `validate` helper and three tests (one per note kind, order, placement after rule diagnostics). `SkillsRegistryTests` gets two end-to-end tests with real `SKILL.md` fixtures.

    Discovery: the quoting-fallback retry note now also becomes an advisory. Two existing tests changed because of this:
    - `brokenBadColonDescription...` now expects exactly one advisory that names the retry.
    - The `arity-mismatch` fixture description had an unquoted `arguments:` colon, so it decoded only through the retry. The description is now quoted, so the fixture exercises only the arity rule.
  timestamp: 2026-08-26T13:10:19.683757+00:00
- actor: claude-code
  id: 01m0z32y5r7hwseh93h09361y5
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsSkills/Validation/SkillValidator.swift, Sources/FoundationModelsSkills/Validation/SkillDiagnostic.swift, Sources/FoundationModelsSkills/Frontmatter/SkillFrontmatter.swift, Sources/FoundationModelsSkills/Frontmatter/FrontmatterDecoder.swift, Tests/FoundationModelsSkillsTests/SkillValidatorTests.swift, Tests/FoundationModelsSkillsTests/SkillsRegistryTests.swift; `swift test` 338 tests passed
    - next: test, commit, review
  timestamp: 2026-08-26T13:10:24.696700+00:00
- actor: claude-code
  id: 01m0z34y191te5c6mjzg6k4w3w
  text: |-
    ### test — green
    - evidence: `swift test` — 338 tests in 23 suites passed, 0 failed; `swift build --build-tests` has no compiler warnings (one pre-existing SwiftPM bundle warning for `mlx-swift_Cmlx.bundle`, not from source). One gated test (`HotReloadLiveTests`, skipped unless `SKILLS_INTEGRATION_TESTS=1`) fails with the same error on HEAD without this change; filed as a new task.
    - next: commit
  timestamp: 2026-08-26T13:11:30.089389+00:00
- actor: claude-code
  id: 01m0z35fmz1ydv1hbxzhz9c8af
  text: |-
    ### commit — changed
    - evidence: 2b921bc feat(validation): surface frontmatter decode notes as advisory diagnostics
    - next: review
  timestamp: 2026-08-26T13:11:48.127766+00:00
- actor: claude-code
  id: 01m0z3a4j4afxn7hbkca4ast8k
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 6 files reviewed (7 validator runs, 0 failed); no prior findings sections
    - next: done
  timestamp: 2026-08-26T13:14:20.612555+00:00
- actor: claude-code
  id: 01m0z3a6gw29qah6x3cyekwrxm
  text: |-
    ### finish iteration 1 — review clean, task moved to done
    - implement: changed — 6 files (SkillValidator, SkillDiagnostic, SkillFrontmatter, FrontmatterDecoder, SkillValidatorTests, SkillsRegistryTests)
    - test: green — `swift test` 338 passed, 0 failed
    - commit: 2b921bc
    - review: clean — 0 findings on HEAD~1..HEAD
  timestamp: 2026-08-26T13:14:22.620147+00:00
position_column: done
position_ordinal: aa80
title: Surface frontmatter decode notes as registry diagnostics
---
## What
Reopens the unfinished third of the validation-edges task: mistyped `metadata.*` extension values are noted at decode time (`Frontmatter/SkillFrontmatter.swift:315-323`, wired through `resolveExtensionField`) and correctly ignored — but the note NEVER becomes a diagnostic. `SkillValidator`'s `RuleContext` does not carry `DecodedSkill.notes`, no rule consults them, and `grep '\.notes' Sources/` matches only `Frontmatter/`. So `metadata: { preload: "true" }` produces no `.advisory` in `registry.diagnostics` — contradicting the closed task's acceptance criterion. The pre-existing top-level/`metadata.*` conflict note has the same dead end.

Fix:
- Carry decoder notes into the validator's context and emit each as an `.advisory` `SkillDiagnostic` with the skill's winning-root provenance (both the mistyped-value notes and the both-spellings conflict note).
- Update the stale doc comment at `SkillFrontmatter.swift:155-157` ("currently just the … conflict case") to describe both note kinds.

## Acceptance Criteria
- [x] `metadata: { preload: "true" }` yields an `.advisory` in `registry.diagnostics` naming the key and expected type; skill still loads
- [x] A field present both top-level and under `metadata.*` yields the conflict advisory in `registry.diagnostics`
- [x] Doc comment on `SkillFrontmatter.notes` matches reality

## Tests
- [x] Extend `Tests/FoundationModelsSkillsTests/SkillValidatorTests.swift` (or `SkillsRegistryTests`) — decode-note → diagnostic rows for both note kinds, asserting id, severity, message, provenance
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.