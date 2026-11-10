---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m732ayrrjew9jyy8ap0qp633
  text: |-
    ### EXTRAS-12 is on FoundationModelsExtras main (feature af13e80, head 4254281)
    The external dependency is satisfied. Run `swift package update FoundationModelsExtras` first. API (core target `FoundationModelsExtras`, `Sources/FoundationModelsExtras/Hosting/ToolMode.swift`):
    - `public enum ToolMode: String, Sendable, Codable, CaseIterable { case open, sandboxed }`
    - `public struct SandboxProbe: Sendable`: `.live`, `.fixed(Bool)` for tests, `init(isSandboxed:)`.
    - `public enum ToolModeError: Error { case openModeInSandbox }`
    - `mode.validate(probe: SandboxProbe = .live) throws(ToolModeError)`: call it at composition time (in `SkillsTool.make` or the `SkillsToolContext` init), before a tool is registered. Add a test with `.fixed(true)` and `.open` that expects `ToolModeError.openModeInSandbox`.
    Docs: Extras `docs/REFERENCE.md` ("Tool modes: ToolMode") and `docs/GUIDE.md`.
  timestamp: 2026-11-10T15:48:27.544429+00:00
- actor: claude-code
  id: 01m737be30gvd3vpxhffnx57pb
  text: |-
    ### Implementation notes
    - `swift package update FoundationModelsExtras`: resolved at main 4254281 (ToolMode present). Package.resolved did not change.
    - New public API (tell ACPAgent, ACPA-19):
      - `SkillsRegistry` public inits take `mode: ToolMode` with no default, right after the source: `init(roots:mode:policy:watch:templateContext:)`, `init(stack:mode:policy:watch:templateContext:)`, `init(layers:mode:policy:watch:templateContext:)`, `init(marketplaces:stack:mode:policy:watch:templateContext:)`. New `public let mode: ToolMode`.
      - `SkillsToolContext.init(registry:searchAgent:mode:sandboxProbe: = .live, visibilityPredicate:reloadFollower:catalogNoticeFollower:) throws`. It calls `mode.validate(probe:)` and throws `ToolModeError.openModeInSandbox`; it throws the new `SkillsToolContext.ModeMismatchError(registryMode:contextMode:)` when `mode != registry.mode`. New `public let mode`.
      - `ShellInjection.init(mode: ToolMode)` (was `init()`); `ShellInjection.disabledMarker` is removed.
      - `RenderPolicy` keeps only `shellCommandTimeout` and `shellOutputByteLimit`. `isShellExecutionDisabled` and `isScriptExecutionDisabled` are removed: ToolMode covers each use.
      - `SkillsTool.make(registry:...)` factories and `SkillsCLI.makeDriver(registry:)` take the mode from `registry.mode`; no new parameter.
    - `SkillsTool.make(context:)` does not register `RunScript` in `.sandboxed`. `ScriptGate` gate 1 is now the tool mode (`Script execution is not available in the sandboxed mode.`), for a host that dispatches `RunScript` against a sandboxed context directly.
    - What did not work: a first `ProcessRegistry.global` watch missed the pids, because `touch` ends before a sample, and because `URL.resolvingSymlinksInPath()` keeps `/var` while `proc_pidinfo` gives `/private/var`. The fix: each fixture command waits for a release file, the watch makes that file when it sees a pid whose working directory is in the fixture folder, and the fixture uses `realpath(3)`. I checked by hand that both no-process tests fail when the fixture is built in `.open`.
    - The `missing creator for mutated node ... mlx-swift_Cmlx.bundle` line is a SwiftPM build-system message from the dependency graph, not a compiler warning of this package.
  timestamp: 2026-11-10T17:16:06.112285+00:00
