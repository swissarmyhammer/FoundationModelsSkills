---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2h15jj1xrwr2bcg13k94f9s
  text: |-
    ### Step 1 (Extras) — done by the Extras session
    - evidence: `DotfolderStack.Source.marketplace` is on FoundationModelsExtras `main` at d0048eb3f5c629554811c4bdaa68d00650cae63d (push 76b773b..d0048eb). New test `DotfolderStackTests.defaultInitNeverDerivesAMarketplaceLayer`. Extras `swift test`: 265 tests, 24 suites, 0 warnings. Extras had no exhaustive switch on `Source`; three doc comments in `LayeredYAMLDocument.swift` were updated.
    - next: ACPAgent is not changed yet. Its `ConfigurationLayerName.swift:29` switch breaks when it next resolves Extras `main`. Do step 2 (ACPAgent) first, then step 3 (this package).
  timestamp: 2026-09-14T22:38:55.553508+00:00
- actor: claude-code
  id: 01m2jfxz6vzm4z1wz10t45wasq
  text: |-
    ### Research — implement step
    - `Package.resolved` is ignored by Git in this repository (`.gitignore` has the line `Package.resolved`; `git ls-files Package.resolved` is empty). Thus the step "commit `Package.resolved`" cannot occur. I did not force-add the file. The build and the new test prove the pin.
    - The local `Package.resolved` already pins FoundationModelsExtras at d0048eb3f5c629554811c4bdaa68d00650cae63d. Remote `main` is also d0048eb (`git ls-remote`). `swift package update FoundationModelsExtras` gives "Everything is already up-to-date" and makes no change.
    - The checkout `.build/checkouts/FoundationModelsExtras` is at d0048eb and has `case marketplace` in `DotfolderStack.swift`.
    - `StencilPass.resolvedTrust(for:)` is `layer.source == .defaults ? .trusted : .untrusted`. Thus `.marketplace` is untrusted with no change.
    - Extras `TemplateEngine.untrustedAllowedTags` does not contain `now`. Thus `{% now %}` is rejected under `.untrusted` with `UntrustedTemplateError.tagNotAllowed(tag: "now")`, which the facade gives as `TemplateEngineError.renderingFailed`.
  timestamp: 2026-09-15T12:16:09.435482+00:00
- actor: claude-code
  id: 01m2jg2v18y68kjzwr86q3jjsk
  text: |-
    ### TDD record
    - I added two tests to `Tests/FoundationModelsSkillsTests/StencilPassTests.swift`: `marketplaceLayerDrawsTheUntrustedRejectionForTheNowTag` and `defaultsLayerRendersTheNowTagThatAMarketplaceLayerRejects`.
    - The behavior is already correct, so the tests pass against the unchanged code. To prove that the marketplace test can fail, I changed `resolvedTrust(for:)` for a short time to also give `.trusted` to `.marketplace`. Result: the marketplace test failed with "an error was expected but none was thrown and \"2026-09-15 at 07:18\" was returned". The defaults test passed. Then I removed the temporary change. `StencilPass.swift` has no change in the final diff.
    - What did not work: a `private static let` regex for the date shape. Swift 6 rejects it ("static property ... is not concurrency-safe because non-'Sendable' type 'Regex<Substring>'"). The regex is now a local constant in the test.
    - The defaults test matches the date shape (`\d{4}-\d{2}-\d{2} at \d{2}:\d{2}`, the Stencil default format), not a value. Thus it has no hard-coded time value and does not depend on the clock.
  timestamp: 2026-09-15T12:18:49.000421+00:00
- actor: claude-code
  id: 01m2jg9rdnxbypyw0vhxdpm3ey
  text: |-
    ### implement — changed
    - evidence: 1 file changed — `Tests/FoundationModelsSkillsTests/StencilPassTests.swift` (+46 lines: two tests, two documented `private static let` constants, labeled `#expect` messages). `StencilPass.swift` has no change. `swift build --build-tests`: 0 warnings. `swift test`: 434 tests in 34 suites passed, 0 failures, 0 warnings.
    - pin: the local `Package.resolved` pins FoundationModelsExtras at d0048eb3f5c629554811c4bdaa68d00650cae63d. `swift package update FoundationModelsExtras` gives "Everything is already up-to-date". `Package.resolved` is ignored by Git, so it is not in the diff and I did not force-add it. The build, which uses `DotfolderStack.Source.marketplace`, proves the pin.
    - rules check: the rules subagent did not report in time. I checked the new tests against the project rules myself: no `guard`; `#require(throws:)` and `#expect` with messages; no magic numbers except the regex digit counts, which a comment ties to the Stencil default format; no new public items.
    - next: `/review`. The task stays in `doing`. Nothing is committed.
  timestamp: 2026-09-15T12:22:35.701455+00:00
