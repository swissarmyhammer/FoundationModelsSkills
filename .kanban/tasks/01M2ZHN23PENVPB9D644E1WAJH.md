---
assignees:
- claude-code
depends_on:
- 01M2XD7YJF87V9PF0EPSG5CF2N
position_column: todo
position_ordinal: 9b80
title: Delete the Marketplace exception of the frontmatter-split guard
---
## What

`NoFrontmatterSplitTests` (`Tests/FoundationModelsSkillsTests/NoFrontmatterSplitTests.swift`) holds this package to the boundary rule: no file of `Sources/` splits a document itself, because `FrontmatterDocumentStack` of `FoundationModelsExtras` gives the split.

The guard has one exception today. `Marketplace/CatalogResolver.rootSkillName()` reads the root `SKILL.md` of a marketplace repository through a `CatalogFileSource`. That source can be a git tree (`GitTreeFileSource`), thus it is no dotfolder stack and the document stack cannot serve it. The case keeps one call of `FrontmatterDocument.split`, and the test filters the `Marketplace/` folder out of the walk.

Card ^sg5cf2n gives the marketplace to Extras and deletes that folder. After it lands, the exception has nothing to protect.

## Acceptance Criteria

- [ ] `NoFrontmatterSplitTests` walks every file of `Sources/`, with no folder filtered out.
- [ ] `marketplacePath` and the prose about it are gone from the suite.
- [ ] No file of `Sources/FoundationModelsSkills/` names `FrontmatterDocument.split`.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

#loading-boundary #skills