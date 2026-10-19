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
depends_on:
- 01M5A7Z0YGYG5Y3MR7EBQ1DX6D
- 01M5A84CYKC62A5H2MMWFHKW3J
position_column: todo
position_ordinal: '8280'
title: On each reload, post one catalog-change notice to every live session that has the skills tool
---
## What
Follow `registry.onReload` in the same way that `SkillsReloadFollower` does: subscribe before reading the seed, and capture no `self`. Keep the last model-visible catalog. On each publication, build a `SkillCatalogChange` from the old and new catalogs. When it is not empty, post ONE notice with the agreed text through the FoundationModelsExtras post seam to each live session that has the `skills` tool. Then keep the new catalog as the last one.

- Use the shared notice type and the post seam from FoundationModelsExtras (session foundationmodelsextras-8f will send the API). Do NOT add a second notice type.
- Do not rebuild `SkillsCatalogTool`. Do not change its description or its `parameters` during a session: the transcripts require byte-identical tool definitions, and the cached prompt must stay.

## Blocked
Waiting on the Extras notice type and post seam (foundationmodelsextras-8f). Bump the Extras pin when it lands.

## Open design question: the `id` enum
`SkillsCatalogTool.parameters` makes `id` an enum of the skill ids that were visible when the tool was made (`SkillsToolSchema`). Under guided generation, the model cannot write an added skill's id, so a notice that announces a new skill points at one it cannot load with `use skill`. Answer this with the requester before this task is done: for example, a plain-string `id` from the start with the `UseSkill` corrective as the guard, or a notice that lists only removed and changed skills. Record the decision here.

## TDD: failing tests first
- [ ] a reload that adds a visible skill posts exactly one notice with the agreed text
- [ ] a reload with no visible change (body-only, or a hidden skill) posts nothing
- [ ] two reloads post two notices, each diffed against the catalog before it
- [ ] the tool's `description` and `parameters` are byte-identical before and after a reload
- [ ] a released follower posts nothing more

## Acceptance
- [ ] Tests written first and seen failing, then passing; full `swift test` green
- [ ] Pushed to origin/main, and the commit sent to foundationmodelsacpagent-a5 #skills #extras