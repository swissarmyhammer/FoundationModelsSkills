---
depends_on:
- 01M2ZDRMMGTDZCMB4ZS15QQK20
- 01M2ZDRMVEV4ZYV446AWJJ4PFD
- 01M2ZDRN2FAQT69FPBRAYGAQ3P
- 01M2ZDRN9J0YB9V5B1W46MJF9K
- 01M2XD7YJF87V9PF0EPSG5CF2N
position_column: todo
position_ordinal: '8680'
title: 'Guard the loading boundary: no file access, no Stencil and no frontmatter split in this package'
---
## What

This is the last card of the loading boundary. The rule (the user, 2026-09-20): the raw work of loading lives in `FoundationModelsExtras` — the sources and the marketplace fetch, the file system, the layers, the file watcher, Stencil, and the split of the markdown frontmatter. This package keeps only the work of the skill schema: the decode of the frontmatter into `SkillFrontmatter`, the validation rules, the catalog, the two grammar passes of the skill format (arguments and shell injection), `allowed-tools` and the script gate, the resource operations as contracts (the paging, the caps, the kinds, the correctives), the search, the operations, and the CLI.

```
1  Extras  Marketplace            fetch, cache, materialize a layer root
2  Extras  DotfolderStack         find a file in the combined view; say which layer gave it; confine the path
3  Extras  DotfolderWatcher       say that a layer root changed
4  Extras  FrontmatterDocumentStack   split the frontmatter from the body
5  Extras  StenciledDotfolderStack    Stencil, with the trust and the partial scope of the layer
6  here    the skill schema       everything above
```

The cards before this one do the moves: ^sg5cf2n (the marketplace), ^g9jt4sq and the resources card (the file reads of the operations), the `SKILL.md` read card, the render card, the watcher card. This card closes what is left and puts a guard on the rule, so it cannot come back.

1. **The last call.** `CLI/MarketplaceCLIContext.swift` reads `FileManager.default.currentDirectoryPath` for the default of its working directory. Replace it: the context takes `workingDirectory: URL` from its caller; `SkillsCLI` and `Examples/skills-demo` pass `URL.currentDirectory()`; the tests pass their temporary directory. The `marketplaces.yaml` write of the `add` and `remove` commands already goes through `MarketplaceConfig.save(to:)` of Extras.
2. **The guard test.** One test walks `Sources/FoundationModelsSkills/` and fails when a file names one of: `FileManager`, `FileHandle`, `String(contentsOf`, `Data(contentsOf`, `resourceValues`, `contentsOfDirectory`, `DispatchSource`, `O_EVTONLY`, `resolvingSymlinksInPath`, `FrontmatterDocument.split`, `TemplateEngine`, `TemplateContext`, `import Stencil`, `import libgit2`. The list has one entry that is permitted, by file name: `CLI/StandardStream.swift` may name `FileHandle`, because it writes the console and loads nothing. Put the list and the exemption in one table in the test, with the reason of each.
3. **The documents.** `plan.md` §3 (the layer architecture) and `docs/development.md` state the table above and the rule, with the date. `ARCHITECTURE.md` does not exist; do not make one.
4. Check `ScriptGate` (`Resources/ScriptGate.swift`): its `fnmatch` call matches a path pattern of `allowed-tools`, and opens no file. It stays. State that in one line of its doc comment, because the guard test does not name it.

## Acceptance Criteria

- [ ] The guard test passes, and it fails when any forbidden name is put back in any file under `Sources/FoundationModelsSkills/` (prove it one time with a temporary edit, then revert).
- [ ] `MarketplaceCLIContext` takes its working directory from its caller.
- [ ] `plan.md` and `docs/development.md` state the boundary rule and the table.
- [ ] The rendered text of each skill, the catalog, each diagnostic, and the output of each `skills` command are the same as before this group of cards.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/LoadingBoundaryTests.swift` (new): the walk of `Sources/` with the table of forbidden names and the one exemption.
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceCLITests.swift`: the `add` command writes into the working directory that the test gives to the context.
- [ ] `Tests/FoundationModelsSkillsTests/SkillsDemoTests.swift`: `skills-demo --marketplace list` gives the same output as before.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #dotfolder-overlay #skills
