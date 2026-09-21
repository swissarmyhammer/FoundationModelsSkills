---
comments:
- actor: claude-code
  id: 01m32820pajqpf30rxsmjt026a
  text: |-
    Research, before the code.

    **The guard suites that exist now.** Each one gives `SwiftSourceScan` a test of a line, and that reader walks the Swift files of a directory.

    | suite | what it forbids | where |
    |---|---|---|
    | `NoFrontmatterSplitTests` | `FrontmatterDocument.split`, and `String(contentsOf` in `Registry/` | `Sources/` |
    | `NoResourceFileReadTests` | `FileManager`, `FileHandle`, `resourceValues` | `Sources/.../Resources` |
    | `NoFileSystemWatchTests` | `DispatchSource`, `O_EVTONLY`, `SkillWatcher` | `Sources/` |
    | `StencilLivesInExtrasTests` | `TemplateEngine`, `TemplateContext`, `TemplateValue`, `WellKnownValues`, and `FileManager` in `Render/` | `Sources/` |
    | `NoDotfolderStackExtensionTests` | a line that opens `extension DotfolderStack` | `Sources/` |
    | `NoGitProcessTests` | a line that starts a process and names `git` | `Sources/` |
    | `NoStandardOutWriteTests` | a call of `print`, `debugPrint`, `dump`, `_printChanges` | `Sources/`, `Examples/skills-demo` |

    **The decision.** The first four suites all ask one question: does a line name a forbidden text? Thus they join into one suite, `LoadingBoundaryTests`, with one table. Each row of the table holds the name, the reason, and the files that may hold it. The four files go away. The last three stay: each one reads a shape rather than a name (a process line that also names `git`, a call with a word boundary, an extension head with the character after it), thus a name table cannot hold them.

    The new table holds each name of the four suites, so the fold loses no cover. It adds `Data(contentsOf`, `contentsOfDirectory`, `resolvingSymlinksInPath`, `import Stencil` and `import libgit2`.

    **What names a forbidden text now.** Two lines only: `CLI/MarketplaceCLIContext.swift` names `FileManager` (item 1 of the card removes it), and `CLI/StandardStream.swift` names `FileHandle` (an exemption of the card).

    **`SeamReexports.swift`.** The card exempts it for `TemplateEngine`, and states the reason: its comment tells a host what the re-export of Extras gives. The file does not name `TemplateEngine` yet; the comment lists `FrontmatterValue`, `QuarantinedText` and `SlashCommand`. An exemption that exempts nothing is dead, thus the comment takes `TemplateEngine` as well, which is true: `@_exported import FoundationModelsExtras` gives a host that type. A second test holds each exemption to a real line, so no dead row can stand in the table.

    **`Examples/skills-demo`.** The `--marketplace` mode builds its context with `MarketplaceCLIContext(stack: FixtureStack.make())`, thus it already takes its folders from its caller and needs no change when the default of `workingDirectory` goes away. `SkillsCLI.runMarketplace`, `MarketplaceCLI.run` and `MarketplaceCLISession.active` are the three callers that need `URL.currentDirectory()`.
  timestamp: 2026-09-21T15:06:24.330841+00:00
- actor: claude-code
  id: 01m328jy5bh99b4y61wyd36t9r
  text: |-
    The work landed. What each part does:

    **The guard.** `Tests/FoundationModelsSkillsTests/LoadingBoundaryTests.swift` is the one guard of the whole boundary. It holds a table of 17 rules; each row carries the forbidden name, the reason, and the files that may hold it. One parameterized test walks `Sources/FoundationModelsSkills/` for each rule over the shared `SwiftSourceScan`, and a second one holds each exemption to a real line, so no dead row can stand in the table. Five line tests read the two helpers of a rule.

    **The fold.** `NoFrontmatterSplitTests`, `NoResourceFileReadTests`, `NoFileSystemWatchTests` and `StencilLivesInExtrasTests` are gone; the table holds each of their names and adds `Data(contentsOf`, `contentsOfDirectory`, `resolvingSymlinksInPath`, `import Stencil` and `import libgit2`. `NoGitProcessTests`, `NoStandardOutWriteTests` and `NoDotfolderStackExtensionTests` stay: each one reads a shape, not a name.

    **The last call.** `MarketplaceCLIContext.init(workingDirectory:environment:)` has no default now. `MarketplaceCLIContext.currentProcess` gives the context over `URL.currentDirectory()`, and the three command entry points take it: `MarketplaceCLI.run`, `SkillsCLI.runMarketplace` and `MarketplaceCLISession.active`. One place of the package reads where the process stands, and a test never reaches it.

    **The documents.** plan.md §3 carries the table under the heading "The loading boundary (the user, 2026-09-20)", and the layer diagram no longer says that Layer 3 holds the file watcher: `DotfolderWatcher` stands in the Extras box. `docs/development.md` states the same table and names the two exemptions.

    **`ScriptGate`.** Its doc comment says that it opens no file and that the table names it in no rule.

    **The proof of the guard.** One temporary line in `FoundationModelsSkills.swift` naming `FrontmatterDocument.split` and `FileManager` made two rules fail, each with the path and the line number. The line is reverted.
  timestamp: 2026-09-21T15:15:38.795168+00:00
