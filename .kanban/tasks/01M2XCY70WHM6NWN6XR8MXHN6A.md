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
position_column: doing
position_ordinal: '80'
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

- [ ] No file under `Sources/` or `Tests/` names `MarketplaceGrants` or `grants.shellInjection`, and no file under `Sources/` names a `grants` member on a marketplace type.
- [ ] A skill from a marketplace layer renders and runs under the same `RenderPolicy` as a skill from a `user` layer: shell injection and `run script` are on when the policy has them on, and off when it has them off.
- [ ] A `marketplaces.yaml` entry that still has a `grants:` key loads with no error.
- [ ] No document under `docs/`, and neither `marketplace.md` nor `plan.md`, names a marketplace grant.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/RunScriptTests.swift`: a script from a marketplace layer runs when the host policy permits scripts and the skill has the `allowed-tools` grant.
- [ ] `Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift` (or the registry render test that exists): a marketplace skill with a shell injection renders the shell output when the host policy permits the shell, and the literal when the policy disables it.
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceConfigTests.swift`: a YAML entry with `grants:` decodes to a source with the same `url`.
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceDocsTests.swift`: no document names `MarketplaceGrants`.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#marketplace #skills