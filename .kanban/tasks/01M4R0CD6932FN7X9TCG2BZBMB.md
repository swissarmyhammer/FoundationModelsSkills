---
assignees:
- claude-code
depends_on:
- 01M4R0NQVS6M1G3SBMXHH71NX8
- 01M4R0BGFCECWZYT3BWRFXG8ZA
position_column: todo
position_ordinal: '8480'
title: 'Stencil: let {% include %} put a file of the skill into the body'
---
## What
An author can write `{% include "references/house-style.md" %}` in `SKILL.md`. The render puts the winning copy of that file of the skill into the body. The `_partials/` search of now does not change. The Extras include-resolver hook comes from the dependency task. This task does only the work in FoundationModelsSkills.

Rules:
- The order of the search: (1) a file of the skill, with the include name as a path relative to the skill; (2) the `_partials/` search of now.
- Step 1 applies only when the include name:
  - passes `ResourcePathRules.isWellFormedRelativePath(_:)` (not absolute, no `..`);
  - has a minimum of one `/`, so a bare partial name such as `"header"` never matches a file of the skill;
  - is not `SKILL.md` and has no hidden path component (a component that starts with `.`).
- Trust and scope: step 1 searches only the contributing directories whose layer is in the partial scope of the winning layer. That is the same scope as `partialsStack(for:)` of Extras: the winning marketplace layer plus the local layers, or the local layers only. Thus a trusted `.defaults` skill never includes a file that only a marketplace layer gives.
- The included file renders the same as a partial now: the same variables, trust, limits and include-depth limit. An author who wants the text with no template change uses `{% raw %}` in the file.
- An include of a file that is in no step gives the render failure of now.
- `RenderRequest` carries the contributing directories (with their layers) of the skill, so that `StencilPass` can make the resolver. Look at `SkillsRegistry.call(id:arguments:)` and each other `RenderRequest` call site in `SkillsRegistry`. Decide if the metadata render gets the directories too, and write the decision in the doc comment.
- `StencilPass` gives the resolver to the Extras hook. Do not open a file and do not resolve a symlink in this package (`LoadingBoundaryTests`).
- Docs: `README.md` (the three-pass pipeline text), `docs/marketplaces.md` ("Partial scope"), and `docs/security.md`. Say that an include can name a file of the skill, the name rules, and the scope rule.

## Acceptance Criteria
- [ ] A body with `{% include "references/changelog.md" %}` renders with the content of that file.
- [ ] When a higher layer and a lower layer both hold the file, the include gives the higher-layer copy. A file that only a lower layer holds is found.
- [ ] `MarketplacePartialScopeTests` and `RenderPipelineNoRescanTests` pass with no change.
- [ ] A file of the skill at `partials/header.md` does not change `{% include "header" %}`, which still gives the `_partials/` copy.
- [ ] `{% include "SKILL.md" %}`, `{% include "../other-skill/SKILL.md" %}`, an absolute name and a hidden path do not read a file of the skill.
- [ ] A `.defaults` skill cannot include a file that only a marketplace layer gives.
- [ ] A marketplace (untrusted) skill can include its own file, with the untrusted limits.
- [ ] `LoadingBoundaryTests` passes.

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/StencilPassTests.swift`: tests for each criterion above, over temp layer directories.
- [ ] `Tests/FoundationModelsSkillsTests/MarketplacePartialScopeTests.swift`: add the `.defaults`-cannot-include-marketplace-file test.
- [ ] `Tests/FoundationModelsSkillsTests/RenderPipelineTests.swift`: one end-to-end render of a temp skill that includes its own reference.
- [ ] `swift test` passes with no failure.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.