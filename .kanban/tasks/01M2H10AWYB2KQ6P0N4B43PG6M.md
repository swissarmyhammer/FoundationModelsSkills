---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2k40n6z21hfb916yv1ra5pp
  text: |-
    Research and decisions of this pass.

    Six changes outside the two new files were necessary. Each one is in service of the card.

    1. `MarketplaceLocation`: a `file://` URL that ends in `.git` is now a git source; a `file://` URL that does not end in `.git` is still a local folder. The card asks for tests over `GitFixtureRepository` with `file://` and the real `LibGit2Transport`, and the parser gave every `file://` URL to the local branch. §5.1 already says that a git form ends in `.git`, thus the same suffix tells the two apart. No test changed its result.
    2. `GitFixtureRepository` now makes its bare repository at `<temporary directory>/fixture.git`, and removes the parent when it is released. This gives the `.git` suffix that rule 1 needs.
    3. `SkillDiscovery.candidateSkillDirectories` lists the root by its path and no longer by its URL. `FileManager.contentsOfDirectory(at:)` refuses a symlink with "Not a directory", thus every marketplace layer root, which is the `current` symlink, gave zero skills. This was a real fault that blocked the whole feature; four tests found it.
    4. `SnapshotLimits` is now public, because `MarketplacePolicy` carries it. It has the default values of the card: 64 mebibytes and 5,000 files.
    5. `MarketplaceCache`: `makeFolders()` is internal; `installUnderWriterLock(snapshotAt:sha:ref:)` runs the install steps for a caller that already holds the lock (`flock` is per open file, thus a second lock from the same process would wait forever); an asynchronous `withWriterLock(isolation:_:)` holds the lock over the fetch; `leaseCurrentSnapshot()` and `SnapshotLease` hold a shared lock for as long as the store serves a snapshot.
    6. `EventBroadcaster<Element>` is a new shared type in `Registry/`, backed by a `Mutex`. It replaces the private `ReloadBroadcaster` of `SkillsRegistry`, which was `@unchecked Sendable`, and the store uses it for `events` and for `layerUpdates`. One broadcaster, no duplicate.

    Two smaller decisions:

    - `MarketplaceStore.cacheDirectory(environment:)` is a public forwarder to `MarketplaceCache.cacheDirectory(environment:)`. An internal type cannot appear in the default argument of a public initializer, and the plan sketch in §6.2 names this same call.
    - `MarketplaceStateRecord` gets a `displayID` field, thus a new process shows the catalog name of the marketplace with no fetch.

    `MarketplaceEvent` holds only `.updated` and `.failed`, which are the two cases this card names. `.checked` and `.updateAvailable` belong to the update-checks card (01M2H125CCEZMT2PZAW6DRYE1R).

    A source that names a local folder gets an advisory and no layer. The `file://` card (01M2H1P68DQAVE9B0SAC5HEFA3) removes that advisory when it serves those sources.
  timestamp: 2026-09-15T18:07:09.023694+00:00
- actor: claude-code
  id: 01m2k40veeeba19s4z8ghjwj2c
  text: |-
    ### implement — changed
    - evidence: 11 files. New: Sources/FoundationModelsSkills/Marketplace/MarketplaceStore.swift, MarketplacePolicy.swift, MarketplaceEvent.swift; Sources/FoundationModelsSkills/Registry/EventBroadcaster.swift; Tests/FoundationModelsSkillsTests/MarketplaceStoreTests.swift. Changed: Marketplace/MarketplaceCache.swift, MarketplaceLocation.swift, MarketplaceState.swift, SnapshotWriter.swift; Discovery/SkillDiscovery.swift; Registry/SkillsRegistry.swift; Tests/FoundationModelsSkillsTests/MarketplaceTestSupport.swift, GitFixtureRepository.swift. `swift test --filter MarketplaceStoreTests`: 10 tests, 10 passed. `swift test`: 626 tests in 46 suites, all passed. `swift build --build-tests`: zero warnings, zero errors.
    - next: /review
  timestamp: 2026-09-15T18:07:15.406604+00:00
- actor: claude-code
  id: 01m2k661g8v7t1735k966htsyh
  text: |-
    ### review — findings
    - evidence: 4 findings — MarketplaceLocation.swift:114, MarketplaceStore.swift:57, SnapshotWriter.swift:9, SnapshotWriter.swift:13
    - scope: review sha HEAD~1..HEAD (commit 3e045e3). The engine tried 14 checks; it confirmed 5 and refuted 0.
    - note: the first attempt stopped because of a session rate limit. This is a new run.
    - next: correct the 4 findings, then do the review again. The task stays in review.
  timestamp: 2026-09-15T18:45:02.600427+00:00