- actor: claude-code
  id: 01m328k3f82p0dafs5q2fdcefd
  text: |-
    ### implement — changed
    - evidence: 12 files. New: Tests/FoundationModelsSkillsTests/LoadingBoundaryTests.swift. Deleted: NoFrontmatterSplitTests.swift, NoResourceFileReadTests.swift, NoFileSystemWatchTests.swift, StencilLivesInExtrasTests.swift. Changed: Sources/FoundationModelsSkills/CLI/MarketplaceCLIContext.swift, CLI/MarketplaceCLI.swift, CLI/MarketplaceCLISession.swift, CLI/SkillsCLI.swift, Resources/ScriptGate.swift, SeamReexports.swift, Tests/.../MarketplaceCLITests.swift, Tests/.../SwiftSourceScan.swift, plan.md, docs/development.md. `swift build --build-tests`: 0 errors, 0 warnings. `swift test`: 567 tests in 53 suites, 0 failures. The guard proof: one temporary line naming `FrontmatterDocument.split` and `FileManager` failed 2 rules, then reverted.
    - next: /review
  timestamp: 2026-09-21T15:15:44.232288+00:00
- actor: claude-code
  id: 01m328xfq6w50qj5mv12eykmh6
  text: |
    ### test — green
    - evidence: `swift build --build-tests` (clean build, `swift package clean` first) — 0 warnings. `swift test` — Test run with 567 tests in 53 suites passed. 0 failures. 0 skipped tests.
    - Pinned suites checked in the output and green: `Loading boundary`, `Marketplace CLI`, `UseSkillPlainTextTests`, `HotReloadTests`, `SkillsRegistryTests`, `SkillValidatorTests`, `DiagnosticsRenderingTests`, `SearchListPlainTextTests`, `SkillsDemoTests`.
    - Rule check on the join into `LoadingBoundaryTests.swift`: I read the full old text of the four deleted suites (`NoFileSystemWatchTests`, `NoFrontmatterSplitTests`, `NoResourceFileReadTests`, `StencilLivesInExtrasTests`) from git history and matched each forbidden name to a row in the new `rules` table. Each old name is a row now: `FileManager`, `FileHandle` (with the same one exemption, `CLI/StandardStream.swift`), `resourceValues`, `DispatchSource`, `O_EVTONLY`, `SkillWatcher`, `FrontmatterDocument.split`, `String(contentsOf`, and the Stencil names `TemplateEngine` (with the same one exemption, `SeamReexports.swift`), `TemplateContext`, `TemplateValue`, `WellKnownValues`, `import Stencil`. The new scan directory (`Sources/FoundationModelsSkills`) is the same directory tree the old suites scanned (`Sources/` holds only that one target), so no rule lost scope. Two old suites scanned a narrower path than the whole tree (`Resources/` only, `Registry/` only); the new table scans the whole tree for those same names, which is a superset check, so a break in the old narrow path still fails the new test.
    - Live proof that a rule failure still fails the suite: I added a temporary comment line `// TEMP-PROBE: FileManager` to `Sources/FoundationModelsSkills/SeamReexports.swift`, ran `swift test --filter 'FoundationModelsSkillsTests.LoadingBoundaryTests'`, and saw it fail (1 issue, exit non-zero). I then reverted the line and reran the full suite — green again, 567 tests passed.
    - `MarketplaceCLIContext.currentProcess` reads `URL.currentDirectory()`, not `FileManager`. `SkillsCLI.run` and `MarketplaceCLI.run` default to `.currentProcess`; `Examples/skills-demo` uses that default.
  timestamp: 2026-09-21T15:21:24.454831+00:00
- actor: claude-code
  id: 01m3293tjb7t3kfvk4bs2m6zhk
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 5cf4fe2). Counts: 0 findings, 0 confirmed, 0 refuted; 7 validators attempted, 0 failed. 13 files reviewed. 6 files not reviewed: 4 `.kanban/` files (ignore rule) and `docs/development.md`, `plan.md` (no validator matches). The code-hygiene tool rules declined 4 files that this commit deleted (`NoFileSystemWatchTests.swift`, `NoFrontmatterSplitTests.swift`, `NoResourceFileReadTests.swift`, `StencilLivesInExtrasTests.swift`). The task has no earlier review findings.
    - next: The task moved to done.
  timestamp: 2026-09-21T15:24:52.171123+00:00
