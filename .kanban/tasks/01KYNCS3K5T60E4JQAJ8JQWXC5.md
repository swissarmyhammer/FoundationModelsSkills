---
comments:
- actor: claude-code
  id: 01kyny6xrdyxgacvgwh4mvf2f5
  text: |-
    Implemented per /tdd. Wrote Tests/FoundationModelsSkillsTests/RenderPipelineTests.swift first (6 tests: fixed pass order 1->2->3 via a recording fake, metadata path never invoking pass 2, no-re-scan invariant via substituting+constant-output fakes, RenderPolicy plumbed to every invocation, plus two identity-pipeline smoke tests), confirmed RED (cannot find RenderPipeline/RenderPolicy in scope), then implemented Sources/FoundationModelsSkills/Render/RenderPipeline.swift to go GREEN.

    Design notes for the next tasks (pass 1/2/3, SkillsRegistry):
    - RenderRequest.winningLayer is FoundationModelsExtras' DotfolderStack.Layer (source + root) -- it is Sendable but NOT Equatable, so RenderRequest itself is Sendable-only, no Equatable conformance (kept RenderPolicy Equatable since tests need to compare it).
    - RenderPass protocol is minimal: just `func render(_ text: String, request: RenderRequest) throws -> String`. Did not add a `name` property to the protocol -- no downstream task description needed it, and test fakes can track their own name for recording purposes without it being part of the contract (avoided a wasted concept).
    - RenderPipeline holds three named `any RenderPass` properties (argumentSubstitution/shellInjection/stencil) rather than an array, matching the task's "each a RenderPass protocol value" framing; renderBody runs [1,2,3], renderMetadata runs [1,3], both via a shared private `run(passes:request:)` that threads output text through in order, exactly once per pass.
    - Added `RenderPipeline.identity` static convenience (three IdentityRenderPass instances) since it's the natural scaffold default for this task ("Passes are identity functions in this task") and will let SkillsRegistry (^7h5tyxr) construct a working pipeline before the real passes land.

    swift build: exit 0, no new warnings (only the pre-existing foundationmodelsoperationtool package-identity warning already noted in Package.swift's own comments). swift test: 62/62 passed, exit 0 (56 pre-existing + 6 new).
  timestamp: 2026-07-29T03:20:38.925213+00:00
- actor: claude-code
  id: 01kynyzhk9kx7zb97s5f7shnm2
  text: |-
    Adversarial double-check (via really-done) returned REVISE with 5 findings; addressed the actionable ones, logging disposition here per really-done's contract:

    1. (High) Doc comment convention violated in 5 places in RenderPipeline.swift (RenderRequest.arguments, and the three RenderPipeline pass properties argumentSubstitution/shellInjection/stencil, plus .identity) -- summary sentence ran straight into elaboration with no blank `///` line. Fixed all 5 by inserting the blank `///` separator, matching the rest of the file.

    2. (Medium) The no-re-scan test (`laterPassOutputContainingPassOneSyntaxIsNotReSubstituted`) only proved the pipeline threads output through sequentially, not that pass 1 specifically ran (a regression that skipped pass 1 entirely would have passed the old assertion too). Fixed: `SubstitutingPass` now takes an `InvocationRecorder` and the test asserts it ran exactly once, in addition to the output assertion. Verified this is a real regression guard: temporarily patched `renderBody` to run `[shellInjection, stencil]` (skipping pass 1), reran just this test, watched it fail red (`recorder.invocations.map(\.name) -> []`, expected `["argumentSubstitution"]`), then restored the file from a backup and confirmed `swift build`/`swift test` are clean again (byte-identical restore, diff empty).

    3. (Low-Medium) RenderPolicy plumbing was only tested for `renderBody` (3 invocations), not `renderMetadata` (2 invocations). Fixed: split the single test into `renderPolicyIsPlumbedToEveryBodyPassInvocation` and a new `renderPolicyIsPlumbedToEveryMetadataPassInvocation`, both asserting every recorded invocation's policy matches.

    4. (Low, informational) `RenderPipeline.identity` flagged as scope beyond the four acceptance criteria -- kept it: it's the natural scaffold default this task's own description calls for ("Passes are identity functions in this task"), costs nothing, and unblocks SkillsRegistry (^7h5tyxr) construction before the real passes land. No action taken, justification logged here per really-done's "proceed past REVISE findings with logged justification" allowance.

    5. (Low, informational) RenderRequest's "Immutable per invocation" doc overstated a guarantee the type itself doesn't enforce (fields are `var`). Fixed: reworded to "Not mutated by RenderPipeline during a render call" -- accurate to what the code actually guarantees.

    Final state: swift build exit 0 (no new warnings); swift test 63/63 passed, exit 0 (56 pre-existing + 7 new -- the policy test split added one net test vs. the original 6). Re-ran really-done's verification command fresh after every edit round per its Iron Law.
  timestamp: 2026-07-29T03:34:05.673924+00:00
depends_on:
- 01KYNCR37A3M7MYKAH7T0QREYS
position_column: doing
position_ordinal: '80'
title: Render pipeline skeleton (ordered passes, identity transforms)
---
## What
The M2 render scaffold (plan §5): wire the three-pass pipeline shape with identity transforms so ordering, single-shot semantics, and the body/metadata split are fixed before real pass logic lands.

- `Sources/FoundationModelsSkills/Render/RenderPipeline.swift`:
  - `RenderRequest` (skill body or metadata value, arguments, skill directory, winning layer, policy).
  - Ordered passes: (1) argument/variable substitution, (2) shell injection, (3) Stencil — each a `RenderPass` protocol value; passes run once, output of pass N is NEVER re-scanned by pass N or earlier (plan: single-shot, no re-scanning).
  - Two pass-sets: body render = passes 1+2+3; `description`/`metadata` render = passes 1+3 only (shell never runs at metadata-build time, decision #25).
  - `RenderPolicy` struct holding `disableShellExecution` and `disableScriptExecution` (consumed later; lives here so the registry can own it at construction, decisions #25/#28).
- Passes are identity functions in this task; each later render task replaces one.

## Acceptance Criteria
- [x] Pipeline runs passes in fixed order 1→2→3 (observable via a recording fake pass)
- [x] Metadata render path never invokes pass 2
- [x] A pass output containing pass-1 syntax (e.g. `$0`) is not re-substituted
- [x] `RenderPolicy` is plumbed to every pass invocation

## Tests
- [x] `Tests/FoundationModelsSkillsTests/RenderPipelineTests.swift` — order recording; metadata-path pass-set; no-re-scan invariant with identity+marker fakes
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.