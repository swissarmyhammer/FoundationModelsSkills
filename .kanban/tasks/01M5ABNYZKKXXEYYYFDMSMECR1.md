---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5adm6gpwjdf26msqy59c169
  text: |-
    Research (implement):
    - Extras resolved at 23baf04 (`swift package update FoundationModelsExtras`; Package.resolved is gitignored, Package.swift tracks main).
    - Every surface reads ONE catalog: `SkillsRegistry.buildCatalog` folds `SkillDiscovery.discover()` with `skillDocuments(layers:)` (the FrontmatterDocumentStack read). `metadata()` (model list, tool description, search agent seed and reloads), `commandListing()` (user `/` menu, CLI), `call(id:)`, `preloadedBodies()` and the resource ops (by id) all read that catalog. A disabled skill left out of the catalog is thus gone from every surface, and an unknown/disabled id hits the same `UnusableSkillIDText` corrective.
    - DECISION: the user `/` listing and the CLI hide a disabled skill too. The one shared catalog makes the choice, and it matches the rule "the disabled view is for UIs only": the full `items` view with `enablement` is for a settings UI, which this package does not have. No second catalog is added.
    - `onDiagnostic` of the document stack is NOT wired today (default no-op), so Extras diagnostics never reach `SkillsRegistry.diagnostics`. The invalid-value diagnostic can be built from `document.enablement == .invalid(message)` in buildCatalog, with the skill id and the winning-layer provenance. That gives exactly one diagnostic without a lock box around a @Sendable hook.
    - Trap: `enabledItems` alone would make a disabled id look like an unreadable SKILL.md (no document) and raise the `.skip` "SKILL.md could not be read" diagnostic. Calling both `items` and `enabledItems` reads every file twice and reports an invalid value twice. So the read stays one `items` call, and buildCatalog skips a document that is not `isEnabled` (the same filter `enabledItems` applies).
    - Trap: `SkillFrontmatter` does not know the `enabled` key, so `enabled: true` would raise an "unknown top-level keys" advisory. Add `FrontmatterEnablement.key` to the known keys.
  timestamp: 2026-10-19T15:49:02.102422+00:00
- actor: claude-code
  id: 01m5adw5905th4fnk2c1tn6t4v
  text: |-
    Implementation landed (TDD).
    - RED: 12 new tests, 11 failed for the expected reason (disabled skill still in metadata/description/search/preload/`/` menu, corrective differed, invalid value loaded, `enabled: true` raised an unknown-key advisory, flip posted no notice). `aSkillWithNoEnabledKeyIsOn` passed on RED: it pins existing behavior, as the card lists it.
    - GREEN: `SkillsRegistry.validate` returns nil for a document that is not `isEnabled`; `.invalid(message)` adds one `.skip` SkillDiagnostic with the Extras text and the winning-layer provenance. A new `skipDiagnostic(discovered:marketplaces:message:)` helper also builds the unreadable-file diagnostic. `SkillFrontmatter.knownTopLevelKeys` adds `FrontmatterEnablement.key`.
    - Not done on purpose: `enabledItems(in:named:)` is not called, because it hides the difference between "off" and "unreadable"; the read stays one `items` call and validate applies the same `isEnabled` filter (doc comment on `skillDocuments` says why). `onDiagnostic` stays unwired: the invalid diagnostic comes from `document.enablement`, so exactly one appears.
    - Docs: docs/operations.md gets a Visibility row and a "Turn a skill off" section with the `/` menu decision; docs/marketplaces.md gets the stub example.
    - Build output carries one SwiftPM warning, `missing creator for mutated node: ... mlx-swift_Cmlx.bundle/Contents/MacOS`. It comes from the build system for the mlx bundle, not from source in this package; the Extras board records the same Swift Build metal warning.
    - Open: "Send the sha to foundationmodelsacpagent-a5 when it is on origin/main" waits for the commit step.
  timestamp: 2026-10-19T15:53:22.976064+00:00
- actor: claude-code
  id: 01m5adw78jqgh0p1wcw7r559ra
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Sources/FoundationModelsSkills/Frontmatter/SkillFrontmatter.swift, Tests/FoundationModelsSkillsTests/SkillEnablementTests.swift (new), Tests/FoundationModelsSkillsTests/SkillsCatalogNoticeTests.swift, docs/operations.md, docs/marketplaces.md; `swift test` 656 tests in 60 suites passed, 0 failures; Extras resolved at 23baf04
    - next: /review; after commit, send the sha to foundationmodelsacpagent-a5
  timestamp: 2026-10-19T15:53:25.010136+00:00
