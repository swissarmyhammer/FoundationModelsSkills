---
comments:
- actor: claude-code
  id: 01m2xst3vmh2s5qdg0da2mj8tk
  text: |
    One more document line for this card, found while card ^2hmmnga ran.

    plan.md §7.3 (the `run script` row) and the M6 line of the milestones both state "cwd = the skill directory". One skill now has more than one layer directory. `RunScript` runs the winning copy of the script with the layer directory that gave that copy as the working directory. The words of plan.md need that correction.
  timestamp: 2026-09-19T21:40:27.636986+00:00
- actor: claude-code
  id: 01m2zk9f8sytd9fyhp7bcfcetk
  text: |
    Research done.

    What the code does now, read from the source:

    - `DiscoveredSkill` (Sources/FoundationModelsSkills/Discovery/DiscoveredSkill.swift) carries `contributingDirectories: [ContributingDirectory]`, lowest precedence first. `shadowedCandidates` is gone.
    - `SkillOverlay` (Sources/FoundationModelsSkills/Resources/SkillOverlay.swift) gives the combined view. Its own comment says: "The unit of override is the file: for a path of the skill, the copy in the highest layer directory that holds it wins, and a file that only a lower directory holds stays visible."
    - `RunScript.execute` runs the winning copy with `overlay.directories[winning.directoryIndex]` as the working directory. The comment says "The working directory of the run is the layer directory that gave the winning copy". Thus plan.md "cwd = the skill directory" is not exact.
    - `SkillsRegistry` reads each `SKILL.md` through the Extras `FrontmatterDocumentStack` (commit 895c901). The package opens no file for a skill.
    - The shadow diagnostic stays. `SkillValidator.shadowedMarketplaceSentences` names the layer of the winning `SKILL.md`, thus the word "shadows" is still correct for one file, and wrong for a whole directory.

    Documents that state the rule that shipped before:
    - plan.md lines 69, 93-94, 128, 145, 525-526, 652, 692, 811-812, 856; §7.3 and the M6 line say "cwd = the skill directory".
    - marketplace.md §4.1 ("Full replace. The winner replaces the full skill folder. There is no merge.") and line 234 names `DiscoveredSkill.shadowedCandidates`.
    - docs/marketplaces.md "The winner replaces the full skill folder. There is no merge."
    - docs/security.md item 8.
    - README.md "where the near layer wins".
    - Examples/skill-library/defaults/base-style/SKILL.md and .../user/base-style/SKILL.md bodies and descriptions.

    Guards to respect while editing:
    - `DependencyGraphTests.readmeUsageBlockMatchesItsCompiledCopy` holds the README Swift fence equal to the copy in ReadmeExampleTests. Do not edit that fence.
    - `MarketplaceDocsTests` holds the four marketplace documents to naming each environment variable, each subcommand and no `MarketplaceGrants`.
    - `FixtureLibraryTests.userBaseStyleFullyReplacesTheDefaultsCopy` states the rule in its own name.
  timestamp: 2026-09-20T14:24:59.673001+00:00
