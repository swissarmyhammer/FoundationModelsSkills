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
- actor: claude-code
  id: 01m5f5ftmvsvgmajbq03cz6g02
  text: |-
    ### Research (implement)
    - `swift package update FoundationModelsExtras` → resolved at 02a207c (ChangeLog/IDChange/ChangedIDs + `problems(...codes:exceptions:)` present).
    - Rule 9 checks `added/changed/removed: [ID!]!`. Toolkit `IDChange.added` is `[String]` (renders `[String!]!`), so the `SkillChange` type maps `IDChange` with package-side computed properties that give `[SkillID]` (the package `ID` scalar), keeping the shared shape and the toolkit type.
    - `onReload` gives only enabled metadata; the diff reads the registry through `detachedReader` (no coordinator ref) and compares per-id content = `SkillRecord` (incl. disabled, `isEnabled`) + frontmatter + body, so a body-only or `enabled:` edit is `changed`.
    - Lifetime: feed task captures the `onReload` stream, the `detachedReader` and the `ChangeLog` actor — never the graph — so no cycle; the graph owns the feed and cancels the task in deinit. Subscribe to `onReload` before reading the seed snapshot (same rule as SkillsReloadFollower).
    - Deterministic multi-skill / no-op reloads in tests: a registry over `FakeMarketplaceProvider` with `watch: false` rebuilds exactly once per `publish(layers:)`, so N file edits become one reload. Add/edit/remove use a `watch: true` registry.
    - Too-old cursor needs a small log: SkillsGraph gets an internal `changeLogCapacity` init parameter (default = toolkit default 1024).
  timestamp: 2026-10-21T12:03:02.427504+00:00
- actor: claude-code
  id: 01m5f5v2fbe12j24hwwr82jkky
  text: |-
    ### Implementation landed
    - Coordinator update applied: FoundationModelsExtras re-resolved at 9c47e10 (ToolkitID 44c2f54). The package `SkillID` scalar is DELETED; the schema calls `addToolkitIDScalar()` and `Skill.id` / `skill(id:)` use `ToolkitID`. `SkillChange` maps the toolkit `IDChange` directly (`[ToolkitID]` → `[ID!]!`). SDL type stays `ID`, so the golden diff is additive only: `SkillChange`, `Query.cursor`, `type Subscription { changes(after: String): SkillChange! }`. (Package.resolved is gitignored, so the pin bump is local only.)
    - New `SkillChangeFeed` (GraphQL/SkillChangeFeed.swift): subscribes to `onReload` before reading the seed, diffs `detachedReader.skillContents()` per reload, appends one `ChangedIDs` only when something differs. Task captures stream + detachedReader + ChangeLog actor only; SkillsGraph owns the feed and its deinit cancels the task. Test `theEndpointOfAReloadingRegistryIsReleased` proves no retain cycle.
    - New internal `SkillsRegistry.skillContents()` + `SkillContent` (record incl. disabled + frontmatter + body), so body-only and `enabled:` edits are `changed`.
    - `SkillsGraph.init(registry:)` stays public (now a convenience init); internal `init(registry:changeLog:)` lets tests pass `ChangeLog(capacity: 1)` for the too-old cursor case. Alias `Subscription.changes` ← `skillChanges`.
    - Conformance test now calls `problems(of:scope:probe:codes: [], exceptions: [])` and expects empty — the rule-9 string filter is gone and no exception remains.
    - Tests: new SkillsGraphChangesTests (16 tests). Multi-skill and no-op reloads use a non-watching registry over `FakeMarketplaceProvider` (one `publish` = exactly one rebuild), avoiding the watcher's debounce splitting a burst under load. Add/edit/remove/turn-off use a `watch: true` registry.
    - Note: `swift build` prints `warning: missing creator for mutated node: ('.build/out/Products/Debug/mlx-swift_Cmlx.bundle/Contents/MacOS')` — a SwiftPM build-system note about the mlx-swift dependency bundle, not from any source file in this package.
  timestamp: 2026-10-21T12:09:10.891803+00:00
- actor: claude-code
  id: 01m5f5v5q1sjkkw9gxrar82dj5
  text: |-
    ### implement — changed
    - evidence: `swift test` 690 tests in 63 suites passed, 0 failures; compiler warnings 0 (one SwiftPM build-system note on the mlx-swift_Cmlx dependency bundle). 8 files — Sources/FoundationModelsSkills/GraphQL/SkillsGraph.swift, Sources/FoundationModelsSkills/GraphQL/SkillsGraphSchema.swift, Sources/FoundationModelsSkills/GraphQL/SkillChangeFeed.swift (new), Sources/FoundationModelsSkills/Registry/SkillContent.swift (new), Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Tests/Fixtures/skills.graphql, Tests/FoundationModelsSkillsTests/SkillsGraphTests.swift, Tests/FoundationModelsSkillsTests/SkillsGraphChangesTests.swift (new)
    - next: /review
  timestamp: 2026-10-21T12:09:14.209108+00:00
- actor: claude-code
  id: 01m5f5ymn2vh5nhbpt8qgc4pb5
  text: |-
    ### test — green
    - evidence: swift build clean; swift test — 690 tests in 63 suites passed, 0 failed, 0 skipped; only warning is the known out-of-scope mlx-swift Cmlx "missing creator for mutated node". swift test --filter SkillsGraphChangesTests — 15 tests passed (twice in total: once inside the full run at 1.58s, once filtered at 1.06s), no timing flake observed. Not looped, per the one-measurement rule.
    - next: review/commit
  timestamp: 2026-10-21T12:11:07.810357+00:00
- actor: claude-code
  id: 01m5f65zh4k1t71w6te599n1n9
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (9711ce2) — 0 findings (7 files attempted, 0 confirmed, 1 refuted, 0 failed)
    - next: none; task moved to done
  timestamp: 2026-10-21T12:15:08.324634+00:00
- actor: claude-code
  id: 01m5f667ej4ba71hz460482c7n
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 8 files
    - test: green — swift test, 690 passed in 63 suites
    - commit: 9711ce2
    - review: clean — 0 findings
  timestamp: 2026-10-21T12:15:16.434092+00:00
depends_on:
- 01M5F230NX5CY90TNJP53Y1QD6
position_column: done
position_ordinal: ffa780
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
- [x] Adding, editing and removing a SKILL.md in a watched dotfolder produce events with the id in `added`, `changed` and `removed` respectively
- [x] A reload that changes several skills gives one event that lists them all; a reload with no difference gives no event
- [x] `changes(after: cursor)` sends only later events
- [x] A stale-epoch, too-old or future cursor gives RESYNC_REQUIRED (final errors payload with `extensions.code`)
- [x] The rule-9 conformance exception from task 01M5F230NX5CY90TNJP53Y1QD6 is removed if EXTRAS-11 has landed; otherwise keep it and note it. Golden SDL updated
- [x] `swift build` and `swift test` green #sk-5 #graphql