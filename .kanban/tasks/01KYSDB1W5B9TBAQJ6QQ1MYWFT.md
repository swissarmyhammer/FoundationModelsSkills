---
comments:
- actor: claude-code
  id: 01m0z3nzwkcastpfvb1c48hxz0
  text: |-
    ### research
    - `TemplateEngine.render(_:context:trust:)` (Extras) makes new budget objects in each call (`TemplateEngine.swift:143-145`). The public API has no budget-in parameter. Plan: `StencilPass` makes ONE `render` call for each pass. It joins all spans into one template. Each `.quarantined` span becomes a `{{ <key> }}` reference to a context value. This gives one shared budget and lets a Stencil block straddle a splice.
    - Adjacency hazard: an `.original` span that ends with `{` before a placeholder makes `{{{`. Plan: move the trailing `{` characters into the quarantined value (they are always literal text there).
    - `SpanBuilder.appendQuarantined("")` writes an empty span (`QuarantinedText.swift:106-109`). Plan: skip empty values in `SpanBuilder`, and make `QuarantinedText.init(spans:)` drop empty spans and join adjacent `.original` spans.
    - `ShellInjection.injectionPattern` uses `(?<prefix>^|\s)` per span. Plan: `QuarantinedText` gives each transform the character that precedes the span in the flattened text. `ShellInjection` scans `preceding + text` with `.withTransparentBounds` and `.withoutAnchoringBounds`, and a lookbehind `(?<![^\s])` replaces the `prefix` group.
    - Extras' `DotfolderStack.projectDotfolderName` (`TemplateEngine.swift:915`) uses `.first(where:)` over a stack that has one `.project` layer. `StencilPass.WellKnownValues.projectDotfolderName` uses `.last(where:)` because `init(roots:)` tags every root `.project`. The comment must state the difference, not claim a mirror.
    - `SkillsRegistry.init(stack:)` (`SkillsRegistry.swift:268`) has no `dotfolder_name` end-to-end test. `DotfolderStack.init` appends `<workingDirectory>/.<name>` as the `.project` layer.
  timestamp: 2026-08-26T13:20:49.043958+00:00
- actor: claude-code
  id: 01m0z47t7y5jav8xwr4asaehq8
  text: |-
    ### implementation
    Decision for defect 2: REPAIR. `StencilPass` renders the whole text as ONE template. Each `.quarantined` span becomes a `{{ stencilPassQuarantinedSpan<N> }}` reference to an opaque context value. Result: one render call, one budget set, and a `{% if %}...{% endif %}` block can straddle a splice.

    What did not work:
    - Stencil's lexer is not quote-aware. A reference inside `{{ ... }}` (`{{ $0 }}` -> `{{ {{ key }} }}`) rendered as an empty variable plus a literal ` }}`, with no error. `{% if $0 %}` threw only because the `if` parser rejected it. So the pass now refuses a splice inside an open `{{`, `{%`, or `{#` pair itself, with `TemplateEngineError.renderingFailed`, before Stencil runs. This is the same result for every delimiter form, and it is documented in `StencilPass`, README, and plan §5.
    - A bare `{` before a splice fused with the reference (`{$0}` -> `{{{ key }}}`). The pass moves a trailing run of `{` into the spliced value. `{$1}` renders `{value}`.

    Other changes:
    - `QuarantinedText.init(spans:)` drops empty spans and joins adjacent `.original` spans; `SpanBuilder.appendQuarantined` skips an empty value.
    - `QuarantinedText.mappingOriginalSpans` has an overload that passes the character before each span. `ShellInjection` scans `preceding + text` with `.withTransparentBounds` and `.withoutAnchoringBounds`; the inline anchor is now the lookbehind `(?<![^\s])`, so no prefix text is consumed or re-emitted.
    - `StencilPass.WellKnownValues.projectDotfolderName` comment states the deliberate `.last` vs Extras' `.first` difference.
    - New tests: 50-splice iteration and output budget fixtures, empty-span coalescing, straddling block, brace adjacency, delimiter-error matrix, quarantine-key collision, span-boundary shell matrix with a `touch` probe, `init(stack:)` `dotfolder_name` end to end.

    ### implement — changed
    - evidence: 9 files — Sources/FoundationModelsSkills/Render/QuarantinedText.swift, Sources/FoundationModelsSkills/Render/ShellInjection.swift, Sources/FoundationModelsSkills/Render/StencilPass.swift, Tests/FoundationModelsSkillsTests/RenderPipelineNoRescanTests.swift, Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift, Tests/FoundationModelsSkillsTests/StencilPassTests.swift, README.md, plan.md, .kanban task card. `swift test`: 349 tests in 23 suites passed, exit 0.
    - next: test, commit, review
  timestamp: 2026-08-26T13:30:33.086954+00:00
