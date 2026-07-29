---
comments:
- actor: claude-code
  id: 01kyr0rk9meev5vsrcmvkk2qrc
  text: |-
    Implemented all three bullets. `SkillsRegistry.roots`/`.policy` and `RenderPolicy.isShellExecutionDisabled`/`.isScriptExecutionDisabled` are now `let` (construction-time invariants, doc comments updated to say so explicitly) — no external mutation site existed anywhere in Sources/Tests, so this was a pure signature tightening.

    Split `ScriptGate.evaluate` into `evaluateHostPolicy(isScriptExecutionDisabled:)` (gate 1 alone) and `evaluateGrant(path:allowedTools:)` (gate 2 alone), keeping `evaluate` as their composition for anyone still calling it directly. `RunScript.execute(in:)` now checks `evaluateHostPolicy` FIRST, before `ResourceIDLookup.withResolvedDirectory` (id lookup) or any path/scripts-prefix/confinement check — so a script-disabled registry returns the identical policy corrective for a valid path, an unknown id, a non-scripts/ path, or a confinement-escaping path alike, never leaking a path-shaped corrective ahead of the policy gate.

    Tests: RunScriptTests.swift gets a 4-case parameterized policy-first-ordering test (valid id/path, unknown id, non-scripts/ path, confinement escape — all assert the exact same "disabled" message). SkillsRegistryTests.swift gets a call(id:arguments:)-path shell-disable test (previously only proven via preloadedBodies()). SkillsCLITests.swift gets a CLI skill-use-path shell-disable test. All 268 tests passing (265 prior + 3 new).
  timestamp: 2026-07-29T22:43:44.052723+00:00
- actor: claude-code
  id: 01kyr18cyzr33y818z0zk98x8q
  text: Clean review (task k41ogpwcn, sha 2a73ed7..795a63f) — 0 findings after fixing the dead-code removal flagged in the prior round. Moved to done. All 268 tests passing.
  timestamp: 2026-07-29T22:52:21.855021+00:00
depends_on:
- 01KYQP8YX04FDQV1R78R3BHWDP
position_column: done
position_ordinal: '9780'
title: Make RenderPolicy and roots construction-time invariants (#25/#28)
---
## What
Variance from decisions #25/#28: `disableShellExecution`/`disableScriptExecution` must be "set at registry construction" — today `SkillsRegistry.policy` is a `public var` (`Registry/SkillsRegistry.swift:130`) with `RenderPolicy` fields also `public var` (`Render/RenderPipeline.swift:36-40`), read per render/dispatch, so any holder can re-enable shell/scripts after construction. `public var roots` (`:126`) is mutable but inert (catalog + StencilPass layers captured at init) — silently misleading.

- Make `policy` and `roots` `let` on `SkillsRegistry`; make `RenderPolicy` fields immutable (`let`) or keep the struct mutable but store it immutably in the registry.
- In `RunScript.execute`, evaluate gate 1 (host policy) BEFORE id lookup/path resolution (`Resources/RunScript.swift:140-164`) so a script-disabled registry never leaks path-shaped correctives (§7.3.1 "triple-gated, every check at dispatch").
- Close the #25 coverage gap: the disable flags are only tested via `preloadedBodies()` (`SkillsRegistryTests.swift:166-172`); add tests proving `disableShellExecution` is honored on the `call(id:arguments:)`/`use skill` path AND the CLI `skill use` path.

## Acceptance Criteria
- [ ] `registry.policy.… = …` no longer compiles (immutability enforced by the compiler)
- [ ] With scripts disabled, `run script` with ANY path (valid, bogus, escaping) returns the same policy corrective
- [ ] Shell-disable honored on call/use and CLI paths (inert marker, no process spawned)

## Tests
- [ ] Extend `Tests/FoundationModelsSkillsTests/RunScriptTests.swift` — policy-first ordering matrix
- [ ] Extend `SkillsRegistryTests` + `SkillsCLITests` — shell-disable on call and CLI paths
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.