- actor: claude-code
  id: 01m737bh0ggfm4pv217dm8tays
  text: |-
    ### implement — changed
    - evidence: 62 files changed + new Tests/FoundationModelsSkillsTests/SandboxedModeTests.swift (11 tests). Sources: RenderPipeline.swift, ShellInjection.swift, SkillsRegistry.swift, SkillsToolContext.swift, SkillsTool.swift, SkillsToolAssembly.swift, SkillFilesText.swift, UseSkill.swift, ScriptGate.swift, RunScript.swift, SkillsCLI.swift; Examples/skills-demo; README.md, docs/operations.md, docs/security.md, docs/marketplaces.md; each test caller. `swift test`: 797 tests in 68 suites passed, 0 compiler warnings.
    - next: /review
  timestamp: 2026-11-10T17:16:09.104409+00:00
- actor: claude-code
  id: 01m737v15zvagvrtkfghy8ys1t
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD — 6 findings (6 confirmed, 9 refuted). Tests/FoundationModelsSkillsTests/SandboxedModeTests.swift:104, Tests/FoundationModelsSkillsTests/SandboxedModeTests.swift:119, Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift:213, Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift:265, Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift:444, Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift:59.
    - acceptance: the reviewer examined each acceptance criterion and test item against the code and ticked all 8. `swift test`: 797 tests in 68 suites pass. The build has no compiler warning. The build gives one SwiftPM build-system warning ("missing creator for mutated node") on the dependency product `mlx-swift_Cmlx.bundle`. That warning does not come from the source of this package.
    - next: correct the 6 findings in the dated Review Findings section, then run /review again.
  timestamp: 2026-11-10T17:24:37.183648+00:00
- actor: claude-code
  id: 01m737vsamfjsfzx95d2k0m5x0
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 62 files + SandboxedModeTests.swift
    - test: green — swift test, 797 passed in 68 suites, 0 warnings
    - commit: 6c5d30d (pushed at once: the code meets each criterion, and ACPAgent waits for the mode API)
    - review: findings — Tests/FoundationModelsSkillsTests/SandboxedModeTests.swift:104, :119; ShellInjectionTests.swift:213, :265, :444; SkillsToolAssemblyTests.swift:59
  timestamp: 2026-11-10T17:25:01.908724+00:00
- actor: claude-code
  id: 01m73826mph8jxbxp6es2k791x
  text: |-
    ### Review findings (2026-11-10 11:16) corrected
    - SandboxedModeTests.swift: renamed `noOpPutsAPidOfTheFixtureInTheProcessRegistry` to `noOpLeavesNoPidOfTheFixtureInTheProcessRegistry`. Replaced `runScriptGivenASandboxedContextDirectlyStartsNoProcess` with three tests, one assertion each: `...GivesACorrective`, `...WritesNoMarkerFile`, `...LeavesNoPidInTheProcessRegistry`. They use the new fixture helper `runScriptDirectly()`, which runs `RunScript.execute(in:)` under `ProcessRegistryWatch`. The new `makeWatch()` helper is shared with `callEveryOp()`. I built the fixture in `.open` for one run: all three tests failed, as expected. Then I restored `.sandboxed`.
    - ShellInjectionTests.swift: `render(_:mode:request:)` has `mode: ToolMode = .open`; the `pass` property is removed. The three sandboxed tests call the helper. `passOneAndTwoPipeline(stencil:)` has `stencil: any RenderPass = IdentityRenderPass()`. The metadata test, the git-context test and the single-shot test (real `StencilPass`) all call it, thus no inline copy of the pipeline is left in the file.
    - SkillsToolAssemblyTests.swift: `makeFixtureRegistry(mode: ToolMode = .open)`; the sandboxed case calls `makeFixtureRegistry(mode: .sandboxed)`. Added `import FoundationModelsExtras` for `ToolMode`. The `SkillsRegistry(roots:mode:)` call over an empty temp root is a different source, thus it stays.
    - Formatted only the three files (4 spaces, 120 columns).
  timestamp: 2026-11-10T17:28:32.150823+00:00
