---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2xdznpwj7rwnt6ae358rdv6
  text: |-
    Research before the work (files read, and what they hold):

    - `Sources/.../Marketplace/MarketplaceSource.swift` holds `MarketplaceGrants` and the `grants` field, init parameter and decode of `MarketplaceSource`. The decode reads `decodeIfPresent`, thus a `grants:` key in YAML becomes an unknown key after the delete and the decode still gives a source.
    - `Sources/.../Marketplace/MarketplaceLayerProviding.swift` holds `MarketplaceLayer.grants`, `MarketplaceProvenanceIndex.Entry.grants` and `grants(atLayerIndex:)`. After the delete, `Entry` holds the provenance alone and `entry(atLayerIndex:)` still serves `provenance(atLayerIndex:)`.
    - `Sources/.../Registry/SkillsRegistry.swift` holds `LayerPlan.grants(atLayerIndex:)`, `CatalogEntry.grants`, `effectivePolicy(for:)` and `effectivePolicy(id:)`, all under the MARK "Per-marketplace grants". The doc comment of `grants(atLayerIndex:)` sits above `contributingDirectories(for:)`, thus the delete also repairs that doc block.
    - `effectivePolicy(id:)` has one caller: `Sources/.../Resources/RunScript.swift` gate 1. It becomes `context.registry.policy`, which is public.
    - Tests that name a marketplace grant: `MarketplaceGrantsTests.swift` (whole file), `MarketplaceStoreTests.eachLayerCarriesTheGrantsOfItsSource`, three cases of `MarketplaceSourceTests`, one fixture line of `MarketplaceConfigTests`, the `grants:` parameter of `MarketplaceTestSupport.makeMarketplaceLayer`, and one doc comment of `ResourceTestSupport`.
    - `RunScriptTests.swift` names no marketplace grant. Every "grant" there is the `allowed-tools` grant of a skill, which stays. The card's new test for that file is an addition.
    - Documents that name a marketplace grant: `docs/marketplaces.md` (the `grants` row and the "Trust and grants" section), `docs/security.md` (rule 1), `marketplace.md` (the status paragraph, §6.2, §6.6, §10 and §14). `plan.md` names no marketplace grant: each grant there is the `Script(<glob>)` grant of a skill.
  timestamp: 2026-09-19T18:13:46.844337+00:00
- actor: claude-code
  id: 01m2xeeag6h4bpe8ser8vqaxv9
  text: |-
    Implementation landed, with `/tdd`.

    Red first: the four new tests all failed before one line of the sources changed — the config test decoded a source that still carried grants, the shell test gave `[shell execution disabled]` under a permissive host policy, the `run script` test drew the policy corrective, and the docs test found the name in `docs/marketplaces.md` and in `marketplace.md`. Then the sources changed and every one of them passed.

    Two decisions that the card leaves to the work:

    - `effectivePolicy(id:)` goes as well. It stands inside the "Per-marketplace grants" MARK section that the card deletes, and without `CatalogEntry.grants` its body is `return policy`. Its one caller, gate 1 of `RunScript`, now reads `context.registry.policy`, which is public.
    - The shell injection test of a marketplace layer goes to `MarketplaceRegistryTests`, which the card permits ("or the registry render test that exists"). `ShellInjectionTests` tests the pass over a `RenderRequest` and builds no registry, thus a layer test there would duplicate the registry fixture.

    One reading of an acceptance criterion: `Tests/.../MarketplaceDocsTests.swift` holds the string `"MarketplaceGrants"` as the name that the documents must not carry. The card asks for that test by name, thus the criterion "no file under `Sources/` or `Tests/` names `MarketplaceGrants`" reads as the code that uses the type. No file uses the type any more.
  timestamp: 2026-09-19T18:21:46.886387+00:00
- actor: claude-code
  id: 01m2xeeen3j8mjg8sj6hfxfb94
  text: |-
    ### implement — changed
    - evidence: 17 files — 6 under `Sources/`, 8 under `Tests/` (1 deleted: `MarketplaceGrantsTests.swift`), 3 documents. `swift build --build-tests` 0 warnings. `swift test` 742 tests in 57 suites, 0 failures.
    - next: `/review`
  timestamp: 2026-09-19T18:21:51.139108+00:00
- actor: claude-code
  id: 01m2xekkyzr4dvpa8v5ekan9f0
  text: |-
    ### test — green
    - evidence: swift build --build-tests — 0 errors, 0 warnings; swift test — 742 tests in 57 suites passed, 0 failed, 0 skipped
    - no lint or format config file at the project root, so build warnings are the full check for this step
    - one pre-existing conditional test disable is present at Tests/FoundationModelsSkillsTests/SkillWatcherTests.swift (unreadableDirectoryInsideARootIsSkippedAndReadableSiblingsStillReport), gated on the process not running as root; it is not part of the current change set and every other test ran and passed
    - next: send the task to review
  timestamp: 2026-09-19T18:24:40.415078+00:00
