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
depends_on:
- 01M7302DGMW7PA5MMAZ3DJBEDK
position_column: doing
position_ordinal: '80'
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
- [ ] In `.sandboxed`, the `skills` tool schema has no `run script` op, and the description does not name it.
- [ ] In `.sandboxed`, `use skill` of a body with `` !`echo hi` `` and a ` ```! ` block gives both unchanged.
- [ ] In `.sandboxed`, the files text of `use skill` has no "To run a script" line.
- [ ] In `.sandboxed`, no operation of the `skills` tool starts a process (spec requirement).
- [ ] In `.open`, the existing `RunScriptTests`, `ShellInjectionTests` and `SkillFilesTextTests` pass unchanged in behavior.

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SandboxedModeTests.swift`: build the tool in `.sandboxed` over a fixture skill with a script and both injection forms. Call every op of the tool. Assert that `ProcessRegistry.global` gets no pid, and that a marker file which each command would write does not exist after the calls. Also assert the schema, the body text and the files text above.
- [ ] Update `RunScriptTests`, `ShellInjectionTests`, `SkillFilesTextTests`, `SkillsToolAssemblyTests` for the `mode` parameter.
- [ ] `swift test` passes with no warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1