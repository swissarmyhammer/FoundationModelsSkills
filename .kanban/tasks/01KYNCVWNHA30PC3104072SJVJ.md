---
depends_on:
- 01KYNCSXAEKDVR36H387H5TYXR
position_column: todo
position_ordinal: 8d80
title: SkillMetadata + SkillSearchAgent over MetadataSearcher
---
## What
The discovery backend (plan §7, decision #26): a thin wrapper over `MetadataSearcher` from `../FoundationModelsMetadataRegistry`.

- `Sources/FoundationModelsSkills/Search/SkillMetadata.swift` — conform the registry's metadata row to the sibling's `SearchableMetadata` protocol (read its declaration first): id, rendered description, parameter summary — rendered as the text block the searcher indexes; never full bodies.
- `Sources/FoundationModelsSkills/Search/SkillSearchAgent.swift` — wraps `MetadataSearcher<SkillMetadata>`:
  - Init takes a configured `MetadataSearcher` (selection model, mode, weights are the CALLER's business — plan: knobs live in `SkillsToolContext` construction).
  - `search(query:limit:) -> [SkillMetadata]` ranked matches + total.
  - `update(items:)` forwards the model-visible subset on registry reload (hash-guarded incrementality is the sibling's job).
  - Seeds only model-visible items.
- Test doubles per plan §13: replicate the sibling's `FakeEmbedder` (counting `TextEmbedding`) and `ScriptedAgentSession` (`AgentSession`) patterns (~a dozen lines each) in our test target — its own doubles are not importable. Drive a REAL `MetadataSearcher` in `.retrieval` mode for GPU-free tests.

## Acceptance Criteria
- [ ] Seeding filters to model-visible metadata only (`lint` present, `deploy` absent)
- [ ] A keyword query over the fixture catalog returns the expected ranked ids with totals
- [ ] `update(items:)` after a catalog change makes a new id searchable and drops removed ids

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/SkillSearchAgentTests.swift` — real `MetadataSearcher` + `FakeEmbedder`, retrieval mode; seed-filtering; search; update round trip
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.