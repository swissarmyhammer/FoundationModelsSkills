---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mysq57waeemd2mc4bh6ngz
  text: 'User decision: "no way, we don''t want to be writing to error, we want otel support. the demo doesn''t need to log the otel". The demo bootstraps `SwiftLogNoOpLogHandler`. The description is updated.'
  timestamp: 2026-09-28T21:30:09.447875+00:00
- actor: claude-code
  id: 01m3myxz1b7nzm918bapqk7wmw
  text: 'Research: `Examples/skills-demo/SkillsDemoMain.swift` `main()` is the one start point for all four modes (CLI, --chat, --watch, --marketplace). The `skills-demo` target links `commonDependencies`, which holds the `Logging` product, thus no manifest change is necessary. The "enter" record message is `enter <span name>` (`ExtrasTelemetry.EnterRecord`, internal to Extras). The span names are `SkillsTracing.SpanName.search`, `.skillLoad`, `.catalogLoad` (internal; the test target reads them through `@testable import`). `SkillsDemoTests.run` already keeps standard output apart from standard error. Plan: RED test in `SkillsDemoTests` (parameterized over `skill search` and `skill use`) holds that no standard-error line holds a span name; GREEN: `LoggingSystem.bootstrap(SwiftLogNoOpLogHandler.init)` as the first statement of `main()`.'
  timestamp: 2026-09-28T21:32:28.587648+00:00
- actor: claude-code
  id: 01m3mzb42pjp62njtzh24m7bjf
  text: 'Implementation landed (TDD). RED: the new parameterized test `SkillsDemoTests.cliRunWritesNoEnterLineToStandardError(arguments:)` failed for both runs with the expected lines, `info FoundationModelsSkills.search: [FoundationModelsExtras] enter FoundationModelsSkills.search` and `info FoundationModelsSkills.registry: [FoundationModelsExtras] enter FoundationModelsSkills.skill.load`. GREEN: `LoggingSystem.bootstrap(SwiftLogNoOpLogHandler.init)` is the first statement of `SkillsDemoMain.main()`, before each mode, and the file imports `Logging`. No tracer or metrics factory is bootstrapped. The test also moved the search and use argument lists into `searchArguments` / `useArguments`, which the two older CLI cases now read, and the stale `RunResult` doc comment (it said standard error holds the log records) is corrected. The CHANGELOG records only public API changes, thus it gets no entry. Note: each `swift build` / `swift test` in this environment writes SwiftPM "failed loading cached manifest ... disk I/O error" warnings. They come from the SwiftPM manifest cache on this machine, not from the code; no `.swift` file has a compiler warning.'
  timestamp: 2026-09-28T21:39:39.734111+00:00
- actor: claude-code
  id: 01m3mzb5xayhf1sszfj24ycj5g
  text: |-
    ### implement — changed
    - evidence: 2 files — Examples/skills-demo/SkillsDemoMain.swift, Tests/FoundationModelsSkillsTests/SkillsDemoTests.swift. `swift test`: 586 tests in 56 suites passed, 0 failed, 0 compiler warnings.
    - next: /review
  timestamp: 2026-09-28T21:39:41.610888+00:00
- actor: claude-code
  id: 01m3mzkzdg8f49xjveyqaj87ee
  text: |-
    ### test — green
    - evidence: swift test --parallel — 586 tests in 56 suites passed, 0 failed, 0 skipped. swift build --build-tests after touching every Swift file (forced full recompile of package targets) — Build complete, 0 compiler warnings.
    - note: SwiftPM prints 32 "failed loading/storing manifest ... disk I/O error" lines at startup. They come from the SwiftPM manifest cache in this environment, not from package source. No source change can affect them.
    - next: review
  timestamp: 2026-09-28T21:44:29.872813+00:00
- actor: claude-code
  id: 01m3mzrnt41xj3d6mvgb2zhv3p
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (cedd0af). 0 findings, 0 confirmed, 0 refuted. 2 files reviewed. 4 .kanban files not reviewed (excluded by .reviewignore).
    - next: none. The task is in done.
  timestamp: 2026-09-28T21:47:03.876580+00:00
- actor: claude-code
  id: 01m3mzrx9ecqnv514s119q9etc
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files (Examples/skills-demo/SkillsDemoMain.swift, Tests/FoundationModelsSkillsTests/SkillsDemoTests.swift)
    - test: green — swift test --parallel, 586 tests in 56 suites passed, 0 compiler warnings
    - commit: cedd0af
    - review: clean — 0 findings
  timestamp: 2026-09-28T21:47:11.534334+00:00
position_column: done
position_ordinal: ff9680
title: 'skills-demo: bootstrap logging at startup (OTel rule 6)'
---
## What

Rule 6 of the OpenTelemetry design of 2026-09-28 (copy: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer/9f4fa2e8-6833-46c6-bb95-5091ae3613fa/scratchpad/otel-design.md): an executable must always bootstrap logging. The `skills-demo` executable (`Examples/skills-demo`) does not call `LoggingSystem.bootstrap`.

Found in ^z097jdt. Since that task, a skill search and a skill load each write one "enter" record at level `info` (`TracedCall` of `FoundationModelsExtras`). With no bootstrap, swift-log uses its default handler, which writes each record to standard error. Thus each `skills-demo skill search` and `skills-demo skill use` run writes one or more `enter FoundationModelsSkills...` lines to standard error. `SkillsDemoTests` now reads standard output apart from standard error, thus the tests pass, but a user sees the lines.

## Decision (user, 2026-09-28)

The telemetry must not go to standard error. The package gives OpenTelemetry support through the swift-log, swift-distributed-tracing and swift-metrics APIs; an OTel backend that the host bootstraps receives the records. The demo does not need to log the telemetry. Thus `skills-demo` bootstraps the handler that does nothing (`SwiftLogNoOpLogHandler`). The demo does not bootstrap a tracer or a metrics factory, so the defaults (no-op) stay.

## Do this
- [x] Decide with the user which handler the demo bootstraps: the handler that does nothing (`SwiftLogNoOpLogHandler`). No stderr handler, no level switch.
- [x] Call `LoggingSystem.bootstrap` one time at the start of `skills-demo`, before it makes a registry or a search agent, with `SwiftLogNoOpLogHandler`.
- [x] Add a test in `SkillsDemoTests` that runs `skill search` and `skill use` and holds that standard error has no `enter` line (no telemetry text).
- [x] Doc comments in ASD-STE100 Simplified Technical English.

## Workflow
- Use `/tdd`.
- Do not run `swift format`.