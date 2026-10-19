---
assignees:
- claude-code
depends_on:
- 01M5A7ZGHC7Y1KY81E8C5KPNWV
- 01M5A84CYKC62A5H2MMWFHKW3J
position_column: todo
position_ordinal: '8480'
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

## TDD: failing tests first
- [ ] a skill with `enabled: false` is absent from `metadata()` (model surface), the description list, search, and the preload
- [ ] `use skill` with a disabled id gives the unknown-id corrective
- [ ] a project stub `enabled: false` hides a lower-layer skill of the same name
- [ ] `enabled: "yes"` (not a bool) → the skill is off, with one diagnostic
- [ ] a missing key → the skill is on
- [ ] flipping `enabled` in a watched file reloads, and the board gets a notice with Removed, then New

## Acceptance
- [ ] Extras resolved at 23baf04 or later
- [ ] Tests written first and seen failing, then passing; full `swift test` green
- [ ] Send the sha to foundationmodelsacpagent-a5 when it is on origin/main