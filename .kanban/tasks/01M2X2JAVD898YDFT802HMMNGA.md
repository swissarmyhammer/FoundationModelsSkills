---
comments:
- actor: claude-code
  id: 01m2xssj90480yg18ep3ssvpy4
  text: |
    Research, before the code.

    - `ScriptGate` already holds no marketplace input. Commit 3377f57 removed the grant concept, thus item 2 of the card asked for a removal that was done. `evaluateHostPolicy(isScriptExecutionDisabled:)` and `evaluateGrant(path:allowedTools:)` are the whole type, and neither reads a layer. The card text that asks for "the grants of the layer that gives the script" no longer applies, and nothing was removed here.
    - `SkillOverlay` and the list form of `PathConfinement` are there since commit e8b6c29, and no operation used them yet. `SkillsRegistry.contributingDirectories(id:)` gives the layer directories of a catalog entry, lowest precedence first.
    - Every catalog entry holds a minimum of one contributing directory. `SkillDiscovery` takes the winner from that list, thus the list can never be empty for an id that resolved. The new code needs no empty-list branch.
    - `RunScriptTests` held the one marketplace test of `run script`. The card asks for a `ScriptGateTests.swift`, thus that test moved there instead of a second copy.
  timestamp: 2026-09-19T21:40:09.632805+00:00
- actor: claude-code
  id: 01m2xsszevahrb5p82tmcpfqzb
  text: |
    The work, in the TDD order.

    RED: two new tests in `RunScriptTests`. `aScriptThatOnlyALowerLayerHoldsRuns` drew "The script `scripts/report.sh` must have the executable bit set ... and start with a shebang line", because the run looked in the directory of the winning `SKILL.md` only. `aScriptThatTwoLayersHoldRunsTheCopyOfTheHigherLayer` ran the lower copy.

    GREEN:
    - `ResourceIDLookup.withResolvedOverlay(id:context:whenGranted:)` resolves the id through the call that is there, and gives a `SkillOverlay` over `registry.contributingDirectories(id:)`.
    - `RunScript.execute(in:)` takes the winning copy from that overlay, and it runs that copy with the layer directory that gave it as the working directory. The `scripts/` guard, the grant gate, the direct-exec checks and each corrective text stand as they were.

    The tests of `ScriptGateTests.swift` were green at once, because commit 3377f57 already made a marketplace layer untrusted like a local layer. They lock that rule: one skill, one script, two layer kinds, and the same outcome for a grant, for a host policy that stops scripts, and for a skill with no grant.

    `swift build --build-tests`: 0 warnings. `swift test`: 787 tests in 64 suites, 0 failures.
  timestamp: 2026-09-19T21:40:23.131277+00:00
- actor: claude-code
  id: 01m2xst8nf3q2tts0qd3gajn3g
  text: |
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsSkills/Resources/RunScript.swift, Sources/FoundationModelsSkills/Resources/ResourceSupport.swift, Tests/FoundationModelsSkillsTests/RunScriptTests.swift, Tests/FoundationModelsSkillsTests/ResourceTestSupport.swift, Tests/FoundationModelsSkillsTests/ScriptGateTests.swift (new). `swift build --build-tests`: 0 warnings. `swift test`: 787 tests, 64 suites, 0 failures.
    - next: /review. The card stays in `doing`.
  timestamp: 2026-09-19T21:40:32.559025+00:00
- actor: claude-code
  id: 01m2xt03xznxw4rs64qvjx2mq5
  text: |-
    ### test — green
    - command: swift package clean && swift build --build-tests — build complete, 0 warnings
    - command: swift test — 787 tests, 64 suites, 787 passed, 0 failed, 0 skipped
    - command: diagnostics check working — 0 errors, 0 warnings
    - next: ready for review
  timestamp: 2026-09-19T21:43:44.319039+00:00
- actor: claude-code
  id: 01m2xt7v0zh99qpw5pt7cmmfw1
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 8075b80) — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. 5 files reviewed; 6 `.kanban/` files not reviewed, because a `.reviewignore` rule holds them out.
    - next: the card moves to `done`. No open finding stays.
  timestamp: 2026-09-19T21:47:57.343874+00:00
- actor: wballard
  id: 01m2xt8hq1558vv8rq433hjyj2
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files, 1 new
    - test: green — swift test, 787 passed, 0 warnings
    - commit: 8075b80
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-19T21:48:20.577173+00:00
depends_on:
- 01M2X2HX820957M3JE41JKNJ0E
- 01M2X2J1KXF8CGFNFY9XHB2S4D
position_column: done
position_ordinal: ff80
title: run script over the combined view
---
## What

`run script` must find a script in the combined view.

There is no marketplace grant. The user removed that concept on 2026-09-19. A script from a marketplace layer runs under the same rules as a script from a `user` or `project` layer: the host `RenderPolicy` and the `allowed-tools` grant of the skill.

1. `RunScript` (`Sources/FoundationModelsSkills/Resources/RunScript.swift`) resolves the path through the overlay, thus a script that only a lower layer holds can run, and a higher copy of the same path wins.
2. `ScriptGate` (`Sources/FoundationModelsSkills/Resources/ScriptGate.swift`) applies the host policy and the `allowed-tools` grant of the winning `SKILL.md`. It does not read the layer of the script for a permission. If `ScriptGate` still holds a marketplace grant input after the grant removal card, remove it here.
3. The `scripts/` rule, the confinement rule and the correctives do not change.

## Where the card text and the code differ

The code wins, and here is how:

1. **The grants of the layer that gives the script are gone.** Commit 3377f57 removed the marketplace grant concept. `ScriptGate` holds two gates only: the host `RenderPolicy` and the `allowed-tools` grant of the skill. Thus item 2 of **What** asked for a removal that was already done, and this card removed nothing from `ScriptGate`. The `directoryIndex` that `SkillOverlay.resolve(_:)` gives names the layer of the winning copy, and no gate reads it.
2. **The working directory of a run.** plan.md §7.3 states "cwd = the skill directory". One skill now has more than one layer directory, thus the run takes the layer directory that gave the winning copy of the script. A script then reaches the files beside it with a relative path, as it did before. plan.md still holds the old words; card ^71pp5x carries that correction.
3. **`ResourceIDLookup` gained `withResolvedOverlay(id:context:whenGranted:)`.** It resolves the id exactly as `withResolvedDirectory(id:context:whenGranted:)` does, and gives the overlay of the contributing directories. Card ^g9jt4sq puts `list resource` and `read resource` on the same call.
4. **The marketplace test moved.** `RunScriptTests` held `aScriptOfAMarketplaceLayerRunsUnderAPermissiveHostPolicy` and its fixture. That test is now in the new `ScriptGateTests.swift`, beside the two refusals, thus the two files hold no copy of one test. The readers of one `run script` outcome are now in `ResourceTestSupport`.

## Acceptance Criteria

- [x] A script that only a lower layer holds runs.
- [x] A script that two layers hold runs the copy of the higher layer.
- [x] A script that a marketplace layer gives runs under the same host policy as a local script.
- [x] `ScriptGate` has no marketplace grant input.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/RunScriptTests.swift`: a script that only the defaults layer holds runs and gives its output.
- [x] Same file: the same script path in two layers runs the higher copy.
- [x] `Tests/FoundationModelsSkillsTests/ScriptGateTests.swift`: a script from a marketplace layer is permitted or denied by the same host policy and `allowed-tools` rule as a local script.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#dotfolder-overlay #skills