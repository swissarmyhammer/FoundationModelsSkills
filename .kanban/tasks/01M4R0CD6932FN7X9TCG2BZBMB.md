---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4r7c3ve9g4b4hw9yy980ges
  text: |-
    Research:
    - Extras 6ac66c1 gives `StenciledDotfolderStack.IncludeResolver = @Sendable (String) -> String?` and the `includeResolver:` init parameter. The resolver must give the TEXT. Thus the resolver reads the file through a `DotfolderStack` over the skill directories in scope (`content(_:)`), which applies the Extras text check and the symlink confinement. This package opens no file.
    - `StencilPass.StackFactory` takes `(DotfolderStack, [String: String])`. It must also take the resolver, so the test seam `pinnedPass` in StencilPassTests forwards it.
    - `RenderRequest` has one call site in the registry: `SkillsRegistry.renderRequest(text:entry:arguments:argumentNames:)`, shared by `call` and the metadata render. Plan: the metadata render gets the directories too (one scope rule for each templated text).
    - `SkillsRegistry.ContributingDirectory` (directory + layer) is internal. Plan: make it public, and add `contributingDirectories` to `RenderRequest` (default empty).
    - `DotfolderStack.Layer` is not Equatable. The scope rule compares `source` and `root`, the same values the registry puts on the catalog entry.
  timestamp: 2026-10-12T14:13:25.998544+00:00
- actor: claude-code
  id: 01m4rawg67b0ftvsqkg22gq4yd
  text: |-
    Implementation landed (TDD; work resumed after an API usage limit stopped the first session).
    - New `Sources/FoundationModelsSkills/Render/SkillFileInclude.swift`: it gives the resolver to the Extras `includeResolver` hook. The name rules are in `isSkillFileName(_:)`: `ResourcePathRules.isWellFormedRelativePath`, a minimum of one `/`, the components are not `["SKILL.md"]` (so `SKILL.md/` is also refused), and no component starts with `.`. The scope rule: a marketplace directory is in scope only when the winning layer is that same marketplace (source and standardized root). The resolver reads through `DotfolderStack.content(_:)` over the skill directories in scope. Thus there is no file access and no symlink resolution in this package.
    - `SkillsRegistry.ContributingDirectory` is now public, with a public init, because the public `RenderRequest.contributingDirectories` (default `[]`) carries it.
    - Decision: `SkillsRegistry.renderRequest(...)` gives the directories to the body render AND to the metadata render (written in its doc comment). A description can include a file of the skill. The metadata render runs no shell.
    - `StencilPass.StackFactory` now takes the resolver as a third argument. The test seam `pinnedPass` forwards it.
    - RED evidence: (1) compile failure for the missing API; (2) after the naive resolver, 8 issues: the bare `header` name, `SKILL.md`, `SKILL.md/`, `./SKILL.md`, `.hidden/...`, `references/.secret.md`, defaults-vs-marketplace, other marketplace; (3) with the registry wiring taken out, the body and description end-to-end tests failed. `../other-skill/SKILL.md` and the absolute name are already refused by the Extras stack text check. Those tests are guards.
    - Docs: README (a paragraph after the override text), docs/marketplaces.md "Partial scope", docs/security.md (a new bullet).
  timestamp: 2026-10-12T15:14:48.647765+00:00
- actor: claude-code
  id: 01m4rawkfh6ky9rd7fef841e8j
  text: |-
    ### implement — changed
    - evidence: `swift test`: 616 tests in 56 suites passed, 0 failures (LoadingBoundaryTests, MarketplacePartialScopeTests, RenderPipelineNoRescanTests included). No compiler warning. One SwiftPM build-graph warning ("missing creator for mutated node" for the mlx-swift_Cmlx bundle) comes from a dependency, not from this change. 10 files: Sources/FoundationModelsSkills/Render/SkillFileInclude.swift (new), Render/StencilPass.swift, Render/RenderPipeline.swift, Registry/SkillsRegistry.swift, Tests/FoundationModelsSkillsTests/StencilPassTests.swift (+16 cases), RenderPipelineTests.swift (+2), MarketplacePartialScopeTests.swift (+1), README.md, docs/marketplaces.md, docs/security.md. Not committed.
    - next: /review
  timestamp: 2026-10-12T15:14:52.017899+00:00
