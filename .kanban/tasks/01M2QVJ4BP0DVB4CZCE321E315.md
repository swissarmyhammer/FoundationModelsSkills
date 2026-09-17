---
assignees:
- claude-code
position_column: todo
position_ordinal: '9480'
title: 'ACPAgent: ConfigOptionsTests keeps a private copy of the agentText reader'
---
## What

**Cross-repository task.** The code is in `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent`.

Card `^je0whap` put the shared reader `ScriptedTurnFixture.agentText(in:)` in
`Tests/FoundationModelsACPAgentTests/Support/ScriptedTurnFixture.swift`, beside the
other sequence readers.

`Tests/FoundationModelsACPAgentTests/ConfigOptionsTests.swift` still holds a
private `agentText(in:)` of its own, written before the shared one. The two read
the same `agent_message_chunk` text.

Make `ConfigOptionsTests` call the shared reader, and delete its private copy.

- [ ] Delete the private `agentText(in:)` of `ConfigOptionsTests`
- [ ] Call `ScriptedTurnFixture.agentText(in:)` at each site

## Acceptance Criteria
- [ ] One reader, in `ScriptedTurnFixture`
- [ ] `swift test --filter ConfigOptionsTests` passes

## Tests
- [ ] `swift test --filter ConfigOptionsTests`