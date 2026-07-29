---
comments:
- actor: claude-code
  id: 01kypz4hp25j0cvxa2cfbpgsmx
  text: |-
    Research: read Extras' real SlashCommandProviding/SlashCommand/Invocation source (../FoundationModelsExtras/Sources/FoundationModelsExtras/{SlashCommandProviding,SlashCommand}.swift). The task's assumed shape matches the real API exactly, including the `.prompt(template:)` case name (SlashCommand.Body enum: `.prompt(template: String)` and `.action(@Sendable (Invocation) -> AsyncThrowingStream<String, Error>)`). No divergence to document.

    Design decisions:
    - commands(workingDirectory:) builds SlashCommand values from commandListing() rows (name=id, description, argumentHint). workingDirectory is unused/ignored, same pattern as Extras' own DemoCommandProvider example (commandListing() already resolves against the registry's construction-time roots, not a per-call directory).
    - argumentHint reuses the existing parameterSummary(_:) helper (widened from `private` to internal/module access in SkillsRegistry.swift so the new extension file can call it) rather than duplicating its placeholder-synthesis logic, joined space-separated in position order.
    - The `.prompt(template:)` body carries the skill's RAW unrendered body text (added a small internal `rawBody(id:) -> String?` accessor to SkillsRegistry.swift for this) -- not run through any of this package's own §5 render passes. This matches plan.md §7.1's caveat literally: "none of §5's passes 1-2 run" when the harness engine renders this template, and a full-fidelity host must call registry.call(id:arguments:) directly. Documented on the extension's own doc comment.
    - commandUpdates bridges onReload: a computed property that (when onReload is non-nil) spawns a Task iterating onReload and yielding a freshly recomputed slashCommands() list on each tick, cancelled via continuation.onTermination. Returns nil when watch:false (onReload nil), matching onReload's own contract.

    TDD: wrote Tests/FoundationModelsSkillsTests/SlashCommandProvidingTests.swift first (10 tests: command snapshot, user-invocable-only filtering, description passthrough, raw-unrendered-.prompt-body check, single/multi/unhinted/no-param argumentHint assembly, commandUpdates reload tick, watch:false -> nil commandUpdates). Confirmed RED (compile failure: "value of type SkillsRegistry has no member commands/commandUpdates") before implementing Sources/FoundationModelsSkills/Registry/SkillsRegistry+SlashCommands.swift. All 10 pass after implementation; full suite 183/183 green.

    Self-review pass applied for this project's five strict review categories (doc-comment convention, nesting depth, duplication, boolean naming, no caller/history narration in doc comments) -- revised two doc comments that named specific caller methods to instead describe semantics only.
  timestamp: 2026-07-29T12:56:04.034802+00:00
- actor: claude-code
  id: 01kypzaxnqk4cdseqqsk2xng07
  text: |-
    Adversarial double-check (per really-done) ran and returned REVISE: the doc comment on the SlashCommandProviding extension claims all three §5 passes (1: $-args, 2: shell injection, 3: Stencil) are absent from the .prompt template, but the original test only verified pass 1 inertness (via commit's $0/$ARGUMENTS). Everything else passed (Extras protocol shapes match, commandUpdates concurrency-safety confirmed via catalogBox's shared-reference-before-yield ordering, parameterSummary access widening justified, doc/nesting/duplication/boolean-naming all clean).

    Fix: added two tests to SlashCommandProvidingTests.swift using fixtures already in the stack -- commandsPreserveRawShellInjectionSyntaxUninterpretedInThePromptTemplate (asserts git-context's raw `` !`echo "on branch main, working tree clean"` `` backtick token survives unexecuted) and commandsPreserveRawStencilSyntaxUnrenderedInThePromptTemplate (asserts env-report's raw `{% include "header" %}`/`{{ HOME }}`/`{{ working_directory }}` Stencil tags survive unrendered). No production code changes needed -- rawBody(id:) was already correct; this closes the verification gap. Full suite: 185/185 green, `swift test` exit 0.
  timestamp: 2026-07-29T12:59:32.919137+00:00
- actor: claude-code
  id: 01kypzbkfdgwj6xjsvretxcnyc
  text: 'Done: implementation green, adversarial double-check''s one finding addressed, full suite 185/185 (`swift test` exit 0). Description checkboxes checked off. Left in `doing` per /implement''s process for /review to pick up.'
  timestamp: 2026-07-29T12:59:55.245386+00:00
depends_on:
- 01KYNCSXAEKDVR36H387H5TYXR
- 01KYND89QDD8BYQWGGPJ8Z4J2M
position_column: doing
position_ordinal: '80'
title: SlashCommandProviding conformance for the user surface
---
## What
Harness delivery channel (plan §6, decision #29): conform `SkillsRegistry` to Extras' `SlashCommandProviding`.

- `Sources/FoundationModelsSkills/Registry/SkillsRegistry+SlashCommands.swift`:
  - `commands(workingDirectory:)` derives `SlashCommand` values from `commandListing()` — name = id, description, `argumentHint` assembled from the §6.1 parsed parameters (placeholders in order, variadic tail rendered as `...`).
  - `commandUpdates` ticks on every registry reload (bridge `onReload`).
  - Read Extras' `SlashCommandProviding`/`SlashCommand`/`Invocation` declarations first and match their exact shapes — including the body kind. Where a `.prompt(template:)` body kind exists, document plainly (doc comment) that the harness engine runs none of §5 passes 1–2 and a full-fidelity host calls `registry.call(id:arguments:)` (§7.1 caveat).

## Acceptance Criteria
- [x] `commands(workingDirectory:)` over the fixture stack lists exactly the user-invocable skills with correct hints
- [x] A reload (temp-dir edit) produces a `commandUpdates` tick and a changed command set
- [x] The §7.1 caveat is documented on the conformance

## Tests
- [x] `Tests/FoundationModelsSkillsTests/SlashCommandProvidingTests.swift` — command snapshot; hint assembly cases; reload-tick case
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.