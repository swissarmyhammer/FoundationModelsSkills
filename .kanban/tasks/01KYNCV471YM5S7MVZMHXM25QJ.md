---
comments:
- actor: claude-code
  id: 01kyp956hsxtwne9gz5t80vx0g
  text: |-
    Implemented via TDD (RED confirmed: ShellInjectionTests.swift failed to compile before ShellInjection.swift existed; GREEN: all tests pass after implementation).

    What landed:
    - Sources/FoundationModelsSkills/Render/ShellInjection.swift: pass 2. Single combined NSRegularExpression with named groups (prefix/inlineCommand/fencedCommand) discriminates inline `` !`command` `` (prefix group requires start-of-text or whitespace immediately before `!`, so mid-word never matches) from fenced ```! blocks (anchored per-line via .anchorsMatchLines). Runs via /bin/sh -c, cwd = RenderRequest.skillDirectory, env fully inherited (Process.environment left nil), merged stdout+stderr via one Pipe, trailing newlines trimmed (POSIX $(...) parity). isShellExecutionDisabled substitutes ShellInjection.disabledMarker ("[shell execution disabled]") instead of running. No caching -- each render(_:request:) call re-executes, proven by a counter-file test. Algorithm mirrors ArgumentSubstitution's single left-to-right scan over the untouched input text, so injected shell output structurally can never be re-scanned (matches are computed once before any splicing).
    - Sources/FoundationModelsSkills/Render/NamedCaptureGroup.swift: extracted the named-capture-group text lookup shared by ArgumentSubstitution and ShellInjection into one helper, removing what would otherwise have been a near-duplicate private method in the new file (ArgumentSubstitution.swift refactored to use it too; no behavior change, its own test suite still green).
    - Examples/skill-library/project/.skills/git-context/SKILL.md: preload: true + a deterministic `echo` injection (task explicitly said to avoid `git status` for stable unit-test output, even though plan.md's fixture-library table elsewhere describes this fixture as eventually using `git status`).
    - Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift: recognition grammar table (6 cases incl. mid-word rejection), real execution (merged output, cwd via `pwd`, inherited env via setenv), disabled-policy inert marker proven with a touched-file side-effect probe, re-execution/no-caching proven with a counter file, body-only proven end-to-end through a real RenderPipeline + real ShellInjection instance (not just the pre-existing RecordingPass fakes in RenderPipelineTests), and a full-pipeline no-re-scan test where a shell command inlines a sentinel file containing literal $0 / `` !`echo hi` `` / {{ HOME }} and none of the three get reprocessed.

    Verification: `swift build` exit 0; `swift test` exit 0, 88/88 tests green across 6 suites (no regressions in the other 5 suites).

    Note on naming: task description said `disableShellExecution`; used the already-renamed `RenderPolicy.isShellExecutionDisabled` per this task's own instructions (the rename landed in the prior render-pipeline-skeleton task's review round).

    Local automated review (`review working`) flagged 8 findings: several about ArgumentSubstitution/ShellInjection not shell-escaping substituted arguments before injection, and several about omitted first-parameter labels on `render(_:request:)`/`classify(_:in:)`/`trimmingTrailingNewlines(_:)`/`shellStyleTokens(_:)`. Judged out of scope / inapplicable: shell injection's lack of escaping is the documented, intentional feature (plan.md §8 / decision #28's explicit "scrubbing would be theater" stance, mirroring Claude Code's own `!command` syntax) rather than a defect; `render(_:request:)`'s label is fixed by the `RenderPass` protocol requirement in RenderPipeline.swift (relabeling it would not compile); the other three helpers' omitted labels mirror ArgumentSubstitution.swift's own pre-existing, already-reviewed `classify(_:in:)`/`shellStyleTokens(_:)` shape, kept for consistency rather than diverging style between two sibling passes. Sent for independent adversarial double-check per really-done's process before finalizing.
  timestamp: 2026-07-29T06:31:56.729327+00:00
- actor: claude-code
  id: 01kyp9f17nv4xqkdjxy40t2chh
  text: |-
    Adversarial double-check (really-done's required advisory gate): PASS, no findings.

    Independently verified: fresh `swift build`/`swift test` both green (88/88, 6 suites); hand-traced the injection regex against adjacent-injection, no-separator, mid-word, nested-backtick, and fenced-boundary edge cases -- all match the documented grammar; confirmed the no-re-scan guarantee is structural (matches computed once against the untouched input before any splicing, never re-invoked against the growing output); pulled the prior ^hxm25qj dependency task's (01KYNCTMRAN6DEBBJGV5GE1MNN, ArgumentSubstitution) full 5-round review history and confirmed shell-escaping-of-substituted-arguments was never raised there either, corroborating that the local `review working` findings on that topic are a scope misread against this codebase's documented (plan.md §5/§8, decision #28) unsandboxed trust model, not a live defect; confirmed the `render(_:request:)` label finding would break `RenderPass` protocol conformance if applied; confirmed the other omitted-label findings mirror ArgumentSubstitution.swift's own pre-existing, already-reviewed style.

    Leaving this task in `doing` (green, all subtasks checked) for `/review` to pick up, per the implement skill's contract -- not moving it to `review` myself.
  timestamp: 2026-07-29T06:37:18.965641+00:00
depends_on:
- 01KYNCTMRAN6DEBBJGV5GE1MNN
position_column: doing
position_ordinal: '80'
title: 'Render pass 2: shell injection (macOS, body-only)'
---
## What
Implement §5 pass 2 (decision #25), replacing the identity transform.

- `Sources/FoundationModelsSkills/Render/ShellInjection.swift`:
  - `` !`command` `` recognized only at line start or after whitespace; fenced ```` ```! ```` blocks run their contents.
  - Run via `/bin/sh -c` with cwd = the skill directory and inherited env; capture merged stdout+stderr; inline output as plain text at the injection site.
  - Output is NOT re-scanned by this or any later pass invocation of pass 2 (single-shot); it flows into pass 3 as literal text only if the pipeline order says so — follow the skeleton's no-re-scan contract: injected output is never re-scanned, so mark injected ranges and have the pipeline pass them through Stencil untouched.
  - Commands re-execute on EVERY render (each `use skill`, `/command`, CLI `use`); no caching.
  - `RenderPolicy.disableShellExecution` → the pass replaces each injection with a clear inert marker (e.g. `[shell execution disabled]`) instead of running.
  - Body-only: the pipeline already routes metadata renders around pass 2 — assert that here too (precondition or test).
  - Add the fixture `Examples/skill-library/project/.skills/git-context/SKILL.md` — `preload: true` + a `!`echo`-style deterministic injection (avoid `git status` in unit tests; keep output stable).

## Acceptance Criteria
- [x] Inline and fenced forms execute; mid-word `!`cmd`` does not
- [x] Injected output is never re-scanned (an injected `$0` / `` !`echo hi` `` / `{{ HOME }}` stays literal end-to-end through a full body render)
- [x] `disableShellExecution` renders inert markers, runs nothing (proven with a side-effect file probe)
- [x] Re-render re-executes (a counter file increments per render)

## Tests
- [x] `Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift` — recognition grammar table; execution; merged output; policy-off; re-execution; end-to-end no-re-scan through the full pipeline
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.