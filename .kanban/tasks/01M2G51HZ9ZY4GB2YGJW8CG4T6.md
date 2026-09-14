---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'FoundationModelsRanker: SelectionTier sends a prompt to the model for an empty catalog'
---
## The problem

`SelectionTier.search` in `FoundationModelsRanker/Sources/FoundationModelsRanker/Selection/SelectionTier.swift` guards `limit > 0` only. For a catalog of zero items, the prompt is the preamble and an empty `# Candidates` part. The prompt stays below the budget, thus the tier sends it to the model. The model answers with prose, and `AgentSession.swift` throws when it decodes that prose as JSON.

^etc7n8d added a guard in this package (`SearchSkill.execute(in:)`), so `search skill` no longer reaches the tier with an empty catalog. Other callers of `MetadataSearcher` in `.auto` or `.selection` mode still reach it.

## The work

- [ ] In the `FoundationModelsRanker` repository, add a guard for an empty catalog beside `guard limit > 0` in `SelectionTier.search`. Return an empty result, and do not call the session.
- [ ] Add a unit test with a session double: a tier over zero items gives an empty result, and the double gets zero calls.

## When it is complete

- A selection tier over zero items sends no prompt and does not throw.