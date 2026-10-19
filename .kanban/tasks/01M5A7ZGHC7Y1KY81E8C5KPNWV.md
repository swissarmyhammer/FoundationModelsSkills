---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5a84nx19ex69wx08qv3gdc6
  text: 'Decision on the `id` enum (foundationmodelsacpagent-a5, 2026-10-19): option (a). `id` becomes a plain string for every session, and the use skill corrective is the guard. That work is task wfhkw3j, which this task now depends on. The agents tool does the same for `name` (^x27vjcb).'
  timestamp: 2026-10-19T14:13:10.689943+00:00
- actor: claude-code
  id: 01m5a8dztmvvj23q51qmqwe0bw
  text: |-
    Unblocked: the Extras API is on its origin/main as e6b2bf9 (Hosting/CatalogChangeNotice.swift and Hosting/CatalogNoticeBoard.swift).
    1. The ReloadCoordinator holds one `CatalogNoticeBoard()` for the skills catalog and gives it to each tool that is made.
    2. `SkillsCatalogTool` conforms to `CatalogNoticing` (`var catalogNoticeBoard: CatalogNoticeBoard`). Sessions join through `ToolMounting.makeWrapped`, root and child sessions alike, and leave when their WorkRegistry closes.
    3. On a reload: `if let n = CatalogChangeNotice(kind: .skills, from: old, to: new) { await board.post(n) }`, with old and new mapped by bq1dx6d.
    4. Test: mount with `ToolMounting.makeWrapped(tool:site: MountSite(sessionID:runPlane: RunPlane(workRegistry: WorkRegistry(sessionID:)), sink: s), configuration: .synchronous)`, where the sink adopts both OperationEventSink and CatalogNoticeSink. Check `post(catalogNotice:)` and `board.sessionIDs`.

    Race: a tool made from catalog v1 can miss a v2 reload that is posted before its session mounts the tool. Read the catalog as late as possible, and pin this with a test.

    Note: the Router's SessionOutbox does not adopt CatalogNoticeSink yet, so a real session drops the notice. That is Router work, outside this task.
  timestamp: 2026-10-19T14:18:15.764545+00:00
- actor: claude-code
  id: 01m5acxxbs7da6bwc3jsm9x86t
  text: |-
    Research (implement):
    - Package.resolved pins Extras at 39c9cde (past e6b2bf9). The API is `CatalogNoticing { var catalogNoticeBoard }`, `CatalogNoticeBoard()` with `post(_:)` and `sessionIDs`, `CatalogNoticeSink.post(catalogNotice:)`. `ToolMounting.makeWrapped` joins the board; `WorkRegistry.close()` leaves it. `ToolContext.childSite(sessionID:runPlane:sink:)` makes a child site.
    - Owner choice: the board belongs to `SkillsToolContext`, not the registry. The notice is diffed with the context's `visibilityPredicate`, so a board per registry would let two tools with different predicates post two notices to one board. The context keeps one board, and a new `SkillsCatalogNoticeFollower` that `makeContext` builds next to `SkillsReloadFollower` (fresh `onReload` subscription first, seed read last). The context derives its board from the follower, so the two cannot differ. `SkillsTool.make(context:)` gives `context.catalogNoticeBoard` to each tool.
    - The follower checks `Task.isCancelled` before each post: an `AsyncStream` can still hand a buffered value to a cancelled task, so without the check a released follower could post one more notice.
    - The notice follower does not depend on `followReloads` (that flag only means that the host pumps the search agent itself). It exists whenever `registry.onReload` is not nil.
  timestamp: 2026-10-19T15:36:51.833398+00:00
- actor: claude-code
  id: 01m5ad7h2rpfemky21ckzq9cn6
  text: |-
    ### implement — changed
    - evidence: 7 files. New: Sources/FoundationModelsSkills/Operations/SkillsCatalogNoticeFollower.swift, Tests/FoundationModelsSkillsTests/SkillsCatalogNoticeTests.swift (11 tests). Changed: Operations/SkillsToolContext.swift (adds `catalogNoticeFollower` and `catalogNoticeBoard`, as a defaulted init parameter), Operations/SkillsCatalogTool.swift (`catalogNoticeBoard`, conforms to `CatalogNoticing`), Operations/SkillsTool.swift (`make(context:)` gives the tool `context.catalogNoticeBoard`), Operations/SkillsToolAssembly.swift (`makeContext` subscribes to `onReload` first and reads the seed last), Package.swift (ULID.swift 1.3.1 as a test-only dependency, so the tests can make session ids). RED: `swift build --build-tests` failed on the missing symbols. GREEN: `swift test --filter SkillsCatalogNoticeTests` passed 11/11. Full `swift test`: 644 tests in 59 suites passed. The one warning is the SwiftPM `missing creator for mutated node` on the mlx-swift_Cmlx.bundle, which comes from the build system and not from this code.
    - Race pin: `aSessionThatMountsAfterAReloadMissesItsNoticeAndGetsTheNextOne`. A session that mounts after a reload gets no notice for that reload. Its next notice is diffed against that reload's catalog, and its description still lists the catalog of the time the tool was made.
    - No public factory signature changed. The `SkillsToolContext.init` change is a defaulted parameter, so existing callers still compile.
    - Open: the acceptance item "send the sha to foundationmodelsacpagent-a5" waits for the user's push.
    - next: /review
  timestamp: 2026-10-19T15:42:06.936682+00:00
