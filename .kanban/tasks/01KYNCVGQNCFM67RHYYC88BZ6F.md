---
comments:
- actor: claude-code
  id: 01kypczaf11d1a6hjfcvpfrh9e
  text: |-
    Implementation landed. Research + discoveries before coding:

    - Read FoundationModelsExtras' real TemplateEngine.swift/TemplateContext.swift/DotfolderStack.swift/DotfolderLoader.swift in full. Key findings that shaped the design:
      - TemplateEngine's ONLY public initializer is `init(partials: DotfolderStack?)` — it always pulls REAL `ProcessInfo.processInfo.environment` and real well-known values internally. The hermetic test seam `init(partials:environment:wellKnownValues:)` and the `WellKnownValues` type are both module-internal to FoundationModelsExtras (no `public`), so FoundationModelsSkills cannot reach them, even from its own test target (no `@testable import` in production code, and that wouldn't help tests target StencilPass anyway).
      - Resolution: StencilPass builds the ENTIRE 3-rung ladder itself into one `TemplateContext` (well-known lowest, environment next, declared skill arguments highest) and hands that single merged context to `TemplateEngine.render`. Because TemplateContext always outranks TemplateEngine's own internal env/well-known rungs, this fully determines the render — TemplateEngine's own (uncontrollable) internal ladder never actually contributes for any key StencilPass sets. This is what makes deterministic golden tests possible without any Extras-side test hook.
      - `DotfolderLoader` (the include-partial resolver) is NOT public API — only reachable via `TemplateEngine.init(partials:)`. So partial resolution over host-supplied roots requires constructing a `DotfolderStack` directly. `DotfolderStack` has no `init(layers:)`, but `layers` is a public mutable var and `Layer.init(source:root:)` is public — so `StencilPass` builds a throwaway `DotfolderStack(name:workingDirectory:)` (values irrelevant, construction does no I/O) and immediately overwrites `.layers` with the host-supplied ordered array. This is the sanctioned bridging seam for "host supplies roots, not a stack Extras derives" (decision #29 amended).
      - `RenderRequest.winningLayer` (from the already-landed RenderPipeline.swift) is typed `DotfolderStack.Layer`, which already carries `.source` (`.defaults`/`.user`/`.project`). Trust default rule keys off `winningLayer.source == .defaults`, per the task's "defaults = lowest-precedence host-designated root" framing — whoever builds RenderRequest is expected to tag the host's lowest-precedence root `.defaults`.
      - Extras' own `WellKnownValues` type isn't public, so StencilPass carries a small public mirror (`StencilPass.WellKnownValues`) with the same 4 fields (`workingDirectory`/`date`/`hostname`/`dotfolderName`), `current(layers:)` deriving real values (dotfolderName found by scanning `layers` for `.source == .project`, mirroring Extras' own `projectDotfolderName` algorithm) and every field independently injectable for tests.
      - `ArgumentSubstitution.shellStyleTokens` changed from `private` to internal (module-visible) so StencilPass can derive the same positional values for the explicit-context rung (`{{ name }}`) that pass 1 already uses for `$name`/`$N` — keeps both passes' argument indexing consistent instead of duplicating the tokenizer.

    Dead ends / bugs found and fixed during TDD:
    - `{% ifnot flag %}no{% endifnot %}` in a trust-matrix test: guessed wrong closing tag. Checked Stencil's actual IfTag.swift (vendored in .build/checkouts/Stencil) — `ifnot` closes with `{% endif %}`, not `{% endifnot %}`. Fixed the test body.
    - Golden env-report test threw "untrusted rendering exceeded the maximum include depth (8)" even for a trivial `{% include "header" %}` body. Root-caused via a raw-API repro (bypassing StencilPass entirely) down to a single-layer real-fixture stack: the ORIGINAL `user/_partials/header.md` fixture's own prose described the include syntax using literal backticked text `` `{% include "header" %}` `` — Stencil has no markdown-aware escaping, so that literal text inside the partial IS a real, executable include tag that re-includes the same partial, recursing until the depth cap. This was a genuine bug in the fixture I authored, not in Extras. Fixed by rephrasing header.md's prose to describe the tag in words instead of writing the literal `{% ... %}` syntax.

    Fixtures added/changed: `Examples/skill-library/project/.skills/env-report/SKILL.md` (new), `Examples/skill-library/user/_partials/header.md` (rewritten prose + added a literal `$0` line for the decision #16 case). Updated `SkillDiscoveryTests.expectedFixtureIDs` and `FixtureLibraryTests.happyPathFixtures` to include `env-report` (both enumerate the real fixture tree and would otherwise fail/miss coverage after the new fixture landed).

    `swift build` and `swift test`: exit 0, 110/110 tests passing (12 new in StencilPassTests.swift; existing 98 still green).
  timestamp: 2026-07-29T07:38:38.433516+00:00
- actor: claude-code
  id: 01kypdmdhp7h38ysgyp0r9datv
  text: |-
    Adversarial double-check (round 1) found a real bug: `StencilPass.namedArguments(for:)` used `zip(request.argumentNames, positionalArguments)`, which silently drops any declared argument name past the number of actually-supplied positional values. A skill declaring `arguments: [HOME]` (or any name colliding with a real env var) with fewer/no arguments actually supplied would leave that key unset at the explicit-context rung, letting the real environment value leak through `{{ HOME }}` — contradicting both the doc comment's own claim that `$name` and `{{ name }}` "always agree" and `ArgumentSubstitution`'s own `.named` branch, which always substitutes `""` for an unsupplied declared name.

    Fixed via TDD: added `declaredArgumentNameWithNoSuppliedValueRendersEmptyRatherThanLeakingEnvironment` to StencilPassTests.swift, confirmed it failed for the right reason (rendered "/Users/leaked" instead of ""), then rewrote `namedArguments(for:)` to iterate `argumentNames.enumerated()` and look up `positionalArguments[safe: index] ?? ""` per name — every declared name is now always set (empty when unsupplied), matching ArgumentSubstitution's own algorithm exactly. Widened `Array.subscript(safe:)` in ArgumentSubstitution.swift from `fileprivate` to internal (same treatment already given to `shellStyleTokens`) so StencilPass can reuse the identical bounds-checked lookup rather than duplicating it.

    `swift build` + `swift test`: exit 0, 111/111 tests passing (13 in StencilPassTests.swift now).
  timestamp: 2026-07-29T07:50:09.718082+00:00
- actor: claude-code
  id: 01kype8b6r8n3v3m2a4j4bxvff
  text: |-
    Adversarial double-check round 2 (the bounded loop's final permitted round, per really-done's contract) confirmed the round-1 fix was correct and complete, and surfaced one further low-severity finding: `StencilPass.namedArguments(for:)` did not handle a skill declaring a *duplicate* `arguments:` name (e.g. `[foo, bar, foo]`). `ArgumentSubstitution`'s `.named` branch always resolves `$name` via `argumentNames.firstIndex(of: name)` (the name's first occurrence), but the round-1 index-based rewrite set `context.set(key:to:)` once per array position, so a later duplicate occurrence's value silently overwrote the first via last-write-wins — `{{ name }}` would resolve to the *last* occurrence while `$name` resolves to the *first*, again contradicting the "always agree" doc-comment claim. Narrow (requires a malformed/unusual duplicate-name declaration nothing currently validates against) and not a security leak (both branches always resolve to a real supplied value, never environment/well-known state) — but cheap to fix and directly in the same function just touched, so fixed now rather than deferred to a follow-up task.

    Fixed via TDD: added `duplicateArgumentNameResolvesToItsFirstOccurrencePositionMatchingPassOne` to StencilPassTests.swift, confirmed RED (rendered "third" instead of "first"), then rewrote `namedArguments(for:)` to track a `seenNames` set and `compactMap` away every occurrence past a name's first, so each distinct name is paired with its first-occurrence position exactly once — matching `ArgumentSubstitution.firstIndex(of:)` semantics precisely, with no overwrite possible.

    Per really-done's bounded double-check loop (spawn findings-driven re-check "at most once"), round 2 was that one permitted re-spawn; this fix is not being sent through a third round — verified instead via fresh `swift build` + `swift test`: exit 0, 112/112 tests passing (14 in StencilPassTests.swift). Both the argument-leak (round 1) and duplicate-name (round 2) findings are now fixed and covered by dedicated regression tests, not just documented as deferred risk.

    Task remains in `doing`, ready for `/review`.
  timestamp: 2026-07-29T08:01:02.680176+00:00
depends_on:
- 01KYNCTMRAN6DEBBJGV5GE1MNN
position_column: doing
position_ordinal: '80'
title: 'Render pass 3: TemplateEngine wiring (trust, ladder, partials)'
---
## What
Implement §5 pass 3 via Extras' `TemplateEngine` (decisions #1/#2/#29 — #29 as amended: roots are host-supplied), replacing the identity transform.

- `Sources/FoundationModelsSkills/Render/StencilPass.swift`:
  - Build the `TemplateContext`: explicit context (skill arguments land here too) > environment variables as flat keys (`{{ HOME }}`) > well-known values (`working_directory`, `date`, `hostname`, `dotfolder_name`) — Extras' precedence ladder; read Extras' `TemplateEngine`/`TemplateContext`/`Trust` API first and use it, never raw Stencil.
  - Trust from the skill's winning root: defaults root → `.trusted`; user/project roots → `.untrusted` (whitelist + include-depth 8 + 1 MiB output + 100k-iteration budgets come from Extras). With host-supplied roots, "defaults" = the root the host designated as shipped defaults (lowest precedence); expose the trust mapping as data (root → Trust) with that default rule, so a host can override per root.
  - `{% include "header" %}` resolves through the layered `_partials/` directories of the SAME host-supplied roots, later roots winning — read Extras' `DotfolderLoader` seam and construct its include resolution over these roots (not over a stack Extras derives itself).
  - Because pass 1 ran before Stencil, `$`-tokens inside partial files are never argument-substituted (decision #16) — cover with a test, not code.
  - Add fixture `Examples/skill-library/project/.skills/env-report/SKILL.md` — `{{ HOME }}` / `{{ working_directory }}` ladder rendering; ensure `user/_partials/header.md` is exercised by a fixture body using `{% include "header" %}`.

## Acceptance Criteria
- [x] `env-report` golden render resolves env + well-known values through the ladder (env injected explicitly in tests for determinism)
- [x] A project-root skill using a non-whitelisted Stencil tag draws the untrusted-rejection diagnostic (§13 named case)
- [x] `{% include "header" %}` renders the partial from the correct (nearest-winning) root; a `$0` inside the partial stays literal
- [x] Defaults-root fixture renders trusted (same tag allowed); the root→Trust mapping is overridable per root

## Tests
- [x] `Tests/FoundationModelsSkillsTests/StencilPassTests.swift` — ladder precedence table; trust-mapping matrix incl. override; include + partial `$`-literal case; untrusted-rejection diagnostic — all through Extras' REAL TemplateEngine, no mocks (plan §13)
- [x] `swift test` — exit 0 (112/112 tests passing)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Implementation notes
`TemplateEngine`'s only public initializer always uses real process environment/well-known values (its hermetic seam is module-internal to Extras), so `StencilPass` builds the entire 3-rung ladder itself into one `TemplateContext` before handing it to `TemplateEngine.render`, which makes deterministic tests possible without any Extras-side hook. `DotfolderLoader` is not public API either; partial resolution is reached by constructing a `DotfolderStack` directly (via its public mutable `layers` property) over the host-supplied roots. See task comments for full research notes, two fixture/test bugs found and fixed during initial TDD, and two further correctness bugs found and fixed across two rounds of adversarial double-check (an argument-name/environment leak, and a duplicate-argument-name resolution mismatch) — both now covered by dedicated regression tests.