---
depends_on:
- 01KYNCSXAEKDVR36H387H5TYXR
- 01KYND89QDD8BYQWGGPJ8Z4J2M
position_column: todo
position_ordinal: '8980'
title: SlashCommandProviding conformance for the user surface
---
## What
Harness delivery channel (plan §6, decision #29): conform `SkillsRegistry` to Extras' `SlashCommandProviding`.

- `Sources/FoundationModelsSkills/Registry/SkillsRegistry+SlashCommands.swift`:
  - `commands(workingDirectory:)` derives `SlashCommand` values from `commandListing()` — name = id, description, `argumentHint` assembled from the §6.1 parsed parameters (placeholders in order, variadic tail rendered as `...`).
  - `commandUpdates` ticks on every registry reload (bridge `onReload`).
  - Read Extras' `SlashCommandProviding`/`SlashCommand`/`Invocation` declarations first and match their exact shapes — including the body kind. Where a `.prompt(template:)` body kind exists, document plainly (doc comment) that the harness engine runs none of §5 passes 1–2 and a full-fidelity host calls `registry.call(id:arguments:)` (§7.1 caveat).

## Acceptance Criteria
- [ ] `commands(workingDirectory:)` over the fixture stack lists exactly the user-invocable skills with correct hints
- [ ] A reload (temp-dir edit) produces a `commandUpdates` tick and a changed command set
- [ ] The §7.1 caveat is documented on the conformance

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SlashCommandProvidingTests.swift` — command snapshot; hint assembly cases; reload-tick case
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.