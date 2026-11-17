---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7ms425vfqk8fj0fgtvxajaq
  text: |-
    Work done.
    - Package.resolved: FoundationModelsExtras is at 09d38f97527c7f218531e12ab64ed0a420cb7d11. Package.resolved is in .gitignore, thus git shows no diff for it.
    - Removed `isInferable = true` from UseSkill, SearchSkill, ListSkill, ReadResource, ListResource. `PlainTextMarker.isInferable` stays `Target.isInferable`. Its doc comment now states the opt-out rule.
    - The first full `swift test` after the update gave 2 failures in MarketplaceOperationsTests: `aURLWithNoOpAddsNoMarketplace` and `anIDAndALayerWithNoOpRemoveNoSkill`. They failed only because `add marketplace` and `remove skill` are now inferable. Changed them to `aURLWithNoOpAddsTheMarketplace` (ids are acme and tools) and `anIDAndALayerWithNoOpRemoveTheSkill` (the SKILL.md file is gone).
    - TDD note: the new behavior comes from the dependency, not from code in this package. Thus the changed assertions passed on their first run. The old assertions were the RED evidence.
    - InferredOpPlainTextTests had no test that expects a refusal. All its tests pass. Only its type doc comment changed: `{"id"}` also fits `remove skill`.
    - docs/operations.md section "A payload with no `op`" now states the opt-out rule. `{"id"}` also fits `show`, `edit` and `remove marketplace` when the host gives a marketplace list. README has no text about this rule.
    - The build warning "missing creator for mutated node" for the mlx-swift_Cmlx bundle is from the build system, and it was there before this change.
  timestamp: 2026-11-17T12:53:44.251063+00:00
- actor: claude-code
  id: 01m7ms44qf5v5dyyx33ad1kewt
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` complete; `swift test` 905 tests in 74 suites passed, 0 issues. Files: Sources/FoundationModelsSkills/Operations/{UseSkill,SearchSkill,ListSkill,SkillsTool,PlainTextOperations}.swift, Sources/FoundationModelsSkills/Resources/{ReadResource,ListResource}.swift, Tests/FoundationModelsSkillsTests/{MarketplaceOperationsTests,InferredOpPlainTextTests}.swift, docs/operations.md, Package.resolved (gitignored).
    - next: /review
  timestamp: 2026-11-17T12:53:46.863544+00:00
- actor: claude-code
  id: 01m7ms68j1rn13dzkx0fbjv3z8
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (1ca2fe6): 0 findings, 0 confirmed, 0 refuted; 7 validator runs attempted, 0 failed. 9 files reviewed. No validator matched docs/operations.md. The .kanban files are ignored by .reviewignore.
    - next: none. The task is in done.
  timestamp: 2026-11-17T12:54:56.321706+00:00
position_column: done
position_ordinal: ffbb80
title: Adopt default-inferable operations from FoundationModelsExtras 09d38f9
---
FoundationModelsExtras main 09d38f9 sets the default of `OperationDefinition.isInferable` to `true`. `isInferable: false` is now an opt-out. An op-less guess can now run an operation with side effects. Adopt this rule in Skills.

- [x] Update the FoundationModelsExtras dependency to 09d38f9. Make sure that Package.resolved shows 09d38f9.
- [x] Remove the redundant `static let isInferable = true` declarations in UseSkill, SearchSkill, ListSkill, ReadResource and ListResource.
- [x] Make sure that `PlainTextMarker` passes the flag of its target.
- [x] Change the tests that expect an op-less call to be refused only because the operation was not inferable. Make them assert that the inferred operation runs.
- [x] Update docs/operations.md, README and the doc comments in SkillsTool.swift and PlainTextOperations.swift: every operation is inferable unless it opts out; `defaultOp` settles a tie.
- [x] `swift build --build-tests` and one full `swift test` pass with zero failures and no new warnings.