---
position_column: todo
position_ordinal: '8680'
title: 'Harden span-based rendering: shared budgets, straddling blocks, span-edge grammar'
---
## What
The no-re-scan quarantine (0d2e736) is structurally sound, but per-span rendering introduced three defects:

1. **Untrusted budget multiplication (security-relevant)**: `StencilPass` calls `engine.render` once per `.original` span (`Render/StencilPass.swift:113-115`), and Extras' `TemplateEngine` allocates fresh budgets per call (1 MiB output / 100k iterations / depth 8). An N-span body gets N× every limit — and spans are free to mint: `$1` with NO arguments supplied still emits an empty `.quarantined("")` (`ArgumentSubstitution.swift:116` → `QuarantinedText.swift:106-109`), so an untrusted project-layer skill can split itself arbitrarily. Fix: skip empty quarantined spans in `QuarantinedText`, and thread ONE shared budget across a render call (coordinate with Extras if the engine API needs a budget-in parameter; otherwise cap total spans/aggregate output locally).
2. **Stencil blocks straddling a splice now throw**: `{% if x %}…$1…{% endif %}` renders the first fragment alone → `TemplateSyntaxError` → `TemplateEngineError.renderingFailed`, even with no arguments (empty splice). Documented as deliberate (`StencilPass.swift:90-93`) but NO test pins it, and existing skills using the pattern silently break. Decide: accept (then pin with a test + document in README/plan §5) or repair (e.g. render across spans with quarantined content injected as an opaque context variable). Either way the behavior must be pinned and disclosed.
3. **Injection grammar widened at span boundaries**: `ShellInjection.injectedSpans` matches `(?<prefix>^|\s)` per span in isolation (`ShellInjection.swift:84-103`), so `^` matches at span-local starts — body `` abc$1!`cmd` `` now EXECUTES although the flattened text is mid-word (must not match). Command text is always original body text (not model-argument escalation), but the grammar is §5-divergent. Fix: carry the preceding flattened character across the span boundary; same for the fenced ```` ```! ```` start-of-line anchor.

Also (tiny, same file): `StencilPass.swift:285-286` claims to mirror Extras' `projectDotfolderName` but uses `.last(where:)` vs Extras' `.first(where:)` — correct the comment; and add the missing end-to-end `dotfolder_name` test for the `init(stack:)` constructor.

## Acceptance Criteria
- [ ] A 50-splice untrusted body cannot exceed the single-render output/iteration budgets (test with a repeated-`$N` fixture)
- [ ] Empty quarantined spans no longer split original spans
- [ ] Straddling-block behavior decided, pinned by a test, and documented
- [ ] `` abc$1!`cmd` `` does not execute; line-start/whitespace-preceded forms still do (span-boundary matrix)
- [ ] `init(stack:)` `dotfolder_name` end-to-end test; comment corrected

## Tests
- [ ] Extend `RenderPipelineNoRescanTests` / `ShellInjectionTests` / `StencilPassTests` per criteria — all through real passes
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.