- actor: claude-code
  id: 01m4rb1d628wfbntcprwh48pj7
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (4b6c676); 1 finding (1 confirmed, 0 refuted) — Sources/FoundationModelsSkills/Render/SkillFileInclude.swift:77
    - next: Use one shared hidden-path-component check for `ListResource.isHidden(_:)` and `SkillFileInclude.isSkillFileName(_:)`. Remove the local `hiddenComponentPrefix` constant. Then review again.
  timestamp: 2026-10-12T15:17:29.410233+00:00
- actor: claude-code
  id: 01m4rb1q8wrxm87wx81spsjm3b
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 10 files (resumed once after an API usage limit)
    - test: green — swift test, 616 passed in 56 suites
    - commit: 4b6c676
    - review: findings — Sources/FoundationModelsSkills/Render/SkillFileInclude.swift:77
  timestamp: 2026-10-12T15:17:39.740801+00:00
- actor: claude-code
  id: 01m4rb6d4k34h7zf0bhkqwb40n
  text: |-
    Review finding fixed (reuse/reuse at SkillFileInclude.swift:77).
    - New shared rule `ResourcePathRules.hasHiddenComponent(_:)` in Sources/FoundationModelsSkills/Resources/ResourceSupport.swift, next to `isWellFormedRelativePath(_:)`. It owns the `pathSeparator` and `hiddenComponentPrefix` constants.
    - `ListResource.isListed(_:)` calls the shared rule. The private `ListResource.isHidden(_:)` is deleted.
    - `SkillFileInclude.isSkillFileName(_:)` calls the shared rule. The local `hiddenComponentPrefix` constant is deleted.
    - A search of all `.swift` files finds no other copy of the rule (`hasPrefix(".")`, `isHidden(`, `hiddenComponentPrefix`).
    - TDD: two table tests in ResourcePathRulesTests (4 hidden paths, 4 paths that are not hidden, one with a full stop inside a name). RED was a compile failure: "type 'ResourcePathRules' has no member 'hasHiddenComponent'". GREEN after the function was added.
  timestamp: 2026-10-12T15:20:13.203254+00:00
- actor: claude-code
  id: 01m4rb6frqwv6q11z9geyxwq8a
  text: |-
    ### implement — changed
    - evidence: `swift test`: 618 tests in 56 suites passed, 0 failures (was 616; +2 parameterized tests). No compiler warning. The one SwiftPM warning ("missing creator for mutated node" for the mlx-swift_Cmlx bundle) comes from a dependency. 4 files: Sources/FoundationModelsSkills/Resources/ResourceSupport.swift, Sources/FoundationModelsSkills/Resources/ListResource.swift, Sources/FoundationModelsSkills/Render/SkillFileInclude.swift, Tests/FoundationModelsSkillsTests/ResourcePathRulesTests.swift. Not committed. The finding is `- [x]`.
    - next: /review
  timestamp: 2026-10-12T15:20:15.895003+00:00
depends_on:
- 01M4R0NQVS6M1G3SBMXHH71NX8
- 01M4R0BGFCECWZYT3BWRFXG8ZA
position_column: doing
position_ordinal: '80'
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

## Review Findings (2026-10-12 10:15)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 7 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 3 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file
> - `docs/marketplaces.md` — no validator matches this file
> - `docs/security.md` — no validator matches this file

- [x] `Sources/FoundationModelsSkills/Render/SkillFileInclude.swift:77` `reuse/reuse` — The hidden-path-component test is written again here. `ListResource.isHidden(_:)` already does the same check: it splits on `/` and tests whether any component starts with `.`. Two copies of the rule can diverge, so a later change to the hidden-file rule could be made in one place and missed in the other. Make `ListResource.isHidden(_:)` internal, or move it to `ResourcePathRules` next to `isWellFormedRelativePath(_:)`, and call it from `SkillFileInclude.isSkillFileName(_:)`. Remove the local `hiddenComponentPrefix` constant.