- actor: claude-code
  id: 01m73829dkhg6dan8p8jjqehdp
  text: |-
    ### implement — changed
    - evidence: 3 files — Tests/FoundationModelsSkillsTests/SandboxedModeTests.swift, Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift, Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift. `swift test`: 799 tests in 68 suites passed (797 before, plus 2 new), 0 compiler warnings. The one SwiftPM "missing creator for mutated node" line on mlx-swift_Cmlx.bundle is the known dependency build-system message.
    - next: /review
  timestamp: 2026-11-10T17:28:34.995797+00:00
- actor: claude-code
  id: 01m7384j69r624tra29sqftknr
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (dbed415): 0 findings, 0 confirmed, 0 refuted; 3 files reviewed, 7 attempted, 0 failed. All 6 prior findings are checked.
    - next: none. The task is in done. Follow-up task ^na244z4 removes the temporary `mode: ToolMode = .open` default.
  timestamp: 2026-11-10T17:29:49.513016+00:00
- actor: claude-code
  id: 01m73850wvde8fmyk0620ndd98
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 3 test files
    - test: green — swift test, 799 passed in 68 suites, 0 warnings
    - commit: dbed415
    - review: clean — 0 findings; task in done
    - note: hotfix 73ebb7a (temporary `mode = .open` default) is pushed; ^na244z4 removes it after ACPAgent ^bwgmkc0.
  timestamp: 2026-11-10T17:30:04.571545+00:00
depends_on:
- 01M7302DGMW7PA5MMAZ3DJBEDK
position_column: done
position_ordinal: ffad80
title: 'SK-7a: Skill scripts and shell injection only in open mode (ToolMode)'
---
## What
SK-7 (TestudoApp/features/packages/foundationmodels-skills.md, SK-7; D128 (d)). EXTERNAL DEPENDENCY: EXTRAS-12, the mode type `ToolMode` (`open` | `sandboxed`) in the core `FoundationModelsExtras` target, with the check that refuses `open` in a sandboxed process. It is not built yet (no `ToolMode` in `../FoundationModelsExtras/Sources`). Do not start this task before EXTRAS-12 is on Extras `main`. Then run `swift package update FoundationModelsExtras`.

Today two host switches exist in `RenderPolicy` (`Sources/FoundationModelsSkills/Render/RenderPipeline.swift:18,23`): `isShellExecutionDisabled` and `isScriptExecutionDisabled`. They do not give the SK-7 behavior:
- With `isScriptExecutionDisabled`, `RunScript` is still registered (`SkillsTool.swift:79`) and gives a corrective. SK-7 says it is not available.
- With `isShellExecutionDisabled`, `ShellInjection` (`Render/ShellInjection.swift:225`) puts `[shell execution disabled]` in the body. SK-7 says `` !`cmd` `` and ` ```! ` blocks stay as text.

Change:
- `SkillsToolContext` (`Operations/SkillsToolContext.swift`) and `SkillsRegistry` take `mode: ToolMode` (no default; change each caller in this package, and tell ACPAgent (ACPA-19) the new parameter). The registry gives the mode to `RenderPipeline`.
- `SkillsTool.make`: in `.sandboxed`, do not register `AnyOperation(RunScript.self)`. Make sure `verbAliasOverrides` and the description do not name `run script` in `.sandboxed`.
- `ShellInjection.render`: in `.sandboxed`, return the text with each injection site unchanged and start no process.
- `SkillFilesText.text` (`Operations/SkillFilesText.swift:42-48`): in `.sandboxed`, give no `runInstruction` line.
- Decide if the two `RenderPolicy` switches are still needed. If `ToolMode` covers each use, remove them and their callers (no backward compatibility, ARCHITECTURE.md). If a host still needs a kill switch in `open` mode, keep them and document why.
- In `.open`, nothing changes.

## Acceptance Criteria
- [x] In `.sandboxed`, the `skills` tool schema has no `run script` op, and the description does not name it.
- [x] In `.sandboxed`, `use skill` of a body with `` !`echo hi` `` and a ` ```! ` block gives both unchanged.
- [x] In `.sandboxed`, the files text of `use skill` has no "To run a script" line.
- [x] In `.sandboxed`, no operation of the `skills` tool starts a process (spec requirement).
- [x] In `.open`, the existing `RunScriptTests`, `ShellInjectionTests` and `SkillFilesTextTests` pass unchanged in behavior.

