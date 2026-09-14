---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2g5bm6b8rv5qjyhmz0xs01a
  text: |-
    ### finish — skipped
    - evidence: the work is in the FoundationModelsRanker repository. The finish loop in FoundationModelsSkills commits and reviews only this repository, so it cannot checkpoint or review this change.
    - next: a person runs /finish on this task from a session in the FoundationModelsRanker repository, or moves the task to the board of that repository.
  timestamp: 2026-09-14T14:32:53.707634+00:00
- actor: claude-code
  id: 01m2g63jwjk98x2pwdht4wed1k
  text: |-
    ### handoff — sent
    - evidence: the user told me to work with the session in FoundationModelsRanker (foundationmodelsranker-5f). I sent it the full task text and asked it to run /finish there, commit locally only, and send back its task short id, commit sha and test counts.
    - next: when the reply arrives, record the result here and close this task.
  timestamp: 2026-09-14T14:45:58.802202+00:00
- actor: claude-code
  id: 01m2g6hkzpa9e4wsvvwn21tf83
  text: |-
    ### handoff — done in FoundationModelsRanker
    - evidence: Ranker task ^k4j6c3q is in done, review clean, 0 findings. Local commit 33e89d6 "fix(selection): stop the tier from sending a prompt for an empty catalog" (not pushed; I checked that it exists). It changes SelectionTier.swift and SelectionTests.swift. swift test: 283 passed, 0 failed, 0 skipped, 0 warnings.
    - change: `guard !catalog.ids.isEmpty else { return [] }` directly after `guard limit > 0`. Test `emptyCatalogSearchSendsNoPromptToTheSession` checks an empty result, forkCount == 0 and callCount == 0. Before the fix, it failed with forkCount 1 and callCount 1.
    - note: only the under-budget path had the defect.
    - next: none. The work and its review are complete in the repository that owns the code.
  timestamp: 2026-09-14T14:53:38.678379+00:00
position_column: done
position_ordinal: c780
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