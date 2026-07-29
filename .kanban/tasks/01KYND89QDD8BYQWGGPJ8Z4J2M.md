---
comments:
- actor: claude-code
  id: 01kypvck1p4tt7xtsn72wn2v14
  text: |-
    Implementation complete (TDD: red test file written first, confirmed compile failure, then implemented to green).

    Design decision on concurrency (actor vs. lock), as required by the task:

    Chose lock-protected mutable state, NOT converting SkillsRegistry to an actor. Rationale:
    - SkillsRegistry stays a `struct` with a synchronous, non-async public API (metadata(), commandListing(), preloadedBodies(), call(id:arguments:) all remain sync). Converting to `actor` would force every one of these -- including the already-committed, widely-used `call(id:arguments:)` -- to become `async`, which is a breaking behavior change to an API that other in-flight/completed tasks and existing tests already call synchronously (SkillsRegistryTests.swift has ~15 tests calling these methods synchronously). Plan.md's own diagram (§7.1) shows `call(id:arguments:)` invoked directly by CLI and other host code without implying async.
    - Instead: a private nested `final class CatalogBox: @unchecked Sendable` holds the mutable `catalog`/`diagnostics` pair behind an `NSLock`, with exactly two access points -- `snapshot` (read both atomically) and `replace(catalog:diagnostics:)` (write both atomically). Every copy of a `SkillsRegistry` value shares one `CatalogBox` instance (struct wrapping a class reference), so a rebuild triggered by one copy's watcher is instantly visible to every other copy holding the same box.
    - Watcher lifecycle: a second private nested `final class ReloadCoordinator: @unchecked Sendable` owns the `SkillWatcher` and the `onReload` `AsyncStream` continuation. Its `deinit` stops the watcher and finishes the continuation. Since `SkillsRegistry` is a struct (no deinit), the registry holds `reloadCoordinator` as a stored `let`; when the last copy of the registry goes out of scope, ARC deinits the coordinator, which is what makes "watcher lifecycle owned by the registry, stopped on deinit" a real guarantee. Verified directly with a dedicated test (`deinitStopsTheWatcherAndDeliversNoFurtherOnReloadPublicationsAfterward`).
    - The `ReloadCoordinator`'s `SkillWatcher.onChange` closure captures `layers`/`catalogBox`/`reader`/`continuation` directly (not `self`), so there is no retain cycle between the coordinator and its own watcher, and no weak-self dance needed.
    - `onReload: AsyncStream<[SkillMetadata]>?` mirrors the established `FoundationModelsExtras.SlashCommandProviding.commandUpdates: AsyncStream<[SlashCommand]>?` pattern (confirmed via explore agent survey of the Extras package) -- `nil` for `watch: false`, one full-catalog-replacement element per rebuild.
    - `metadata()` after a rebuild is computed by handing `ReloadCoordinator` a private "reader" `SkillsRegistry` view (new private init `init(catalogBox:pipeline:policy:roots:)`) that shares the same `catalogBox`/`pipeline`/`policy`. This reuses the exact same rendering path every other reader uses instead of duplicating metadata-computation logic.
    - Verified TSan-clean: `swift test --sanitize=thread --filter SkillsRegistryReloadTests` passes with zero data race reports.
    - `SkillsRegistry.diagnostics` changed from a stored `public var` to a computed property backed by `catalogBox.snapshot.diagnostics` -- necessary so it reflects the post-reload catalog. Confirmed no code anywhere assigns to `.diagnostics` externally (grepped), so this is safe.

    Files:
    - Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift -- watch: Bool on both public inits, CatalogBox, ReloadCoordinator, onReload, reader-view private init.
    - Tests/FoundationModelsSkillsTests/SkillsRegistryReloadTests.swift -- new, 7 tests: exactly-one-rebuild+onReload on edit, add propagation, remove propagation, concurrency stress (8 concurrent readers + 1 writer task, torn-catalog/duplicate-id detection), watch defaults to false, watch:false edit is a no-op, deinit stops the watcher.

    Verification: `swift build` clean, `swift test` 172/172 green (was 165 before this task), reload test file run 6+ times consecutively all green (no flakiness), `swift test --sanitize=thread` clean on the reload suite.
  timestamp: 2026-07-29T11:50:33.270853+00:00
- actor: claude-code
  id: 01kypvqbfvytr50t2bfq9n2exb
  text: |-
    Adversarial double-check (via really-done): PASS.

    Independently re-ran `swift build` (clean), `swift test` (172/172 green), and `swift test --sanitize=thread --filter SkillsRegistryReloadTests` (clean, zero TSan reports). Confirmed the lock design (CatalogBox.snapshot/replace are the only access points, no call-outs while holding the lock, no deadlock path), confirmed no retain cycle in ReloadCoordinator (its watcher closure captures layers/catalogBox/reader/continuation directly, never self), confirmed metadata()/commandListing()/preloadedBodies()/call(id:arguments:)/diagnostics all route through the same lock-protected snapshot. Confirmed the diagnostics stored-var-to-computed-property change has no external callers assigning to it anywhere in the repo. Confirmed no other package/call site in the workspace constructs SkillsRegistry directly (only the test file and plan.md reference it), and the new `watch` parameter is defaulted on both public inits, so this is fully source-compatible.

    One non-blocking observation from the reviewer: given the writer's 20ms edit cadence against the watcher's 200ms debounce in the concurrency stress test, most of the burst likely collapses into a handful of actual rebuilds rather than one-rebuild-per-edit; the real proof of the atomic-swap guarantee is the lock design plus the clean TSan run, not the stress test's assertions alone. No action needed -- this matches the acceptance criterion's own framing ("stress loop over concurrent reads + reloads"), not a claim that every single edit produces a distinct observable rebuild.

    Task remains in `doing`, ready for `/review`.
  timestamp: 2026-07-29T11:56:25.979041+00:00
