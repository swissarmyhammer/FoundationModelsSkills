---
comments:
- actor: claude-code
  id: 01m2v1xn34btcdvyfcmx92f8g9
  text: |-
    ### Research

    - `SelectionTier` (Ranker) calls `respond(to:generating: Selection.self)`. The default of that method decodes plain text with `GeneratedContent(json:)`. A `[explore]` answer throws, and `MetadataSearcher.search` gives the error to `SkillSearchAgent.search`, then to `SearchSkill.execute`, which makes the whole `skills` call fail.
    - `SelectionConfig(model:)` takes `@Sendable (String) -> any AgentSession`. The closure gets the instructions only. Thus the package cannot get a per-call candidate set from the tier. Multitool has the same limit and uses one grammar over the full catalog. The tier drops an id outside the prompt with `.unknownSelectedId`.
    - `SelectionTier.idEnumSchema(ids:)` is public in Ranker and re-exported. It gives the JSON Schema text for `{"ids": [enum]}` with `uniqueItems` and `maxItems`.
    - `MetadataSearcher.retrievalSearch` is private. To get the rank of the tier below, the package must hold a second searcher in `.retrieval` mode. `MetadataIndex.build(items:embedder:)` is public, thus one index can be embedded one time and shared by the two searchers through `MetadataSearcher(index:...)`.
    - The package must stay free of the Router package (`DependencyGraphTests`). Thus a Router model handle cannot be a parameter. The plan: change the `session:` closure so that it takes a request value that carries the instructions, the candidate ids and the id-enum JSON Schema. Remove the live-session overload `make(registry:session: any AgentSession)`, because a plain-text session cannot take a per-call schema.
    - `DependencyGraphTests` pins `SkillsTool.make(registry:session:)` in the plan.md API sketch. Keeping the label `session:` keeps that pin true.
    - There is no CHANGELOG.md in the repo. It must be made.
  timestamp: 2026-09-18T20:04:28.900702+00:00
