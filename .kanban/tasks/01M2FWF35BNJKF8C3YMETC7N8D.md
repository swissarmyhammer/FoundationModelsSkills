---
comments:
- actor: claude-code
  id: 01m2g4xv2yt7nc170g221wrs71
  text: 'Research done. `SkillsTool.make(registry:session:)` builds the searcher in `.auto` mode with a `SelectionConfig`, which is the production path. `SkillsToolAssemblyTests` already has `RecordingAgentSession`, a double that counts `respond(to:)` calls. The plan: add a test there over an empty temporary skills root, with a session that answers prose (as the real model did). Without the guard, the prose decode must throw. With the guard, the tool must answer a corrective and the session must get zero calls. Existing `SearchSkill` tests seed the searcher with items but use the fixture registry, so a guard on `context.registry.metadata().filter(context.visibilityPredicate)` does not change them.'
  timestamp: 2026-09-14T14:25:22.014237+00:00
- actor: claude-code
  id: 01m2g524fwve2w3r7na52g3fny
  text: |-
    Implementation landed.

    - RED: the new test `searchOverAnEmptyStackAnswersACorrectiveAndSendsNoPrompt` failed with the production message, "This operation failed while executing." This confirms that the selection branch over an empty catalog sends a prompt and throws.
    - GREEN: `SearchSkill.execute(in:)` now has a second guard after the blank-query guard. When `context.registry.metadata()` holds no entry that `context.visibilityPredicate` accepts, it returns `.corrective("No skills are available.")`. It uses `contains(where:)`, so it makes no array copy. The doc comments of `SearchSkillOutput`, `SearchSkill` and `execute(in:)` now name both corrective conditions.
    - The test uses `SkillsTool.make(registry:session:)` over an empty temporary root. That factory builds the searcher in `.auto` mode with a selection tier, as production does, thus the test does not use the retrieval branch. The session double answers prose. The test asserts the exact corrective JSON and zero session calls.
    - Full suite: `swift test` — 408 tests in 32 suites pass, zero failures. `swift build --build-tests` gives no warning.
    - New task ^w8cg4t6 records the upstream `SelectionTier` guard in `FoundationModelsRanker`, which the card assigns to a task of its own.
    - Not verified here: the card's third completion item (the three SWE-bench instances make a patch). That check needs a new run of `FoundationModelsACPAgent` against a build that has this change. It cannot run from this package.
  timestamp: 2026-09-14T14:27:42.716184+00:00
- actor: claude-code
  id: 01m2g526pcdwcn9ka43pk3qsyc
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsSkills/Operations/SearchSkill.swift, Tests/FoundationModelsSkillsTests/SkillsToolAssemblyTests.swift; swift test 408 passed, 0 failed, 0 warnings
    - next: /review. Open item outside this package: rerun the three SWE-bench instances to confirm the third completion item.
  timestamp: 2026-09-14T14:27:44.972707+00:00
- actor: claude-code
  id: 01m2g5ac2qgysb726g0seqfy7h
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD. 2 files reviewed. 0 findings, 0 confirmed, 0 refuted (7 attempted, 0 failed). 4 files in .kanban/ are not reviewed because of .reviewignore.
    - next: none. The task moved to done.
  timestamp: 2026-09-14T14:32:12.631178+00:00
- actor: claude-code
  id: 01m2g5aqs64n0vw893m45dc139
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files
    - test: green — swift test, 408 passed
    - commit: 027a1d2
    - review: clean — 0 findings
  timestamp: 2026-09-14T14:32:24.614411+00:00
position_column: done
position_ordinal: c680
title: search skill throws when the stack holds no skill, and it kills the caller's turn
---
## The problem

`search skill` fails when the skill stack holds no skill. The caller gets this
message, and nothing more:

```
This operation failed while executing.
```

The failure is not a small one for the caller. In the SWE-bench run of
2026-09-13, `FoundationModelsACPAgent` mounted this tool and shipped no skill
of its own. Three of the 16 instances called the tool. All three failed, each
one in 20 to 141 seconds, and each lost its whole turn and made no patch. The
host cancels the other tool calls of a turn when one call fails, so a second
call that was correct died with it.

## Why it fails

A search over zero skills still asks the model a question.

1. `Operations/SearchSkill.swift:128` calls `context.searchAgent.search(...)`.
2. `Search/SkillSearchAgent.swift:54` calls `searcher.search(intent:limit:)`.
3. The host builds the searcher in `.auto` mode WITH a selection tier, so
   `MetadataSearcher+Search.swift:152` takes the selection branch. The
   retrieval branch, which has an empty guard at
   `MetadataSearcher+Search.swift:246`, is never used.
4. `MetadataSearcher.swift:304` builds the tier for a catalog of zero items.
   There is no empty-catalog guard.
5. `SelectionTier.search` guards `limit > 0` only
   (`Selection/SelectionTier.swift:178`). With no skill the prompt is the
   header alone, `preamble + "\n\n# Candidates\n"`
   (`SelectionTier.swift:433`), which stays below the budget. So the tier
   sends one real prompt to the model.
6. The model gets a `# Candidates` part with nothing in it, and a preamble
   that tells it to use only the ids it can see. It answers with prose.
7. The answer is decoded as JSON, and the decode throws:
   `Selection/AgentSession.swift:111`, `return try T(GeneratedContent(json: raw))`.

The two conditions give the same failure. `Discovery/SkillDiscovery.swift:129`
answers `[]` for a directory that does not exist, and for a directory that is
empty. Nothing after that point can tell the two apart.

## The work

Guard the empty catalog in this package, beside the blank-query guard that is
there already.

- `Sources/FoundationModelsSkills/Operations/SearchSkill.swift:113` — before
  line 128 reaches the search agent, answer `.corrective` with a message such
  as "No skills are available." when
  `context.registry.metadata().filter(context.visibilityPredicate)` is empty.

This is the correct place. This package knows that a search over zero skills
has no meaning, and the guard costs no token and no model call.

A second guard upstream gives depth, and it belongs to a task of its own:
`FoundationModelsRanker/Sources/FoundationModelsRanker/Selection/SelectionTier.swift:179`,
beside `guard limit > 0`, add a guard for an empty catalog.

## Why no test caught it

The tests of `SearchSkill` build their context with
`Tests/FoundationModelsSkillsTests/FixtureLibrary.swift:106`, and that helper
makes a `MetadataSearcher` with NO `selection:`. So every test takes the
retrieval branch, which has the guard. The selection branch, which is what
production uses, has no test in this package.

`Tests/FoundationModelsSkillsTests/SkillsReloadFollowerTests.swift:136` builds
a searcher over `items: []`, but in `.retrieval` mode, and it tests the
reload.

## When it is complete

- `search skill` over an empty stack answers, and does not throw.
- A test builds a context with NO skill and a selection tier, and it proves
  the answer. The test must not use the retrieval branch.
- The three instances of the run make a patch, or they fail for a reason that
  is not this one.