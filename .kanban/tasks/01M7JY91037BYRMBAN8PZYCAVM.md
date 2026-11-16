---
assignees:
- claude-code
position_column: done
position_ordinal: ffb680
title: Keep the old full names of the SkillsTool.make(registry:) factories
---
Commit 660d15f added `marketplaces:` with a default to the two `SkillsTool.make(registry:...)` factories. This changed their full names. FoundationModelsAgents keeps `make(registry:embedder:followReloads:catalogCharacterLimit:visibilityPredicate:sandboxProbe:)` as a function reference (`skillsToolFactory`), thus its build failed (reported by foundationmodelsacpagent-30).

Fix: the overloads with `marketplaces:` have no default for it. The two old overloads come back and send `marketplaces: nil`.

Acceptance: a test takes each old full name as a function reference; `swift test` passes.