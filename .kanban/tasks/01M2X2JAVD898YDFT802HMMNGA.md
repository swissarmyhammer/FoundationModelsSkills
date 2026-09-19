---
depends_on:
- 01M2X2HX820957M3JE41JKNJ0E
- 01M2X2J1KXF8CGFNFY9XHB2S4D
position_column: todo
position_ordinal: '8480'
title: run script over the combined view
---
## What

`run script` must find a script in the combined view.

There is no marketplace grant. The user removed that concept on 2026-09-19. A script from a marketplace layer runs under the same rules as a script from a `user` or `project` layer: the host `RenderPolicy` and the `allowed-tools` grant of the skill.

1. `RunScript` (`Sources/FoundationModelsSkills/Resources/RunScript.swift`) resolves the path through the overlay, thus a script that only a lower layer holds can run, and a higher copy of the same path wins.
2. `ScriptGate` (`Sources/FoundationModelsSkills/Resources/ScriptGate.swift`) applies the host policy and the `allowed-tools` grant of the winning `SKILL.md`. It does not read the layer of the script for a permission. If `ScriptGate` still holds a marketplace grant input after the grant removal card, remove it here.
3. The `scripts/` rule, the confinement rule and the correctives do not change.

## Acceptance Criteria

- [ ] A script that only a lower layer holds runs.
- [ ] A script that two layers hold runs the copy of the higher layer.
- [ ] A script that a marketplace layer gives runs under the same host policy as a local script.
- [ ] `ScriptGate` has no marketplace grant input.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/RunScriptTests.swift`: a script that only the defaults layer holds runs and gives its output.
- [ ] Same file: the same script path in two layers runs the higher copy.
- [ ] `Tests/FoundationModelsSkillsTests/ScriptGateTests.swift`: a script from a marketplace layer is permitted or denied by the same host policy and `allowed-tools` rule as a local script.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#dotfolder-overlay #skills