- actor: wballard
  id: 01m3294cq23xtbnvxjxp2m99h3
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 17 files; one LoadingBoundaryTests suite with 17 rules replaces four guard suites
    - test: green — swift test, 567 passed, 0 warnings
    - commit: 5cf4fe2
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-21T15:25:10.754618+00:00
depends_on:
- 01M2ZDRMVEV4ZYV446AWJJ4PFD
- 01M2ZEDYF3RJEA214WNYRAQ5XE
- 01M2ZEDY8TKCMFQJA8RWHTH0PD
- 01M2ZDRN2FAQT69FPBRAYGAQ3P
- 01M2ZDRN9J0YB9V5B1W46MJF9K
- 01M2XD7YJF87V9PF0EPSG5CF2N
- 01M2ZHN23PENVPB9D644E1WAJH
position_column: done
position_ordinal: ff8f80
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

The cards before this one do the moves: ^sg5cf2n (the marketplace), ^g9jt4sq, the execute bit card and the confinement card (the file reads of the operations), the shim card, the `SKILL.md` read card, the render card, the watcher card. This card closes what is left and puts a guard on the rule, so it cannot come back.

1. **The last call.** `CLI/MarketplaceCLIContext.swift` reads `FileManager.default.currentDirectoryPath` for the default of its working directory. Replace it: the context takes `workingDirectory: URL` from its caller; `SkillsCLI` and `Examples/skills-demo` pass `URL.currentDirectory()`; the tests pass their temporary directory. The `marketplaces.yaml` write of the `add` and `remove` commands already goes through `MarketplaceConfig.save(to:)` of Extras.
2. **The guard test.** This package already has guard suites of this kind, on the shared walker `Tests/FoundationModelsSkillsTests/SwiftSourceScan.swift`: `NoFrontmatterSplitTests`, `NoGitProcessTests`, `NoStandardOutWriteTests` and `SwiftSourceScanTests`. Build the new suite on that walker, and fold `NoFrontmatterSplitTests` into it (the card ^4e1wajh removes its `Marketplace/` exception first), so one table holds each forbidden name of the loading boundary. One test walks `Sources/FoundationModelsSkills/` and fails when a file names one of: `FileManager`, `FileHandle`, `String(contentsOf`, `Data(contentsOf`, `resourceValues`, `contentsOfDirectory`, `DispatchSource`, `O_EVTONLY`, `resolvingSymlinksInPath`, `FrontmatterDocument.split`, `TemplateEngine`, `TemplateContext`, `import Stencil`, `import libgit2`. The walk reads the full text of each file, comments included, so a stale doc comment fails it; the cards before this one rewrite their comments. Two exemptions, by file name: `CLI/StandardStream.swift` may name `FileHandle`, because it writes the console and loads nothing; `SeamReexports.swift` may name `TemplateEngine`, because its comment tells a host what the re-export of Extras gives, and that stays true. Put the list and the exemptions in one table in the test, with the reason of each.
3. **The documents.** `plan.md` §3 (the layer architecture) and `docs/development.md` state the table above and the rule, with the date. `ARCHITECTURE.md` does not exist; do not make one.
4. Check `ScriptGate` (`Resources/ScriptGate.swift`): its `fnmatch` call matches a path pattern of `allowed-tools`, and opens no file. It stays. State that in one line of its doc comment, because the guard test does not name it.

## Acceptance Criteria

- [x] The guard test passes, and it fails when any forbidden name is put back in any file under `Sources/FoundationModelsSkills/` (prove it one time with a temporary edit, then revert).
- [x] `MarketplaceCLIContext` takes its working directory from its caller.
- [x] `plan.md` and `docs/development.md` state the boundary rule and the table.
- [x] These suites pin the outputs of this group, and each one passes with no change of an expected value in this card: `UseSkillPlainTextTests` and `HotReloadTests` (the rendered text), `SkillsRegistryTests` and `SkillValidatorTests` (the catalog), `DiagnosticsRenderingTests` (each diagnostic), `SearchListPlainTextTests`, `MarketplaceCLITests` and `SkillsDemoTests` (the command output).
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/LoadingBoundaryTests.swift` (new): the walk of `Sources/` with the table of forbidden names and the one exemption.
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceCLITests.swift`: the `add` command writes into the working directory that the test gives to the context.
- [x] `Tests/FoundationModelsSkillsTests/SkillsDemoTests.swift`: `skills-demo --marketplace list` gives the same output as before.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #dotfolder-overlay #skills