- actor: claude-code
  id: 01m0z4d99y3xqvy7yanvj8x0by
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 08527af) — 0 findings, 0 confirmed, 0 refuted; 6 files reviewed, 4 `.kanban/` files excluded by `.reviewignore`. No prior `## Review Findings` section on the card.
    - next: move to done
  timestamp: 2026-08-26T13:33:32.350450+00:00
- actor: claude-code
  id: 01m0z4df6krcg0yc4f90x66xvm
  text: |-
    ### finish iteration 1 — review clean, task moved to done
    - implement: changed — 9 files (QuarantinedText, ShellInjection, StencilPass, three test files, README, plan, card)
    - test: green — `swift test` 349 tests in 23 suites passed, 0 warnings; 1 env-gated live-model skip already tracked (^tb86z9q)
    - commit: 08527af
    - review: clean — `review sha HEAD~1..HEAD`, 0 findings
  timestamp: 2026-08-26T13:33:38.387065+00:00
position_column: done
position_ordinal: ab80
title: 'Harden span-based rendering: shared budgets, straddling blocks, span-edge grammar'
---
## What
The no-re-scan quarantine (0d2e736) is structurally sound, but per-span rendering introduced three defects:

1. **Untrusted budget multiplication (security-relevant)**: `StencilPass` calls `engine.render` once per `.original` span (`Render/StencilPass.swift:113-115`), and Extras' `TemplateEngine` allocates fresh budgets per call (1 MiB output / 100k iterations / depth 8). An N-span body gets N× every limit — and spans are free to mint: `$1` with NO arguments supplied still emits an empty `.quarantined("")` (`ArgumentSubstitution.swift:116` → `QuarantinedText.swift:106-109`), so an untrusted project-layer skill can split itself arbitrarily. Fix: skip empty quarantined spans in `QuarantinedText`, and thread ONE shared budget across a render call (coordinate with Extras if the engine API needs a budget-in parameter; otherwise cap total spans/aggregate output locally).
2. **Stencil blocks straddling a splice now throw**: `{% if x %}…$1…{% endif %}` renders the first fragment alone → `TemplateSyntaxError` → `TemplateEngineError.renderingFailed`, even with no arguments (empty splice). Documented as deliberate (`StencilPass.swift:90-93`) but NO test pins it, and existing skills using the pattern silently break. Decide: accept (then pin with a test + document in README/plan §5) or repair (e.g. render across spans with quarantined content injected as an opaque context variable). Either way the behavior must be pinned and disclosed.
3. **Injection grammar widened at span boundaries**: `ShellInjection.injectedSpans` matches `(?<prefix>^|\s)` per span in isolation (`ShellInjection.swift:84-103`), so `^` matches at span-local starts — body `` abc$1!`cmd` `` now EXECUTES although the flattened text is mid-word (must not match). Command text is always original body text (not model-argument escalation), but the grammar is §5-divergent. Fix: carry the preceding flattened character across the span boundary; same for the fenced ```` ```! ```` start-of-line anchor.

Also (tiny, same file): `StencilPass.swift:285-286` claims to mirror Extras' `projectDotfolderName` but uses `.last(where:)` vs Extras' `.first(where:)` — correct the comment; and add the missing end-to-end `dotfolder_name` test for the `init(stack:)` constructor.

## Acceptance Criteria
- [x] A 50-splice untrusted body cannot exceed the single-render output/iteration budgets (test with a repeated-`$N` fixture)
- [x] Empty quarantined spans no longer split original spans
- [x] Straddling-block behavior decided, pinned by a test, and documented
- [x] `` abc$1!`cmd` `` does not execute; line-start/whitespace-preceded forms still do (span-boundary matrix)
- [x] `init(stack:)` `dotfolder_name` end-to-end test; comment corrected

## Tests
- [x] Extend `RenderPipelineNoRescanTests` / `ShellInjectionTests` / `StencilPassTests` per criteria — all through real passes
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.