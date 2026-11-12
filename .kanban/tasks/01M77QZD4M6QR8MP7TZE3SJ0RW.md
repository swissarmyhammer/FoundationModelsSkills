---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m77ra9xcbrryd8tqt6rrprnn
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — SkillsRegistry.swift, SkillsCatalogTool.swift, SkillsToolContext.swift, SkillsTool.swift, LoadingBoundaryTests.swift, PerRunTemplateContextTests.swift
    - test: green — swift test, 830 passed
    - commit: 950647c
    - review: findings — SkillsCatalogTool.swift:155 (duplication of the assembly of SkillsTool.make), SkillsRegistry.swift:1444 (cast with no else branch), PerRunTemplateContextTests.swift:36 (fixture helper repeats TemplateContextRenderTests.registry)
    - note: the names are `with(templateContext:)`, because `withTemplateContext` and `withTemplateValues` break the LoadingBoundaryTests rules on TemplateContext and TemplateValue.
  timestamp: 2026-11-12T11:29:32.588455+00:00
- actor: claude-code
  id: 01m77rfr8gvxssw7d26zr960zz
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — SkillsCatalogTool.init builds the OperationTool (one assembly); the cast logs an error and fails an assertion; TemplateContextTestSupport.registry is the shared fixture
    - test: green — swift test, 830 passed
    - commit: 734d502
    - review: findings — TemplateContextTestSupport.swift:34 (var accumulator)

    ### finish iteration 3 — clean
    - implement: changed — TemplateContextTestSupport.swift builds the files with let
    - test: green — swift test, 830 passed
    - commit: d8310b9
    - review: clean — review sha HEAD~1..HEAD, 0 findings
  timestamp: 2026-11-12T11:32:31.120021+00:00
position_column: done
position_ordinal: ffb280
title: 'SK-9: per-run template context for call(id:) and the skills tool'
---
## What
Request from FoundationModelsACPAgent (^vshf002) and FoundationModelsAgents (^93vqt8j). Each agent run renders its skills with the template values of its own tools (`tools.<group>.enabled`). All runs share one `SkillsRegistry` and one `SkillsCatalogTool`.

- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: add `with(templateContext:) -> SkillsRegistry`, a view that shares the catalog, the reload coordinator and `onReload`, and renders with the given values in place of the registry values (pass 3, partials too). Add `templateContext: [String: TemplateValue]? = nil` to `call(id:arguments:)`. `nil` keeps the registry values.
- `Sources/FoundationModelsSkills/Operations/SkillsCatalogTool.swift`: add `with(templateContext:) throws -> SkillsCatalogTool`. It shares the search agent (index, embedder), the reload follow and the notice board, and changes only the values of each render.
- `Sources/FoundationModelsSkills/Operations/SkillsToolContext.swift`: an internal copy with another registry.

## Acceptance Criteria
- [x] `call(id:templateContext:)` renders each branch of `{% if tools.shell.enabled %}` from the given values.
- [x] `call(id:)` with `templateContext: nil` keeps the registry values.
- [x] `use skill` through `SkillsCatalogTool.with(templateContext:)` renders with the given values, and the shared tool keeps the registry values.

## Tests
- [x] `Tests/FoundationModelsSkillsTests/PerRunTemplateContextTests.swift`.
- [x] `swift test` passes.

## Workflow
- Use `/tdd`. #step1