---
position_column: doing
position_ordinal: '80'
title: Resource ops must honor the surface visibility predicate (CLI = user)
---
## What
Variance from §7.2 ("The CLI respects the same visibility rules as the user surface — it is a user, not a model"): `ResourceIDLookup.resolve` hardcodes `$0.isModelVisible` (`Resources/ResourceSupport.swift:44, 62`), used by all three resource ops (`ListResource.swift:101`, `ReadResource.swift:130`, `RunScript.swift:140`). On the CLI's user-surface context (`CLI/SkillsCLI.swift:43-51`) this INVERTS visibility: `resource list --id lint` (model-only) succeeds while `--id deploy` (user command) is refused — the exact inversion the skill-op tests forbid.

Note the plan tension: §7.3 says the resource ops "see only the model-visible catalog", §7.2 says the CLI is a user surface. Resolve it the same way the skill ops do — visibility comes from `context.visibilityPredicate`, so the model surface stays model-visible and the CLI surface is user-visible. Record the resolution in a doc comment on `ResourceIDLookup` (and note it for the M7 README).

Also close the coverage hole: no CLI test touches any resource op (`SkillsCLITests.swift` covers only skill list/search/use), and no round-trip parity test exists for them.

## Acceptance Criteria
- [ ] Via the model-surface context: `lint` resources reachable, `deploy` refused with the current-id corrective
- [ ] Via the CLI/user-surface context: `deploy` resources reachable, `lint` refused
- [ ] CLI round-trip payload parity proven for `resource list`, `resource read`, `script run` spellings

## Tests
- [ ] Extend `Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift` — surface matrix over the two contexts
- [ ] Extend `SkillsCLITests.swift` — resource-op invocations + round-trip parity
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.