---
depends_on:
- 01KYQP8YX04FDQV1R78R3BHWDP
position_column: todo
position_ordinal: '9680'
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