- actor: claude-code
  id: 01m2v26wmjzsst1dpeka2z0519
  text: |-
    ### implement — changed
    - evidence: 11 files — Sources/FoundationModelsSkills/Search/SelectionSessionRequest.swift (new), Sources/FoundationModelsSkills/Search/SkillSearchAgent.swift, Sources/FoundationModelsSkills/Operations/SkillsToolAssembly.swift, Sources/FoundationModelsSkills/Operations/SearchSkill.swift, Sources/FoundationModelsSkills/SeamReexports.swift, Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift, Tests/FoundationModelsSkillsTests/SkillSearchAgentTests.swift, Tests/FoundationModelsSkillsTests/ReadmeExampleTests.swift, README.md, CHANGELOG.md (new), plan.md (decision #31 and the §10 sketch)
    - card item 1: `session:` takes `@Sendable (SelectionSessionRequest) -> any AgentSession`; the request carries `instructions`, `candidateIDs` and the id-enum `jsonSchema` (`SelectionTier.idEnumSchema(ids:)`). The live-session overload is removed.
    - card item 2: `SkillSearchAgent` takes an optional `retrievalFallback` searcher; the factory builds it over the same index. A failed selection gives the retrieval rank and goes to the os log. Cancellation still goes to the caller.
    - card item 3: `aBareIDListAnswerGivesTheRetrievalRankNotAFailedCall`, `aSessionThatThrowsGivesTheRetrievalRankNotAFailedCall`, `theSessionRequestCarriesTheIdEnumSchemaOfTheVisibleCandidates`, and two `SkillSearchAgentTests` fallback cases.
    - card item 4: README migration section and CHANGELOG.md with the `ToolCatalog.makeSkillsTool` before/after.
    - targeted run: 25 tests in 4 suites passed.
    - next: test
  timestamp: 2026-09-18T20:09:31.538778+00:00
- actor: claude-code
  id: 01m2v28e1cz2p5d35mye6bg3cp
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` — 0 warnings, 0 errors; `swift test` — 713 tests in 54 suites passed, 0 failed, 0 skipped
    - next: commit
  timestamp: 2026-09-18T20:10:22.124411+00:00
- actor: claude-code
  id: 01m2v2dshz5t6rkrdfyfdc6yay
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 0 confirmed, 0 refuted; 7 validator runs, 0 failed. Not reviewed: README.md, CHANGELOG.md, plan.md (no validator matches), .kanban/ (ignore rule).
    - next: none; task moved to done

    ### finish iteration 1 — clean
    - implement: changed — SelectionSessionRequest with id-enum JSON Schema; `session:` closure takes the request; live-session overload removed; SkillSearchAgent retrieval fallback; tests; README + CHANGELOG migration note; plan.md decision #31
    - test: green — `swift test` 713 tests in 54 suites passed, 0 failed, 0 skipped; 0 build warnings
    - commit: 1d88b4c
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-18T20:13:17.759226+00:00
position_column: done
position_ordinal: f380
title: The skills search trusts free text from the selection model, and a bare [explore] fails the whole skills call
---
## What

SWE-bench run of 2026-09-18 14:13 in `FoundationModelsACPAgent`, instance `django__django-13447`. The model called the `skills` tool one time, to find a skill for its task. The call failed:

```
This operation failed while executing. Cause: Encountered content that cannot be completed into valid JSON
Text: [explore]
```

The selection model chose the correct skill, `explore`, but it wrote `[explore]`, not `{"ids": ["explore"]}`. The main model got a failed call with no next step. It did not try again, and no skill was loaded in that instance.

## Cause

1. `SearchSkill` runs the selection tier of FoundationModelsRanker through the session that the host gives to `SkillsToolAssembly.make(... session: @escaping @Sendable (String) -> any AgentSession ...)`.
2. The tier calls `respond(to:generating: Selection.self)`. The Ranker default of that method sends the prompt as plain text and then does `T(GeneratedContent(json: raw))`. Nothing constrains the shape of the answer.
3. A small model gives an answer with the wrong shape, the parse throws, and `OperationError.executionFailed` makes the whole `skills` call fail.

The rule that the host session must constrain the answer is only a doc comment of `AgentSession` in Ranker. The ACP agent gave a plain Router session, as the `session:` API invites. Each host of this package can do the same.

## Why the fix is here

The `skills` tool is a standalone tool. Its search answer must be correct for each host, with no special knowledge in the host. Multitool shows the model: `SearchToolsTool` takes the model handle (`librarian:`), and it builds its own grammar, `idEnumGrammar(ids:)` in `Discovery/SelectionGrammar.swift`. That grammar forces `{"ids": [...]}`, with each id from the candidate set of that call. A small model cannot write `[explore]` under it.

## The work

1. **The package owns the grammar.** The selection call of `SearchSkill` is constrained to `{"ids": [string]}`, with an enum of the candidate skill ids of that call. The package decides how it gets a grammar-capable model. For example: take a model handle as Multitool does; or change the `session:` API so that the host gives a session that takes a JSON schema per call. A plain-text session must not be enough to build the tool.
2. **One bad answer does not fail the call.** When the selection answer does not decode, the search gives the result of the tier below it (the keyword or embedding rank), or a corrective result that names the candidate ids and tells the model to call `use skill` with one of them.
3. **Tests.** A scripted selection model that answers `[explore]` gives a useful result, not a failed call. A test proves that the constrained path gives the enum schema of the candidates.
4. **Migration note** for hosts in the README and the CHANGELOG. `FoundationModelsACPAgent` passes `SelectionAgentSession(session: profile.flash.makeSession(...))` in `ToolCatalog.makeSkillsTool`, and it will change to the new API after this card.

## Where it was found

`FoundationModelsACPAgent`, SWE-bench run of 2026-09-18 (the run was stopped). #search #cross-repo