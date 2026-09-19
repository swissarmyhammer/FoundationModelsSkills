---
depends_on:
- 01M2X2J679TGA1ENB64G9JT4SQ
- 01M2X2JAVD898YDFT802HMMNGA
position_column: todo
position_ordinal: '8580'
title: Correct every document that states the full-replacement rule
---
## What

The documents state the wrong rule, and they give a reason for it that came from a `DotfolderStack` that could not give a combined view. Correct them.

1. `docs/plan.md`: decision #29 says that the roots are the interface and that `DotfolderStack` is one convenience only. Record that this was a mistake, and that the stack gives the combined view. Decision #3 says that a later root fully replaces an earlier root for the same id. Replace it: the unit of override is the file.
2. `docs/operations.md`: `list resource`, `read resource` and `run script` see the combined view of the skill. Give the layer example of the card ^cw1z0q7.
3. `docs/marketplaces.md`: the grants of `run script` come from the layer that gives the script.
4. `README.md`: correct each statement that says that a higher layer replaces a full skill.
5. `CHANGELOG.md`: one entry that records the change of behavior and the change of the public API (`DiscoveredSkill.contributingDirectories`).

## Acceptance Criteria

- [ ] No document says that a higher layer replaces a full skill directory.
- [ ] `docs/plan.md` records the correction of decision #3 and decision #29, with the reason.
- [ ] `docs/operations.md` holds the layer example.
- [ ] `CHANGELOG.md` records the change of behavior and the change of the API.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/DocumentationTests.swift` (or the test file that checks the documents now): a test that fails when a document holds the words of the full-replacement rule.
- [ ] `Tests/FoundationModelsSkillsTests/ReadmeExampleTests.swift`: the example of the README still agrees with the code.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#dotfolder-overlay #skills