- actor: claude-code
  id: 01m2k66jbwjvwsxzkfsbey90hy
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 13 files; the MarketplaceStore actor with the policy, the git layers, the sync pipeline, the events, the locks, and the credentials; plus two repairs (SkillDiscovery reads a symlinked layer root; a `file://` URL that ends in `.git` is a git source)
    - test: green — swift build --build-tests 0 warnings; swift test x3, 626 passed each run, 0 failed, 0 skipped
    - commit: 3e045e3 feat(marketplace): add the MarketplaceStore core actor
    - review: findings — 4 open: MarketplaceLocation.swift:114 (use `dropLast(while:)`), MarketplaceStore.swift:57 (`lease` is assign-only), SnapshotWriter.swift:9 and :13 (magic numbers)
    - note: the first review agent stopped at a session rate limit; the review ran again and gave this result
  timestamp: 2026-09-15T18:45:19.868055+00:00
- actor: claude-code
  id: 01m2k6kzf4qjxvpgeksv9ah6k7
  text: |-
    How this pass corrected the four findings.

    1. `MarketplaceLocation.trimmingTrailingSeparators` — the finding names `String(text.dropLast(while: { $0 == pathSeparator }))`. That method does not exist: Swift 6.4 has `dropLast(_ k: Int)` only, and the compiler refuses the call ("no exact matches in call to instance method 'dropLast'"). The standard library has `trimmingPrefix(while:)` but no suffix twin. Thus the cause of the finding, the reverse/drop/reverse pattern, is gone in the same way the finding asks: the call now asks `lastIndex(where:)` for the last character that is no separator and keeps the text up to it. It reads the text one time and makes no reversed copy. This is the only such pattern in the file.

    2. `MarketplaceStore.ServedMarketplace.lease` — the property now has a reader. `SnapshotLease` gets `releaseNow()`, which closes the folder and does nothing on a second call. `serve(atIndex:sha:displayID:catalogVersion:)` reads the lease that it replaces out of the `served` lock and releases it outside the lock. Thus the snapshot that the store leaves is free for the next cleanup at that moment, and not when the last reference goes away. `lease` is the only assign-only property of the file; every other stored property has a reader.

    3 and 4. `SnapshotLimits` — `1024 * 1024` and `64 * …` were literals inside an expression, which is what the rule refuses. The file now names `bytesInOneKibibyte`, `kibibytesInOneMebibyte`, and `defaultMaximumMebibytes`, and each product is a product of named constants. The other literals of the file (`5_000`, `0o755`, and the zeros and ones) are each a direct initializer value or a permitted number.

    Tests. `SnapshotLease.releaseNow()` is new production code, thus a failing test came first: the build refused `releaseNow` before the method existed. `MarketplaceCacheTests` gets `aLeaseHoldsItsSnapshotUntilItIsReleased` and `aSecondReleaseOfOneLeaseDoesNothing`. `MarketplaceStoreTests` gets `theStoreHoldsALeaseOnTheSnapshotItServesAndReleasesTheOneItLeaves`, which proves both halves of the lease behavior: the snapshot that the store serves refuses an exclusive lock, and the snapshot that it left takes one. The shared helper `SnapshotLockProbe.isLocked(directory:)` is in `MarketplaceTestSupport.swift`, because two suites use it.

    `flock(2)` belongs to the open file and not to the process, thus a second open in the test process sees the lock of a lease. This is the same rule that `MarketplaceCache.removeSnapshot` depends on.
  timestamp: 2026-09-15T18:52:39.268695+00:00
- actor: claude-code
  id: 01m2k6m4qfk6e50qa5jkqtxae0
  text: |-
    ### implement — changed
    - evidence: 5 files. Sources/FoundationModelsSkills/Marketplace/MarketplaceLocation.swift, MarketplaceStore.swift, MarketplaceCache.swift, SnapshotWriter.swift; Tests/FoundationModelsSkillsTests/MarketplaceCacheTests.swift, MarketplaceStoreTests.swift, MarketplaceTestSupport.swift (7 files in all). `swift build --build-tests`: 0 warnings, 0 errors. `swift test --filter 'MarketplaceCacheTests|MarketplaceStoreTests|MarketplaceSourceTests|SnapshotWriterTests'`: 80 tests in 4 suites, all passed. `swift test`: 629 tests in 46 suites, all passed, 0 failed, 0 skipped.
    - next: /review
  timestamp: 2026-09-15T18:52:44.655927+00:00
depends_on:
- 01M2H0VAP3ASYS7ZX17BKJQ3NN
- 01M2H0VP7PA387VXKDARNERBSJ
- 01M2H0WGC194AK58EKJHWP85EW
- 01M2H0W2TM0WRKHZP8FRAJZAYY
- 01M2H0ZTENV1JH7AW6ABAXZHC5
position_column: doing
position_ordinal: '80'
title: 'Add the MarketplaceStore core: policy, git layers, sync, events, locks, credentials'
---
## What

