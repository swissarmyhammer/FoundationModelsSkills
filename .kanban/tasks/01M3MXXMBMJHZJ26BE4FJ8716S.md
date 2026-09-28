---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'skills-demo: bootstrap logging at startup (OTel rule 6)'
---
## What

Rule 6 of the OpenTelemetry design of 2026-09-28 (copy: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer/9f4fa2e8-6833-46c6-bb95-5091ae3613fa/scratchpad/otel-design.md): an executable must always bootstrap logging. The `skills-demo` executable (`Examples/skills-demo`) does not call `LoggingSystem.bootstrap`.

Found in ^z097jdt. Since that task, a skill search and a skill load each write one "enter" record at level `info` (`TracedCall` of `FoundationModelsExtras`). With no bootstrap, swift-log uses its default handler, which writes each record to standard error. Thus each `skills-demo skill search` and `skills-demo skill use` run writes one or more `enter FoundationModelsSkills...` lines to standard error. `SkillsDemoTests` now reads standard output apart from standard error, thus the tests pass, but a user sees the lines.

## Do this
- [ ] Decide with the user which handler the demo bootstraps (rule 6: a handler that writes to standard error, or a handler that does nothing, when no OTLP endpoint is set) and at which level.
- [ ] Call `LoggingSystem.bootstrap` one time at the start of `skills-demo`, before it makes a registry or a search agent.
- [ ] Add a test in `SkillsDemoTests` that holds the standard error of a `skill search` run to the decided behavior.
- [ ] Doc comments in ASD-STE100 Simplified Technical English.

## Workflow
- Use `/tdd`.
- Do not run `swift format`.