- actor: claude-code
  id: 01m2xeyejxk8b5467yvx15bek0
  text: |
    ### review — findings
    - evidence: 1 finding (1 confirmed, 0 refuted) — `Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift:150`
    - scope: `review sha HEAD~1..HEAD` (commit 3377f57)
    - next: delete the explicit initializer that is equal to the compiler-made one, then run the review again.
  timestamp: 2026-09-19T18:30:35.357171+00:00
- actor: wballard
  id: 01m2xezejsp5rkvepa81wtsgj3
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 17 files, 1 deleted
    - test: green — swift test, 742 passed, 0 warnings
    - commit: 3377f57
    - review: findings — Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift:150
  timestamp: 2026-09-19T18:31:08.121771+00:00
- actor: claude-code
  id: 01m2xf58wvtyh0fs7grccay17h
  text: |-
    The review finding is corrected. `MarketplaceProvenanceIndex.Entry` keeps its one `provenance` field, and the compiler now makes the memberwise initializer. The one caller, `SkillsRegistry.LayerPlan.init(marketplaceLayers:localLayers:)`, writes `MarketplaceProvenanceIndex.Entry(provenance:)` as before, because `Entry` is internal and the compiler-made initializer is internal too.

    The rule owns the internal half alone. I read the rule text: a `public init` of a `public struct` is not identical to the compiler-made one, because Swift makes an internal one. I looked at each of the three other initializers of the file, and each one must stay:

    - `MarketplaceProvenance.init(id:url:sha:catalogVersion:)` -- a public initializer of a public struct. A delete would take the initializer off the package surface.
    - `MarketplaceLayer.init(layer:provenance:isWatchable:)` -- the same, and `isWatchable` carries a default value that no compiler-made initializer gives.
    - `MarketplaceProvenanceIndex.init(byLayerIndex:)` -- the stored property is `private`, thus the compiler-made initializer would be private as well, and the `= []` default would go.

    I also checked the open acceptance items of the card against the code, and I marked the ones the work already meets:

    - No file under `Sources/` names a marketplace grant member. Every remaining "grant" word under `Sources/` names the `allowed-tools` `Script(<glob>)` grant of a skill, which stays.
    - `MarketplaceRegistryTests` holds both shell injection cases (permissive policy and disabled policy), and `RunScriptTests.aScriptOfAMarketplaceLayerRunsUnderAPermissiveHostPolicy` holds the script case.
    - `MarketplaceConfigTests.anEntryThatStillCarriesAGrantsKeyLoadsWithTheSameURL` holds the `grants:` decode case.
    - No document names a marketplace grant: `docs/`, `marketplace.md`, `plan.md` and `README.md` keep grant words for the `allowed-tools` grant of a skill alone. `MarketplaceDocsTests.noDocumentNamesTheRemovedGrantsType` guards the four marketplace documents.
    - `swift build --build-tests` gives 0 warnings and `swift test` is green.
  timestamp: 2026-09-19T18:34:18.907217+00:00
- actor: claude-code
  id: 01m2xf5d1t275xn2p489bzcvkx
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift (the explicit initializer of `MarketplaceProvenanceIndex.Entry` is gone). `swift build --build-tests` 0 errors, 0 warnings. `swift test` 742 tests in 57 suites, 0 failures. Card items: 1 review finding checked, 5 acceptance items checked, 5 test items checked.
    - next: `/review`
  timestamp: 2026-09-19T18:34:23.162298+00:00
- actor: claude-code
  id: 01m2xfavk98fh477tqq88ew851
  text: |-
    ### test — green
    - evidence: `swift package clean && swift build --build-tests` → 0 warnings, build complete. `swift test` → 742 tests in 57 suites, all pass, 0 fails, 0 skips.
    - next: send task to review.
  timestamp: 2026-09-19T18:37:21.897995+00:00
- actor: claude-code
  id: 01m2xfega7nysz3zsndvrp9wjq
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (efc9b01) — 0 findings, 0 confirmed, 0 refuted, 7 attempted. Every prior finding is checked.
    - next: none. The task moved to done.
  timestamp: 2026-09-19T18:39:21.415710+00:00
- actor: wballard
  id: 01m2xffg4nz0jgwj2epq8h7et8
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 file, 1 of 1 findings checked
    - test: green — swift test, 742 passed, 0 warnings
    - commit: efc9b01
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-19T18:39:54.005831+00:00
position_column: done
position_ordinal: f980
title: 'Remove the marketplace grant concept: one host policy for every layer'
---
## What

The user removed the marketplace grant concept on 2026-09-19. A marketplace layer is an untrusted layer like `user` and `project`. The host `RenderPolicy` and the `allowed-tools` grant of a skill are the only gates. A marketplace does not get its own permission switches.

Remove `MarketplaceGrants` and every use of it from this package. Do this before the marketplace code moves to Extras, so the code that moves is smaller.