- actor: claude-code
  id: 01m5adxkf23pp6vv73gycpk9ps
  text: |-
    ### test — green
    - evidence: swift test — 656 tests in 60 suites passed, 0 failed, 0 skipped; only build warning is the known mlx-swift_Cmlx.bundle "missing creator for mutated node" (dependency, not fixed); no package warnings
    - next: review
  timestamp: 2026-10-19T15:54:10.274124+00:00
- actor: claude-code
  id: 01m5ady134f7qqd52bhgmsx3qv
  text: |-
    ### commit — changed
    - evidence: a91e8d1 feat(skills): show only enabled skills to the model via the `enabled` frontmatter key
    - next: review
  timestamp: 2026-10-19T15:54:24.228389+00:00
- actor: claude-code
  id: 01m5ae2ndj9w1zqxkyssfbf4er
  text: |-
    ### review — clean
    - evidence: no findings — `review sha HEAD~1..HEAD` (a91e8d1): counts findings 0, confirmed 0, refuted 0, attempted 7, failed 0. Not reviewed: .kanban/ (.reviewignore); docs/operations.md and docs/marketplaces.md (no validator matched). Shadowing checked: the `items` read gives one winner per id, and `validate` drops a winner that is off at `guard document.isEnabled`, so the lower copy cannot come back. Covered by SkillEnablementTests `aHigherStubThatTurnsASkillOffHidesTheLowerCopy`.
    - next: moved to done. Sending the sha to foundationmodelsacpagent-a5 once it is on origin/main is outside the pipeline.
  timestamp: 2026-10-19T15:56:56.114411+00:00
- actor: claude-code
  id: 01m5ae30p889eejf9xgxe5a1fq
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 6 files (SkillsRegistry, SkillFrontmatter, SkillEnablementTests, SkillsCatalogNoticeTests, docs)
    - test: green — swift test, 656 tests in 60 suites
    - commit: a91e8d1
    - review: clean — no findings; the task is in done
  timestamp: 2026-10-19T15:57:07.656725+00:00
depends_on:
- 01M5A7ZGHC7Y1KY81E8C5KPNWV
- 01M5A84CYKC62A5H2MMWFHKW3J
position_column: done
position_ordinal: ffa480
title: Show only enabled skills to the model, using the Extras `enabled` frontmatter key
---
#skills #extras

## What
Requested by foundationmodelsacpagent-a5 on 2026-10-19. The API is FoundationModelsExtras 23baf04 (on its origin/main): frontmatter `enabled: true|false`, default true, for skills, agents and rules.

Extras API (FrontmatterDocumentStack; the skills read is at SkillsRegistry.swift:779):
- `documents.enabledItems(in:named: "SKILL.md")` or `enabledTree(_:)` replace `items`/`tree` when the model-visible catalog is built.
- Shadowing runs first. A nearer stub that holds only `---\nenabled: false\n---` hides a lower skill of the same name (marketplace or built-in), and the lower copy does not come back.
- `items`/`tree`/`item(at:)` still give every document. Each one carries `enablement` (`.enabled`, `.disabled` or `.invalid(msg)`) and `isEnabled`. A missing key is on. A value that is not a bool fails closed: the skill is off, with one diagnostic through onDiagnostic.
- A disabled document gives no decode diagnostic.

## Requirements
- The model-visible catalog, the `skills` tool description list, `search skill`, `use skill`, and the preload use only enabled skills.
- A disabled id gets the same corrective as an unknown id (the corrective from wfhkw3j).
- A change of `enabled` in a file is an ordinary reload. It posts the catalog-change notice through the c5kpnwv path: "Removed" when a skill turns off, "New" when it turns on.
- The disabled view is for UIs only. Decide whether the user `/` command listing hides disabled skills too; the request names only the model surface. Record the decision here.

## Decision
The user `/` command listing and the CLI hide a disabled skill too. The one shared catalog of `SkillsRegistry` makes the choice: `metadata()`, `commandListing()`, `call(id:)`, `preloadedBodies()` and the resource ops all read it, and a skill that is off is not in it. The view that holds a disabled skill (`FrontmatterDocumentStack.items`, with `enablement`) is for a settings UI, which this package does not have. Recorded in docs/operations.md, "Turn a skill off".

## TDD: failing tests first
- [x] a skill with `enabled: false` is absent from `metadata()` (model surface), the description list, search, and the preload
- [x] `use skill` with a disabled id gives the unknown-id corrective
- [x] a project stub `enabled: false` hides a lower-layer skill of the same name
- [x] `enabled: "yes"` (not a bool) → the skill is off, with one diagnostic
- [x] a missing key → the skill is on
- [x] flipping `enabled` in a watched file reloads, and the board gets a notice with Removed, then New

## Acceptance
- [x] Extras resolved at 23baf04 or later
- [x] Tests written first and seen failing, then passing; full `swift test` green
- [ ] Send the sha to foundationmodelsacpagent-a5 when it is on origin/main