---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0zc7xycs1cy46h1fdzb8chk
  text: |-
    ### finish — skipped in this batch
    - Reason: the acceptance criteria require a change in a different repository (`FoundationModelsRanker`, upstream) and then a `Package.resolved` move to that fix. This batch works only the current working tree, so it cannot complete the task.
    - A person must make the upstream change first. After that, `/finish ^w5mjseg` can remove the `GuidedSelectionSession` wrapper in `Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift`.
  timestamp: 2026-08-26T15:50:25.484877+00:00
position_column: todo
position_ordinal: '9380'
title: 'FoundationModelsRanker: AgentSession.respond(to:generating:) is not a protocol requirement, so the LanguageModelSession guided override is unreachable through `any AgentSession`'
---
## What
Found while `^tb86z9q` was in implement. In the dependency `FoundationModelsRanker` (`Sources/FoundationModelsRanker/Selection/AgentSession.swift`), the protocol `AgentSession` declares only `respond(to:)` and `fork()` as requirements. The typed `respond<T: Generable>(to:generating:)` is an extension method only. `SelectionTier` calls it on `any AgentSession`, so the call always goes to the extension default (plain text, then `GeneratedContent(json:)`). The override in `LanguageModelSessionSupport.swift` that uses native guided generation is never reached through the existential.

Effect: every `SelectionConfig.model` closure that returns a bare `LanguageModelSession` fails with `Encountered content that cannot be completed into valid JSON` on the first selection call. `^tb86z9q` works around this in this package's test target with a `GuidedSelectionSession` wrapper.

## Acceptance Criteria
- [ ] Upstream `FoundationModelsRanker` declares `respond(to:generating:)` as an `AgentSession` protocol requirement (with the current extension body as the default), so the `LanguageModelSession` override dispatches through `any AgentSession`
- [ ] After the upstream fix lands and `Package.resolved` moves to it, the `GuidedSelectionSession` wrapper in `Tests/FoundationModelsSkillsTests/HotReloadLiveTests.swift` is removed and the test returns a bare `LanguageModelSession`

## Tests
- [ ] `SKILLS_INTEGRATION_TESTS=1 swift test --filter HotReloadLiveTests` — exit 0 with the bare `LanguageModelSession`
- [ ] `swift test` — exit 0