## Tests
- [x] `Tests/FoundationModelsSkillsTests/SandboxedModeTests.swift`: build the tool in `.sandboxed` over a fixture skill with a script and both injection forms. Call every op of the tool. Assert that `ProcessRegistry.global` gets no pid, and that a marker file which each command would write does not exist after the calls. Also assert the schema, the body text and the files text above.
- [x] Update `RunScriptTests`, `ShellInjectionTests`, `SkillFilesTextTests`, `SkillsToolAssemblyTests` for the `mode` parameter.
- [x] `swift test` passes with no warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1

## Review Findings (2026-11-10 11:16)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 57 file(s) reviewed, 6 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 4 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file
> - `docs/marketplaces.md` — no validator matches this file
> - `docs/operations.md` — no validator matches this file
> - `docs/security.md` — no validator matches this file

- [x] `Tests/FoundationModelsSkillsTests/SandboxedModeTests.swift:104` `test-integrity/no-test-cheating` — The test name `noOpPutsAPidOfTheFixtureInTheProcessRegistry` says a pid is put in the process registry, but the body asserts `pids.isEmpty`, which expects no pid. The name describes the opposite of what is proven, so a reader would believe the registry path is covered when the test only checks that nothing was registered. Rename the test to a name that matches the assertion, such as `noOpLeavesNoPidOfTheFixtureInTheProcessRegistry`. Keep the assertion, which is the meaningful check.
- [x] `Tests/FoundationModelsSkillsTests/SandboxedModeTests.swift:119` `test-integrity/no-test-cheating` — The test `runScriptGivenASandboxedContextDirectlyStartsNoProcess` asserts only that the output holds a corrective message. It never checks that no process started, no marker file was written, or the process registry is empty. The test name claims a property that the assertion does not prove, so the test would still pass if a process had started. Add an assertion that proves the name. Run the call under `ProcessRegistryWatch.pidsSeen` and assert the result is empty, or assert `fixture.existingMarkers()` is empty after the call. Keep the corrective-message check as a second assertion, or rename the test to say it only checks the corrective message.
- [x] `Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift:213` `reuse/reuse` — The sandboxed inline test builds its own render call. The existing private helper `render(_:request:)` already wraps this call, but it always uses the `pass` property, which is fixed to `.open`. The helper is a near-match that was not extended with a mode. Each sandboxed test repeats the wrap and the flatten. Extend the helper with a mode or pass parameter, for example `render(_ text: String, mode: ToolMode = .open, request:)`, and call it from the sandboxed tests. Use the same change for the fenced test at line 224.
- [x] `Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift:265` `reuse/reuse` — The new test rebuilds the `RenderPipeline` of open-mode argument substitution, open-mode shell injection, and identity Stencil. A helper that builds exactly this pipeline already exists, so the new copy diverges from it at once. Replace the inline construction with `let pipeline = passOneAndTwoPipeline()`.
- [x] `Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift:444` `reuse/reuse` — The git-context fixture test rebuilds the same identity-Stencil pipeline that `passOneAndTwoPipeline()` already returns, so the copy is a duplicate of an existing helper. Replace the inline construction with `let pipeline = passOneAndTwoPipeline()`.
- [x] `Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift:59` `reuse/reuse` — The sandboxed case builds its registry inline with SkillsRegistry(stack: FixtureLibrary.stack(), mode: .sandboxed). This is the same construction as makeFixtureRegistry() in this file, which differs only in the mode argument. A parallel copy lets the two fixtures drift apart. Give makeFixtureRegistry a mode parameter with a default of .open, for example makeFixtureRegistry(mode: ProbeMode = .open). Then call makeFixtureRegistry(mode: .sandboxed) at line 59 instead of building the registry inline.
