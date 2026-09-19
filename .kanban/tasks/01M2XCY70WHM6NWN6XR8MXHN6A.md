---
assignees:
- claude-code
position_column: todo
position_ordinal: '8880'
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

## Acceptance Criteria

- [ ] No file under `Sources/` or `Tests/` names `MarketplaceGrants`, `shellInjection`, or a `grants` field of a marketplace.
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
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace #skills