marketplace.md §6.1, §6.2, §7.3, §7.6. The actor that joins the parts, for git sources. Later tasks add update checks, pins, `file://` and seed sources, and the allowlist. This task makes `start()` bring every git marketplace to its current head one time.

- `Sources/FoundationModelsSkills/Marketplace/MarketplacePolicy.swift` — **this task defines** `public struct MarketplacePolicy: Sendable` with `snapshotLimits: SnapshotLimits` (default `maxBytes` 64 MiB, `maxFiles` 5,000; these are sizes, not times) and `credentials: (@Sendable (URL) async -> MarketplaceCredential?)?` (default `nil`). Later tasks add fields to this type.
- `Sources/FoundationModelsSkills/Marketplace/MarketplaceStore.swift` — `public actor MarketplaceStore: MarketplaceLayerProviding`:
  - `init(sources:cacheDirectory:policy:)` with `cacheDirectory` default `MarketplaceCache.cacheDirectory(environment: ProcessInfo.processInfo.environment)`, plus an internal init that takes a `GitTransport`. It runs `MarketplaceIdentity.validate` on the pre-fetch keys and refuses a list with a duplicate key.
  - `nonisolated func marketplaceLayers() -> [MarketplaceLayer]` for git sources: `<cache>/<cacheFolderName>/current`, in list order, with no network I/O. Each layer carries the source's `grants` and its current `MarketplaceProvenance`.
  - The sync for one source: `remoteHead` (or the pinned `sha`) → if it differs from `currentSha` (or `force`): `fetch` (passing `policy.credentials`) → `GitTreeFileSource` → `CatalogResolver` → `SnapshotWriter` into `snapshots/<sha>.tmp` → `MarketplaceCache.install` → `state.json` → `.updated` on `events` and a value on `layerUpdates`.
  - Locks: hold the cache's exclusive `lock` for the whole sync of one marketplace. Hold a shared lock on the snapshot that `current` names while the store serves it, so cleanup in another process keeps that snapshot.
  - After a fetch, the catalog `name` is the display id. When two sources give the same catalog name, record a diagnostic.
  - `func start() async` and `func update(_ id: String? = nil, force: Bool = false) async -> [MarketplaceEvent]`. Any failure publishes `.failed(id:error:keptVersion:)` and keeps `current`.
  - `nonisolated var events: AsyncStream<MarketplaceEvent>` and `nonisolated var diagnostics: [MarketplaceDiagnostic]`.

- [x] `MarketplacePolicy`, init, validation, and git `marketplaceLayers()` with grants and provenance
- [x] The sync pipeline, with the credentials passed to the transport
- [x] `start()`, `update(_:force:)`, `events`, `layerUpdates`, and the failure path
- [x] The exclusive sync lock and the shared lock on `current`
- [x] The duplicate catalog-name diagnostic

## Acceptance Criteria
- [x] Cold start over a fixture repository: after `start()`, a `SkillsRegistry(marketplaces:stack:)` has the fixture skills, with one reload
- [x] A second `start()` with no remote change does no fetch
- [x] An unreachable URL publishes `.failed` with `keptVersion`, and the old skills stay
- [x] `marketplaceLayers()` carries each source's `grants`
- [x] The store passes `policy.credentials` to the transport
- [x] A snapshot that one store serves survives cleanup by a second store on the same cache

## Tests
- [x] `Tests/FoundationModelsSkillsTests/MarketplaceStoreTests.swift` with `GitFixtureRepository` over `file://`, a temporary cache, and the real `LibGit2Transport`: cold start; no-change restart (a counting wrapper sees zero fetches); a new commit and `update()` swap `current`; an unreachable URL keeps the last good snapshot; a duplicate pre-fetch key is refused; the grants are on the layers; two stores on one cache: the served snapshot is kept
- [x] With the counting transport double: the credentials closure reaches `fetch`; two sources with the same catalog name give a diagnostic
- [x] Run `swift test --filter MarketplaceStoreTests`; then `swift test`; all green and hermetic

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace

## Review Findings (2026-09-15 13:38)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 13 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsSkills/Marketplace/MarketplaceLocation.swift:114` `reuse/reuse` — Custom trailing-separator removal reimplements the standard library's `dropLast(while:)` method. The reverse/drop/reverse pattern is less efficient and less readable than the built-in capability. Replace with `String(text.dropLast(while: { $0 == pathSeparator }))`.
- [x] `Sources/FoundationModelsSkills/Marketplace/MarketplaceStore.swift:57` `code-hygiene/dead-code-swift` — var.instance `lease` is assignOnlyProperty.
- [x] `Sources/FoundationModelsSkills/Marketplace/SnapshotWriter.swift:9` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Sources/FoundationModelsSkills/Marketplace/SnapshotWriter.swift:13` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