- actor: claude-code
  id: 01m2zkwf1eyfft3c8a5dswtxtv
  text: |
    Implementation landed, with `/tdd`.

    RED first. `Tests/FoundationModelsSkillsTests/DocumentationTests.swift` failed with 33 issues before any document changed: 11 rows of the rule that shipped before, 20 claims that no document made, 1 removed field name in marketplace.md, and 1 working-directory claim in plan.md. Each failure named the document and the wording.

    The suite reads ten documents: plan.md, marketplace.md, README.md, CHANGELOG.md, the four files of docs/, and the two `base-style` fixture files. It holds them to:
    - no wording of the rule that shipped before, over every document;
    - no `shadowedCandidates`, over every document but CHANGELOG.md, which records the removal;
    - no `cwd = the skill directory` in plan.md;
    - the sentence `The unit of override is the file` in each document that describes the stack;
    - the layer example, the combined view and the new working directory in docs/operations.md;
    - decision #32, the new working directory and `contributingDirectories` in plan.md;
    - `DiscoveredSkill`, `ContributingDirectory`, `contributingDirectories` and `shadowedCandidates` in CHANGELOG.md.

    The field name is not a copy of the spelling: a `Mirror` over a sample `DiscoveredSkill` finds the field whose value is `[DiscoveredSkill.ContributingDirectory]` and reads its label. Thus a rename makes the suite fail until each document names the new field. One case guards that read, thus an absent field cannot make the document cases prove nothing.

    `DocumentClaim` is reused from MarketplaceDocsTests. Its doc comment now says that a suite decides what a row means: a claim the document must make, or a wording the document must not hold.

    Findings on the way:
    - The forbidden wordings cannot stand in the CHANGELOG either, thus the entry states the behavior that shipped before in other words. No exception rule was needed.
    - A required sentence must stand on ONE line. docs/security.md and the user fixture wrapped it, and both failed until the line was rewrapped. Worth knowing for a later document case.
    - `docs/security.md` now states the other half of the rule as its own item 9: a file that only a marketplace holds stays visible in a local skill. That is a real security consequence of the file-level rule, and no document stated it.
    - `FixtureLibraryTests.userBaseStyleFullyReplacesTheDefaultsCopy` stated the rule in its own name. It is now `userBaseStyleOverridesTheDefaultsCopyOfTheSkillFile`.
    - The README Swift fence was not touched, thus `DependencyGraphTests.readmeUsageBlockMatchesItsCompiledCopy` stays green.

    ### implement — changed
    - evidence: 15 files — Tests/FoundationModelsSkillsTests/DocumentationTests.swift (new), Tests/FoundationModelsSkillsTests/MarketplaceDocsTests.swift, Tests/FoundationModelsSkillsTests/FixtureLibraryTests.swift, plan.md, marketplace.md, README.md, CHANGELOG.md, docs/operations.md, docs/marketplaces.md, docs/security.md, Examples/skill-library/defaults/base-style/SKILL.md, Examples/skill-library/user/base-style/SKILL.md, and the two kanban records. `swift build --build-tests` gives 0 warnings. `swift test` gives 808 tests in 66 suites, 0 failures.
    - next: `/review`
  timestamp: 2026-09-20T14:35:22.030914+00:00
- actor: claude-code
  id: 01m2zkzwqk2f0nrcfwmdvj4sg9
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` — 0 warnings, 0 errors; `swift test` — 808 tests, 66 suites, all pass, 0 fail, 0 skip
    - next: none
  timestamp: 2026-09-20T14:37:14.355122+00:00
depends_on:
- 01M2X2J679TGA1ENB64G9JT4SQ
- 01M2X2JAVD898YDFT802HMMNGA
position_column: doing
position_ordinal: '80'
title: Correct every document that states the full-replacement rule
---
## What

The documents state the wrong rule, and they give a reason for it that came from a `DotfolderStack` that could not give a combined view. Correct them.

1. `plan.md`: decision #29 says that the roots are the interface and that `DotfolderStack` is one convenience only. Record that this was a mistake, and that the stack gives the combined view. Decision #3 says that a later root fully replaces an earlier root for the same id. Replace it: the unit of override is the file.
2. `docs/operations.md`: `list resource`, `read resource` and `run script` see the combined view of the skill. Give the layer example of the card ^cw1z0q7.
3. `docs/marketplaces.md`: state where the `run script` grant comes from. The marketplace grant concept is gone (commit 3377f57), thus the grant comes from the winning `SKILL.md`, and never from the layer that gives the script.
4. `README.md`: correct each statement that says that a higher layer replaces a full skill.
5. `CHANGELOG.md`: one entry that records the change of behavior and the change of the public API (`DiscoveredSkill.contributingDirectories`).

## Acceptance Criteria

- [x] No document says that a higher layer replaces a full skill directory.
- [x] `plan.md` records the correction of decision #3 and decision #29, with the reason.
- [x] `docs/operations.md` holds the layer example.
- [x] `CHANGELOG.md` records the change of behavior and the change of the API.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/DocumentationTests.swift`: a test that fails when a document holds the words of the full-replacement rule.
- [x] `Tests/FoundationModelsSkillsTests/ReadmeExampleTests.swift`: the example of the README still agrees with the code.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#dotfolder-overlay #skills