- actor: claude-code
  id: 01m5ad90tw07wpnyg9h6r8y9y7
  text: |-
    ### test — green
    - evidence: swift test — 644 tests in 59 suites passed, 0 failed, 0 skipped; only build warning is the known mlx-swift_Cmlx.bundle "missing creator for mutated node" (dependency, seen again); SkillsCatalogNoticeTests 3/3 passed in the full run
    - next: 5x repeat of SkillsCatalogNoticeTests not run (test rules forbid looping test runs)
  timestamp: 2026-10-19T15:42:55.836978+00:00
- actor: claude-code
  id: 01m5ad9ps4pdkbym4p2prqn9jc
  text: |-
    ### commit — changed
    - evidence: f8ff30e feat(skills-tool): post one catalog-change notice per reload to every live session
    - next: review
  timestamp: 2026-10-19T15:43:18.308135+00:00
- actor: claude-code
  id: 01m5ade87c33z9rmhke1x4thhw
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (f8ff30e) — 0 findings, 0 confirmed, 0 refuted; 7 files reviewed, 0 failed; 4 .kanban files excluded by .reviewignore
    - next: task moved to done. The open acceptance item (after the push, the user's step, send the sha to foundationmodelsacpagent-a5) is outside this pipeline.
  timestamp: 2026-10-19T15:45:47.244029+00:00
- actor: claude-code
  id: 01m5adehc178dnrdbrt8jb03qb
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 7 files (SkillsCatalogNoticeFollower, SkillsToolContext, SkillsCatalogTool, SkillsTool, SkillsToolAssembly, Package.swift, SkillsCatalogNoticeTests)
    - test: green — swift test, 644 tests in 59 suites
    - commit: f8ff30e
    - review: clean — no findings; the task is in done
  timestamp: 2026-10-19T15:45:56.609788+00:00
depends_on:
- 01M5A7Z0YGYG5Y3MR7EBQ1DX6D
- 01M5A84CYKC62A5H2MMWFHKW3J
position_column: done
position_ordinal: ffa380
title: On each reload, post one catalog-change notice to every live session that has the skills tool
---
## What
Requested by foundationmodelsacpagent-a5 on 2026-10-19. On each registry reload, post ONE catalog-change notice to every live session that has the `skills` tool. Use the shared FoundationModelsExtras API (e6b2bf9, Hosting/CatalogChangeNotice.swift and Hosting/CatalogNoticeBoard.swift). Do NOT add a second notice type or notice text.

1. The registry's reload side holds one `CatalogNoticeBoard()` for the skills catalog. That is the ReloadCoordinator in SkillsRegistry.swift, or the place the SkillsTool factories / `SkillsToolContext` / `SkillsReloadFollower` reach it; choose the cleanest owner. Each tool that `SkillsTool.make` makes gets that board.
2. `SkillsCatalogTool` conforms to `CatalogNoticing` (`var catalogNoticeBoard: CatalogNoticeBoard`). When a host mounts the tool through `ToolMounting.makeWrapped`, each session, root or child, joins the board one time. A session leaves when its WorkRegistry closes.
3. Follow `registry.onReload` the way `SkillsReloadFollower` does: subscribe before reading the seed, and capture no `self`. Keep the last listed catalog as `[CatalogEntry]` from `SkillsToolDescription.catalogEntries(for:isListed:)` (done in ^bq1dx6d), with `context.visibilityPredicate`. On each publication: `if let notice = CatalogChangeNotice(kind: .skills, from: last, to: new) { await board.post(notice) }`. Then keep `new` as the last catalog.
4. Do not rebuild `SkillsCatalogTool`. Do not change its `description` or `parameters` during a session: the transcripts require byte-identical tool definitions, and the cached prompt must stay. `id` is already a plain string (^wfhkw3j), so a skill that a reload adds can be loaded.

Race: a tool made from catalog v1 can miss a v2 reload that is posted before its session mounts the tool. Read the seed catalog as late as possible, and pin the behaviour with a test.

The Router's SessionOutbox does not adopt `CatalogNoticeSink` yet, so a real session drops the notice. That is Router work and outside this task.

## TDD: failing tests first
Test seam: `ToolMounting.makeWrapped(tool:site: MountSite(sessionID:runPlane: RunPlane(workRegistry: WorkRegistry(sessionID:)), sink: s), configuration: .synchronous)`. The sink `s` adopts both `OperationEventSink` and `CatalogNoticeSink`. Check `post(catalogNotice:)` and `board.sessionIDs`.
- [x] a reload that adds a visible skill posts exactly one notice; its `.text` names the skill under "New"
- [x] a reload with no listed change (a body-only edit, or a hidden skill) posts nothing
- [x] two reloads post two notices, each one diffed against the catalog before it
- [x] the tool's `description` and `parameters` are byte-identical before and after a reload
- [x] a root and a child session that both mount the tool each get the notice; a closed session gets nothing
- [x] a released follower posts nothing more

## Acceptance
- [x] Tests written first and seen failing, then passing; full `swift test` green
- [ ] After the push (the user's step), send the sha to foundationmodelsacpagent-a5 #skills #extras