- actor: claude-code
  id: 01m2jghqxf0c937ge585ery9bq
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (2051176). 0 findings (confirmed 0, refuted 0, attempted 7, failed 0). 1 file reviewed: `Tests/FoundationModelsSkillsTests/StencilPassTests.swift`. 4 `.kanban/` files are excluded by `.reviewignore`. The description has no prior `## Review Findings` section.
    - next: The task is in `done`. No work stays open.
  timestamp: 2026-09-15T12:26:57.327690+00:00
- actor: claude-code
  id: 01m2jgj6mh052sypfzdwdq3063
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 1 file (Tests/FoundationModelsSkillsTests/StencilPassTests.swift)
    - test: green — swift test, 434 passed, 0 failed, 0 skipped; swift build --build-tests, 0 warnings
    - commit: 2051176 test(render): prove a marketplace layer renders untrusted
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-15T12:27:12.401479+00:00
- actor: claude-code
  id: 01m2jgkzfaf48btpp3d6770rwy
  text: |-
    ### Rules report — late check
    The rules subagent reported after the step record. I checked the two new tests against each rule it quoted. Result: no change is necessary.
    - magic-numbers-swift: the new code has no numeric literal. The digit counts are inside one regex literal.
    - optionals / noGuardInTests: no `guard`, and no trailing `if let`. The tests use `#require(throws:)` and `#expect`.
    - noForceUnwrapInTests / noForceTryInTests / disallowed-constructs: no `!`, no `try!`, no `as!`, and no `print`.
    - casing / immutability: `nowTagBody` and `nowTagUntrustedRejection` are `lowerCamelCase` `static let`.
    - missing-docs-swift: no new `public` item. The private constants have doc comments.
    - swiftTestingTestCaseNames: the test names have no `test` prefix.
    - no-hard-code: the rejection text is in the expected-value position of an assertion.
    - no-test-cheating: each test has an assertion that can fail. The RED run proved this.
    - duplication / reuse: the two tests assert different results (an error, and a rendered date). They use the shared `render` and `request` helpers.
    The step record "implement — changed" is still correct.
  timestamp: 2026-09-15T12:28:10.602501+00:00
position_column: done
position_ordinal: c980
title: Pin Extras with DotfolderStack.Source.marketplace and prove it renders untrusted
---
## What

marketplace.md §4.3 and decision 8. The Extras session already added `DotfolderStack.Source.marketplace` on FoundationModelsExtras `main` at d0048eb3f5c629554811c4bdaa68d00650cae63d. The ACPAgent switch fix is a separate `cross-repo` task. This task is the in-repo part only.

- Run `swift package update FoundationModelsExtras` in this repository, and commit `Package.resolved`.
- `StencilPass.resolvedTrust(for:)` (`Sources/FoundationModelsSkills/Render/StencilPass.swift`) needs no change: every source except `.defaults` is untrusted. Add a test that proves this for `.marketplace`.

Note: `Package.resolved` is ignored by Git in this repository (`.gitignore`), so it cannot be committed. The local file pins d0048eb. The build and the new test prove the pin. See the comments.

- [x] Extras: `Source.marketplace` is on `main` at d0048eb (done by the Extras session)
- [x] Update the Extras pin in `Package.resolved` (the local file pins d0048eb; the file is ignored by Git)
- [x] Add the `.marketplace` trust test

## Acceptance Criteria
- [x] `Package.resolved` pins FoundationModelsExtras at d0048eb or later
- [x] `swift build` and `swift test` pass with zero warnings
- [x] A `.marketplace` layer renders through `TemplateEngine.Trust.untrusted` in `StencilPass`

## Tests
- [x] `Tests/FoundationModelsSkillsTests/StencilPassTests.swift`: a body with `{% now %}` in a `.marketplace` layer draws the untrusted-rejection error, and the same body in a `.defaults` layer renders
- [x] Run `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace