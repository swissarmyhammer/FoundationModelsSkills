---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2xcgw5s8g4rac3dfdc4q399
  text: |-
    Research, before the code.

    - `swift package update` gives `FoundationModelsExtras` at 2123cdf, the commit the card names. The new API is there: `DotfolderStack.childDirectories(of:) -> [String: [Layer]]` (child directory name to the layers that hold it, lowest first), `layerDirectories(_:) -> [Layer]`, `tree(_:)`, `locate(_:) -> [URL]` (each layer that holds a path, lowest first), `items(in:named:)`.
    - `items(in:named:)` reads the text of the winning file and drops a file that is not UTF-8. Discovery must not use it: a `SKILL.md` that cannot be decoded must stay discovered, because `SkillsRegistry` raises the unreadable-file diagnostic for it (`SkillsRegistryTests`). `locate(_:)` gives the URLs only, thus discovery reads no file.
    - `DotfolderStack` states no initializer that takes its layers. `StencilPass.partialsStack(for:)` already built a throwaway stack and replaced `layers`. That block is now one internal `DotfolderStack.init(layers:)` (`Sources/FoundationModelsSkills/Discovery/DotfolderStack+Layers.swift`), and both call sites use it.
    - The winning layer of a `SKILL.md` comes from a path match: the highest contributing directory whose `<dir>/SKILL.md` is one of the URLs `locate` gave. No layer walk of this package.
    - `SkillValidator` held the shadow rule over `shadowedCandidates`. It now reads the contributing directories below the winning `SKILL.md`. The marketplace sentences of marketplace.md §9.1 do not change.

    Still open for the document card ^e71pp5x: the root `marketplace.md` (line 234) names `DiscoveredSkill.shadowedCandidates` and states the full-replace rule. The card lists `docs/marketplaces.md`; add the root `marketplace.md` to it.
  timestamp: 2026-09-19T17:48:13.369318+00:00
- actor: claude-code
  id: 01m2xchtvn1wpt9y5yvqmqwwfa
  text: |-
    ### implement — changed
    - evidence: `swift package update` keeps FoundationModelsExtras at 2123cdf. 9 files: Sources/FoundationModelsSkills/Discovery/SkillDiscovery.swift, Sources/FoundationModelsSkills/Discovery/DiscoveredSkill.swift, Sources/FoundationModelsSkills/Discovery/DotfolderStack+Layers.swift (new), Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Sources/FoundationModelsSkills/Render/StencilPass.swift, Sources/FoundationModelsSkills/Validation/SkillValidator.swift, Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift, Tests/FoundationModelsSkillsTests/SkillDiscoveryTests.swift, Tests/FoundationModelsSkillsTests/SkillValidatorTests.swift. `swift build --build-tests` gives 0 errors and 0 warnings; `swift test` gives 746 tests in 58 suites, 0 failures. TDD: the new discovery tests were red (no member `contributingDirectories`) before the code, green after.
    - next: /review. The card stays in `doing`, and nothing is committed.
  timestamp: 2026-09-19T17:48:44.789843+00:00
- actor: claude-code
  id: 01m2xcvb9cr8rw74q02a4gtetc
  text: |-
    ### test — green
    - command: swift build --build-tests (full clean rebuild after `swift package clean`) — 0 errors, 0 warnings
    - command: swift test — 747 tests in 58 suites passed, 0 failed, 0 skipped/disabled
    - next: ready for review
  timestamp: 2026-09-19T17:53:56.524012+00:00
- actor: claude-code
  id: 01m2xd2fzd5ytgqedxxsbw1z0g
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (933ce71) — 0 findings, 0 confirmed, 0 refuted; 7 validators ran, 0 failed; 9 files reviewed, 20 files excluded by the `.reviewignore` rule for `.kanban/`
    - next: no open findings, and each prior item is checked. The card moves to done.
  timestamp: 2026-09-19T17:57:50.701577+00:00
- actor: wballard
  id: 01m2xd3d93hvjrrbedsvwfx58t
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 9 files, 1 new
    - test: green — swift test, 747 passed, 0 warnings
    - commit: 933ce71
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-19T17:58:20.707831+00:00
position_column: done
position_ordinal: f880
title: Give SkillDiscovery a combined view over the layer directories
---
## What

`SkillDiscovery.discover()` (`Sources/FoundationModelsSkills/Discovery/SkillDiscovery.swift:74`) replaces a full skill directory when a higher layer holds the same id. This is wrong. The unit of override is the file. A higher layer overrides only the files that it holds, and each other file of the lower layers stays visible.

Example, with `defaults < user < project`:

```
defaults/review/SKILL.md             user/review/SKILL.md          project/review/references/house-style.md
defaults/review/references/rules.md  user/review/scripts/lint.sh
defaults/review/scripts/lint.sh
defaults/review/scripts/report.sh
```

The skill `review` must give: `SKILL.md` from user, `scripts/lint.sh` from user, `scripts/report.sh` from defaults, `references/rules.md` from defaults, `references/house-style.md` from project. Today the user copy of `SKILL.md` hides `report.sh`, `rules.md` and `style.md`.

The comment at `SkillDiscovery.swift:10-14` says that the roots are the interface and that `DotfolderStack` is only a convenience. That text, and `plan.md` decision #29, are a rationalization of a `DotfolderStack` that could not do this. Delete that reason; do not keep it.

**Dependency across repositories.** The combined view comes from the new `DotfolderStack` API in `FoundationModelsExtras` (`tree(_:)`, `childDirectories(of:)`, `layerDirectories(_:)`, card ^40n54dh on that board). Do not write a copy of the walk in this package. If the API is not in the branch of Extras yet, stop and report this task as stuck.

## The work

1. Bump `FoundationModelsExtras` with `swift package update`.
2. `SkillDiscovery` takes the layers (`[DotfolderStack.Layer]`, lowest precedence first), not bare roots. Keep `init(stack:)`. `init(roots:)` stays for a host that gives bare roots; it wraps each root as it does now.
3. `discover()` uses `childDirectories(of: nil)` to find each id of the union. An id counts when a minimum of one of its layer directories holds `SKILL.md`. Skip the names `.git` and `node_modules`.
4. `DiscoveredSkill` (`Sources/FoundationModelsSkills/Discovery/DiscoveredSkill.swift`): replace `shadowedCandidates` with `contributingDirectories: [ContributingDirectory]`, lowest precedence first. Each item holds `rootIndex`, `root` and `skillDirectory`. `skillDirectory`, `root` and `rootIndex` stay, and they name the layer of the winning `SKILL.md`.

## Acceptance Criteria

- [x] `contributingDirectories` gives each layer directory of an id, lowest first, also a layer that holds no `SKILL.md`.
- [x] `skillDirectory` names the layer of the highest `SKILL.md`.
- [x] No type in this package walks the layers itself; the walk comes from `DotfolderStack`.
- [x] The rationalization text at `SkillDiscovery.swift:10-14` is gone.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/SkillDiscoveryTests.swift`: the fixture of the example above gives one skill `review` with three contributing directories, lowest first.
- [x] Same file: a layer that holds `<id>/` but no `SKILL.md` is a contributing directory.
- [x] Same file: an id that no layer gives a `SKILL.md` for is not discovered.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#dotfolder-overlay #skills #cross-repo