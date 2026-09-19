---
depends_on:
- 01M2X2HX820957M3JE41JKNJ0E
- 01M2X2J1KXF8CGFNFY9XHB2S4D
position_column: todo
position_ordinal: '8380'
title: list resource and read resource over the combined view
---
## What

`list resource` and `read resource` see one directory only. They must see the combined view of the skill.

1. `ListResource` (`Sources/FoundationModelsSkills/Resources/ListResource.swift`) gives the union of the paths of the contributing directories. One row for each path, with the winning copy. A path that two layers hold gives one row, not two. The order, the caps and the visibility rule do not change.
2. `ReadResource` (`Sources/FoundationModelsSkills/Resources/ReadResource.swift`) reads the winning copy through the overlay of the card ^xhb2s4d. The paging, the caps and the correctives do not change.
3. `ResourceSupport` (`Sources/FoundationModelsSkills/Resources/ResourceSupport.swift`) takes the contributing directories, not one directory.

## Acceptance Criteria

- [ ] `list resource` shows a file that only a lower layer holds.
- [ ] `list resource` shows one row for a path that two layers hold, and the row names the higher copy.
- [ ] `read resource` gives the text of the higher copy for a path that two layers hold.
- [ ] `read resource` gives the text of the lower copy for a path that only the lower layer holds.
- [ ] A skill with one layer directory behaves exactly as before.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/ResourceOperationsTests.swift`: the fixture of the example (`defaults` holds `scripts/report.sh` and `references/rules.md`; `user` holds `scripts/lint.sh`; `project` holds `references/house-style.md`) gives all four paths in `list resource`, each one time.
- [ ] Same file: `read resource` of `scripts/lint.sh` gives the text of the user layer.
- [ ] Same file: `read resource` of `scripts/report.sh` gives the text of the defaults layer.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#dotfolder-overlay #skills