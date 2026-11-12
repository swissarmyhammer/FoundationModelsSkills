---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'SK-9: per-run template context for call(id:) and the skills tool'
---
## What
Request from FoundationModelsACPAgent (^vshf002) and FoundationModelsAgents (^93vqt8j). Each agent run renders its skills with the template values of its own tools (`tools.<group>.enabled`). All runs share one `SkillsRegistry` and one `SkillsCatalogTool`.

- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: add `withTemplateContext(_:) -> SkillsRegistry`, a view that shares the catalog, the reload coordinator and `onReload`, and renders with the given values in place of the registry values (pass 3, partials too). Add `templateContext: [String: TemplateValue]? = nil` to `call(id:arguments:)`. `nil` keeps the registry values.
- `Sources/FoundationModelsSkills/Operations/SkillsCatalogTool.swift`: add `withTemplateContext(_:) throws -> SkillsCatalogTool`. It shares the search agent (index, embedder), the reload follow and the notice board, and changes only the values of each render.
- `Sources/FoundationModelsSkills/Operations/SkillsToolContext.swift`: an internal copy with another registry.

## Acceptance Criteria
- [ ] `call(id:templateContext:)` renders each branch of `{% if tools.shell.enabled %}` from the given values.
- [ ] `call(id:)` with `templateContext: nil` keeps the registry values.
- [ ] `use skill` through `SkillsCatalogTool.withTemplateContext(_:)` renders with the given values, and the shared tool keeps the registry values.

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/PerRunTemplateContextTests.swift`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd`. #step1