- actor: claude-code
  id: 01kypwwqddwarrf522pctjezk0
  text: |-
    Fixed all three review findings.

    1. TOCTOU race in `call(id:arguments:)`: replaced the two separate reads of the private `catalog` computed property (each of which independently re-acquires `catalogBox`'s lock) with a single `let snapshot = catalogBox.snapshot` before the guard, reusing `snapshot.catalog` for both the lookup and `UnknownSkillError.validIDs`. This closes the window where a reload racing between the two old reads could produce an error whose `id`/`validIDs` came from different catalog generations. Checked every other catalog-touching call site (`sortedCatalogEntries`, `metadata()`, `commandListing()`, `preloadedBodies()`, `diagnostics`) — each already reads `catalogBox.snapshot` exactly once per invocation, so this was the only instance of the pattern.

    2. Documented `ReloadCoordinator`'s `@unchecked Sendable` invariant: added a doc comment stating both stored properties (`watcher`, `continuation`) are `let`s of inherently concurrency-safe types (`SkillWatcher` serializes its own mutable state on a private `DispatchQueue`; `AsyncStream.Continuation` is documented safe for concurrent calls), and that the coordinator itself holds no other state since the watcher's `onChange` closure captures `layers`/`catalogBox`/`reader`/`continuation` directly rather than `self`.

    3. Extracted the concurrent-reader stress test's while-loop body into a new `private static func readerTask(registry:deadline:)` in `SkillsRegistryReloadTests.swift`, called as a single statement from `addTask`, bringing the task-group closure back within the project's 3-level nesting limit while preserving the exact same assertions (no duplicate ids, `"stress-"` prefix check, `commandListing()`/`diagnostics` also exercised).

    Verification (all run fresh this session): `swift build` — exit 0, clean. `swift test` — 172/172 tests passed. `swift test --sanitize=thread --filter SkillsRegistryReloadTests` — 7/7 passed, zero TSan data-race reports. Adversarial double-check agent (via really-done) returned PASS, independently confirming all three fixes are correct, accurate, and complete, with no new races or regressions and no other missed instances of the same patterns elsewhere in the file/test suite.

    All three review-finding checkboxes and all original acceptance-criteria/test checkboxes are now checked off (progress 1.0). Task left in `doing` per /implement's process, ready for /review.
  timestamp: 2026-07-29T12:16:50.605499+00:00
depends_on:
- 01KYNCSXAEKDVR36H387H5TYXR
- 01KYNCSDX30R4T2NRXP7XRQMM2
position_column: doing
position_ordinal: '80'
title: 'SkillsRegistry reload: watcher wiring, atomic swap, onReload'
---
## What
The reloadable half of the registry (plan §7 "Reload & metadata injection"; decision #13) — split out of the static core per double-check.

- Extend `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`:
  - Add `watch: Bool` to the init; when true, wire `SkillWatcher` over every stack layer root → rebuild on its coalesced signal.
  - Rebuild swaps the catalog atomically (actor or lock) — readers never observe a half-built catalog.
  - `onReload` observation (AsyncStream or callback) publishing the refreshed `[SkillMetadata]` after each rebuild — the seam the search agent's `update(items:)` and preload refresh hang off (§7.1).
  - `preloadedBodies()`, `commandListing()`, `metadata()`, and `diagnostics` all reflect the post-reload catalog.
  - Watcher lifecycle owned by the registry: stopped on deinit; no callbacks after stop.

## Acceptance Criteria
- [x] Editing a temp-layer `SKILL.md` triggers exactly one rebuild and one `onReload` publication with refreshed metadata
- [x] Add and remove of a skill directory each propagate to `metadata()` and `commandListing()`
- [x] A reader querying during a rebuild burst never sees a partial catalog (stress loop over concurrent reads + reloads)
- [x] `watch: false` performs no watching (temp-dir edit changes nothing)

## Tests
- [x] `Tests/FoundationModelsSkillsTests/SkillsRegistryReloadTests.swift` — temp-dir add/edit/remove with expectation waits; concurrency stress case; watch-off case
- [x] `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-07-29 07:01)

- [x] `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:364` — The `UnknownSkillError` thrown by `call(id:arguments:)` can have contradictory information: the `id` field reports an unknown skill, but `validIDs` might include that same `id` if the catalog was reloaded between the two reads of `catalog`. This violates the error's contract — a caller seeing the error cannot trust whether the skill is actually invalid. Read the `catalogBox.snapshot` once before the guard statement, then reuse that snapshot for both lookups to ensure the error message is internally consistent.
- [x] `Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:468` — @unchecked Sendable requires a documented synchronization invariant — ReloadCoordinator lacks documentation explaining why concurrent access is safe. Add a doc comment explaining the Sendable invariant before the class declaration, e.g.: '@unchecked Sendable: all stored properties are immutable (declared as `let`) and refer to Sendable types, so concurrent access is safe'.
- [x] `Tests/FoundationModelsSkillsTests/SkillsRegistryReloadTests.swift:118` — While loop nested 4 levels deep (withThrowingTaskGroup → for loop → addTask closure → while) exceeds the 3-level threshold; deep nesting reduces readability of the concurrent reader task logic. Extract the reader task implementation into a separate helper method (e.g., `readerTask(registry:deadline:)`) to reduce nesting and improve readability of the concurrent test setup.