1. `Sources/FoundationModelsSkills/Marketplace/MarketplaceSource.swift`: delete `MarketplaceGrants`. Delete the `grants` field, the `grants:` init parameter, and the `grants` decode of `MarketplaceSource`. A `marketplaces.yaml` entry with a `grants:` key still decodes; the key is ignored.
2. `Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift`: delete `grants` from `MarketplaceLayer` and from `MarketplaceProvenanceIndex.Entry`, and delete `grants(atLayerIndex:)`.
3. `Sources/FoundationModelsSkills/Marketplace/MarketplaceStore.swift`: stop passing grants into the layers.
4. `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`: delete `grants` from `CatalogEntry` and its init, delete `grants(atLayerIndex:)` on the plan, and delete `effectivePolicy(for:)`. Every gate reads the registry `policy` directly. Delete the "Per-marketplace grants" MARK section.
5. `Sources/FoundationModelsSkills/Marketplace/MarketplaceCache.swift`: correct the comment that names the `shellInjection` and `scripts` grants. A marketplace skill can run a script or a shell command under the host policy.
6. Tests: delete `Tests/FoundationModelsSkillsTests/MarketplaceGrantsTests.swift`. Remove the grant fixtures and the grant cases from `MarketplaceTestSupport.swift`, `ResourceTestSupport.swift`, `MarketplaceStoreTests.swift`, `MarketplaceConfigTests.swift`, `MarketplaceSourceTests.swift`, and `RunScriptTests.swift`.
7. Documents: remove the `grants` row and the "Trust and grants" section from `docs/marketplaces.md`; state instead that a marketplace layer renders untrusted and runs under the host policy. Remove the grant rows from `marketplace.md` §6.6, the `grants` field from §6.2, and the grant statements in the status paragraph and in §10 and §14. Remove the grant statements from `docs/security.md` and `plan.md` where they name a marketplace grant (the `allowed-tools` grant of a skill stays).

The render pass named `ShellInjection` and the test file `ShellInjectionTests.swift` keep their names. They are the shell injection feature, not a grant.

## Acceptance Criteria

- [x] No file under `Sources/` or `Tests/` names `MarketplaceGrants` or `grants.shellInjection`, and no file under `Sources/` names a `grants` member on a marketplace type.
- [x] A skill from a marketplace layer renders and runs under the same `RenderPolicy` as a skill from a `user` layer: shell injection and `run script` are on when the policy has them on, and off when it has them off.
- [x] A `marketplaces.yaml` entry that still has a `grants:` key loads with no error.
- [x] No document under `docs/`, and neither `marketplace.md` nor `plan.md`, names a marketplace grant.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/RunScriptTests.swift`: a script from a marketplace layer runs when the host policy permits scripts and the skill has the `allowed-tools` grant.
- [x] `Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift` (or the registry render test that exists): a marketplace skill with a shell injection renders the shell output when the host policy permits the shell, and the literal when the policy disables it.
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceConfigTests.swift`: a YAML entry with `grants:` decodes to a source with the same `url`.
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceDocsTests.swift`: no document names `MarketplaceGrants`.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#marketplace #skills

## Review Findings (2026-09-19 13:25)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 15 file(s) reviewed, 15 not reviewed.

> 12 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 12 file(s)

> 3 file(s) not reviewed — no validator matched:
> - `docs/marketplaces.md` — no validator matches this file
> - `docs/security.md` — no validator matches this file
> - `marketplace.md` — no validator matches this file

> ⚠️ tool rule 'code-hygiene/disallowed-constructs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> disallowed-constructs-swift found no file at Tests/FoundationModelsSkillsTests/MarketplaceGrantsTests.swift, so its constructs are unread

> ⚠️ tool rule 'code-hygiene/function-length-swift' declined an item — it judged the rest of the code, and this it could not judge:
> function-length-swift found no file at Tests/FoundationModelsSkillsTests/MarketplaceGrantsTests.swift, so its bodies are unread

> ⚠️ tool rule 'code-hygiene/idioms-swift' declined an item — it judged the rest of the code, and this it could not judge:
> idioms-swift found no file at Tests/FoundationModelsSkillsTests/MarketplaceGrantsTests.swift, so its declarations are unread

> ⚠️ tool rule 'code-hygiene/magic-numbers-swift' declined an item — it judged the rest of the code, and this it could not judge:
> magic-numbers-swift found no file at Tests/FoundationModelsSkillsTests/MarketplaceGrantsTests.swift, so its literals are unread

> ⚠️ tool rule 'code-hygiene/missing-docs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> missing-docs-swift found no file at Tests/FoundationModelsSkillsTests/MarketplaceGrantsTests.swift, so its declarations are unread

- [x] `Sources/FoundationModelsSkills/Marketplace/MarketplaceLayerProviding.swift:150` `code-hygiene/idioms-swift` — UseSynthesizedInitializer: remove this explicit initializer, which is identical to the compiler-synthesized initializer.
