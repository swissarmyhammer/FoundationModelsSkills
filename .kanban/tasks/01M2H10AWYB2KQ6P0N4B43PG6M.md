---
assignees:
- claude-code
depends_on:
- 01M2H0VAP3ASYS7ZX17BKJQ3NN
- 01M2H0VP7PA387VXKDARNERBSJ
- 01M2H0WGC194AK58EKJHWP85EW
- 01M2H0W2TM0WRKHZP8FRAJZAYY
- 01M2H0ZTENV1JH7AW6ABAXZHC5
position_column: todo
position_ordinal: '8e80'
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

- [ ] `MarketplacePolicy`, init, validation, and git `marketplaceLayers()` with grants and provenance
- [ ] The sync pipeline, with the credentials passed to the transport
- [ ] `start()`, `update(_:force:)`, `events`, `layerUpdates`, and the failure path
- [ ] The exclusive sync lock and the shared lock on `current`
- [ ] The duplicate catalog-name diagnostic

## Acceptance Criteria
- [ ] Cold start over a fixture repository: after `start()`, a `SkillsRegistry(marketplaces:stack:)` has the fixture skills, with one reload
- [ ] A second `start()` with no remote change does no fetch
- [ ] An unreachable URL publishes `.failed` with `keptVersion`, and the old skills stay
- [ ] `marketplaceLayers()` carries each source's `grants`
- [ ] The store passes `policy.credentials` to the transport
- [ ] A snapshot that one store serves survives cleanup by a second store on the same cache

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/MarketplaceStoreTests.swift` with `GitFixtureRepository` over `file://`, a temporary cache, and the real `LibGit2Transport`: cold start; no-change restart (a counting wrapper sees zero fetches); a new commit and `update()` swap `current`; an unreachable URL keeps the last good snapshot; a duplicate pre-fetch key is refused; the grants are on the layers; two stores on one cache: the served snapshot is kept
- [ ] With the counting transport double: the credentials closure reaches `fetch`; two sources with the same catalog name give a diagnostic
- [ ] Run `swift test --filter MarketplaceStoreTests`; then `swift test`; all green and hermetic

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace