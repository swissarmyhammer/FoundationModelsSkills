---
depends_on:
- 01M3MNGJMH6FMPX4VFWJ12KKSS
position_column: todo
position_ordinal: '8180'
title: 'OTel B: add spans and metrics for skill search and skill load, and the content-safety test'
---
## What

Part of the OpenTelemetry design that the user approved on 2026-09-28 (copy: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer/9f4fa2e8-6833-46c6-bb95-5091ae3613fa/scratchpad/otel-design.md). Rules 1, 3, 4, 5 and 8. Add spans for skill search and skill load, add the metrics search duration and skills loaded, and add the content-safety test of this package.

This task depends on Extras task OTel B ^z6jqd9g (01M3MN8N9P4RPET2V5JZ6JQD9G), the `TelemetryTestSupport` product with the content-safety helper, and on Extras task OTel C ^ykgz2aa (01M3MN91YK71YVJ9C7WYKGZ2AA), the helper that opens a span and writes one "enter" log record. The board cannot link a task on another board, so these dependencies are written here only.

Research (where each span and metric goes):
- Skill search: `SkillSearchAgent.answer(query:limit:)` in `Sources/FoundationModelsSkills/Search/SkillSearchAgent.swift` (near line 105); `search(query:limit:)` (near 85) calls it. The selection tier calls a language model and can suspend for a long time, so use the Extras "enter" helper. Attributes: limit, result count, tier (`isSelection` of `SkillSearchAnswer`), and whether the fallback answered. The operation entry is `Operations/SearchSkill.swift` `execute(in:)` (near 134); it does not need a second span.
- Skill load (one skill): `SkillsRegistry.call(id:arguments:)` in `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift` (near 989). It renders the body through `RenderPipeline.renderBody` (`Render/RenderPipeline.swift` near 324), which can run shell injection (`Render/ShellInjection.swift`) and so can suspend for a long time: use the "enter" helper. Attribute: `skill.id` (a name, safe). Never the arguments or the rendered body. `Operations/UseSkill.swift` `execute(in:)` (near 131) is the operation entry.
- Catalog load: `SkillsRegistry.buildCatalog(...)` (private static, near 627), used by the initializers (near 251 to 331) and the hot-reload path (near 1096 `replace(catalog:diagnostics:)`). Attributes: skill count and diagnostic count.
- Metrics: `searchDuration` timer in `answer(query:limit:)` with dimension `search.tier`; `skillsLoaded` from the catalog size after each catalog load.

Do this:
- [ ] Depends on the vocabulary and swift-log task of this board.
- [ ] Add the spans and metrics with the names of `SkillsTracing` only. Open spans with `SkillsTracing.tracer(explicit:)`. Decide if `SkillSearchAgent` and `SkillsRegistry` take an optional `tracer` and `MetricsFactory` for tests; document the choice.
- [ ] Add the test-only products `InMemoryTracing` (swift-distributed-tracing), `MetricsTestKit` (swift-metrics) and `TelemetryTestSupport` (FoundationModelsExtras) to `testOnlyDependencies` in `Package.swift`.
- [ ] Write the content-safety test (see Tests). Update the doc comment of `SkillsTracing` to name it.
- [ ] Doc comments in ASD-STE100 Simplified Technical English.

## Files to change
- `Sources/FoundationModelsSkills/Search/SkillSearchAgent.swift`
- `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`
- `Sources/FoundationModelsSkills/Tracing/SkillsTracing.swift`
- `Package.swift` (test dependencies)
- New: `Tests/FoundationModelsSkillsTests/SkillsTelemetryTests.swift`
- New: `Tests/FoundationModelsSkillsTests/TelemetryContentSafetyTests.swift`

## Acceptance Criteria
- [ ] One `answer(query:limit:)` call gives one `search` span with the limit, result count and tier, one "enter" log record, and one `searchDuration` value.
- [ ] One `call(id:arguments:)` gives one `skillLoad` span with `skill.id` and one "enter" log record; a thrown error is recorded on the span.
- [ ] One catalog build gives one `catalogLoad` span and one `skillsLoaded` value equal to the skill count.
- [ ] The content-safety test passes, and it fails when a marker is put in one attribute on purpose (check one time, then remove it).

## Tests
- [ ] New `Tests/FoundationModelsSkillsTests/SkillsTelemetryTests.swift` with an explicit `InMemoryTracer` and `TestMetrics` over the fixture library (`FixtureLibrary.swift`): one test for search, one for skill load, one for catalog load and hot reload.
- [ ] New `Tests/FoundationModelsSkillsTests/TelemetryContentSafetyTests.swift`: put a unique marker in the search query, the skill arguments, a skill body and the output of a script; run a search (with a selection tier that fails, so the fallback runs), a skill load and a reload; give all captured spans, log records and metrics to the Extras content-safety helper, which fails on the marker.
- [ ] `swift test --parallel` passes. With `swift test --filter`, use a regex with the target name and check that the count of tests that ran is not zero.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Do not run `swift format`.