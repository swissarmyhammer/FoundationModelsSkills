---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f4mbpej9y9bd3hvw23vpvb
  text: |-
    ### Note from the Multitool session (EXTRAS-11 / ^70231sy)
    - EXTRAS-11 (coded, not yet pushed): `GraphQLEndpointConformance.problems(of:scope:probe:codes: [String] = [], exceptions: [GraphQLConventionException] = [])`. When it lands, replace the "filter problems mentioning rule 9" workaround in SkillsGraphTests with `exceptions: [GraphQLConventionException(rule: .rule9, removedBy: "01M5F23EYC7GEW1B2BZHPT8953")]`, and `codes: []`. Once this task ships rule 9, drop the exception.
    - Extras task ^70231sy adds an `ID` scalar to `addToolkitScalars()`. SkillsGraph currently declares its own scalar named "ID" (as kanban does). When ^70231sy lands, remove the package's ID scalar, or the two clash on the type name. Until then `IDChange`/`ChangedIDs` render as `String!`.
  timestamp: 2026-10-21T11:48:02.382918+00:00
- actor: claude-code
  id: 01m5f4w9qnddrjryveksdmmse5
  text: |-
    ### EXTRAS-11 landed
    FoundationModelsExtras origin/main: code dbf4202, tip 02a207c. Run `swift package update FoundationModelsExtras`. Replace the test-side "rule 9" string filter in SkillsGraphTests with `GraphQLEndpointConformance.problems(of:scope:probe:codes: [], exceptions: [...])`. This task implements rule 9, so the final state needs no exception at all. Toolkit ID scalar (^70231sy) will be the opt-in `addToolkitIDScalar()`; keep the package ID scalar until that sha arrives.
  timestamp: 2026-10-21T11:52:22.517692+00:00
depends_on:
- 01M5F230NX5CY90TNJP53Y1QD6
position_column: todo
position_ordinal: '8280'
title: 'SK-5: changes(after:) subscription and cursor from the dotfolder watcher'
---
## Unblocked
EXTRAS-10 is on FoundationModelsExtras origin/main (code f126153, tip 11ffe56). Run `swift package update FoundationModelsExtras` if the resolution is older. Use the toolkit's types; do not copy a change log into this package (EXTRAS-9 rule 2).

Toolkit API (Sources/FoundationModelsExtras/GraphQL/ChangeLog.swift, IDChange.swift):
- `actor ChangeLog<Event>`: `init(capacity: Int = 1024)`, `append(_:)`, `cursor`, `changes(after:where:)` → a stream of `ChangeLogEntry<Event> { cursor: String, at: Date, event }`. `changes(after: nil)` gives only live events. A subscriber more than `capacity` events behind gets RESYNC_REQUIRED.
- `ChangedIDs` (the added/changed/removed ids; use it as the Event) and `IDChange` (the shared `<Noun>Change` shape, with `at` as DateTime).
- Codes: `GraphQLToolkitError.notFound(kind:id:)`, `.resyncRequired(reason:)`. A subscription stream that throws a coded error sends one final `{"errors":[…]}` with `extensions.code` and then ends normally.

## What
EXTRAS-9 rev 2 rule 9 for the `skills` endpoint:
- `subscription { changes(after: String): SkillChange! }` and the root query `cursor: String!`. The cursor is opaque.
- `SkillChange` uses the shared `IDChange` shape: `cursor: String!, at: DateTime!, added: [ID!]!, changed: [ID!]!, removed: [ID!]!`. One event per reload.
- Feed: `SkillsRegistry.onReload` (from `DotfolderWatcher` via the reload coordinator) gives a full `[SkillMetadata]` snapshot per reload. Diff the previous and new snapshots by id (and by content for `changed`). Append one `ChangedIDs` event when any list is non-empty. The ChangeLog is held with the endpoint: one per registry, not one per tool copy (rule 1 rev 2, task 01M5F237DGF69WGB5QSTBWVZ2F).
- A stale-epoch, too-old or future cursor gives RESYNC_REQUIRED. The alias table accepts `skillChanges`.
- SK-6 (the tool writes skills) relies on this.

## Acceptance criteria
- [ ] Adding, editing and removing a SKILL.md in a watched dotfolder produce events with the id in `added`, `changed` and `removed` respectively
- [ ] A reload that changes several skills gives one event that lists them all; a reload with no difference gives no event
- [ ] `changes(after: cursor)` sends only later events
- [ ] A stale-epoch, too-old or future cursor gives RESYNC_REQUIRED (final errors payload with `extensions.code`)
- [ ] The rule-9 conformance exception from task 01M5F230NX5CY90TNJP53Y1QD6 is removed if EXTRAS-11 has landed; otherwise keep it and note it. Golden SDL updated
- [ ] `swift build` and `swift test` green #sk-5 #graphql