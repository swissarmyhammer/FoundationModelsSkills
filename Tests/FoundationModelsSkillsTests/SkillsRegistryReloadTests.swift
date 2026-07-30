import Foundation
import FoundationModelsSkills
import Testing

/// Tests for `SkillsRegistry`'s reloadable half (plan.md §7 "Reload &
/// metadata injection"; decision #13): `watch: true` wires a `SkillWatcher`
/// over every layer root and rebuilds the catalog on its coalesced signal,
/// the rebuild swaps the catalog atomically so a concurrent reader never
/// observes a half-built catalog, `onReload` publishes the refreshed
/// `[SkillMetadata]` exactly once per rebuild, `watch: false` performs no
/// watching at all, and the watcher's lifecycle is owned by the registry --
/// stopped once the registry (and every copy of it) is deinitialized.
///
/// The count-only event tally, generic polling, "exactly one event" wait,
/// and `SKILL.md` fixture-writing helpers all live in shared
/// `ReloadTestSupport`, not reimplemented here -- `HotReloadTests` waits on
/// the identical reload signal shape (review findings, 2026-07-29 21:57).
struct SkillsRegistryReloadTests {
    /// How long a test waits for an expected `onReload` publication to
    /// arrive before treating its absence as a failure. Generous relative to
    /// `SkillWatcher`'s default 200ms debounce interval to absorb scheduler
    /// and filesystem-event jitter in a sandboxed test environment (mirrors
    /// `SkillWatcherTests.expectedSignalTimeout`).
    private static let expectedSignalTimeout: Duration = .seconds(10)

    /// How long a test waits, after an expected publication already
    /// arrived, to confirm no *second* publication follows it (mirrors
    /// `SkillWatcherTests.noFurtherSignalWindow`).
    private static let noFurtherSignalWindow: Duration = .seconds(1)

    // MARK: - Editing triggers exactly one rebuild and one onReload publication

    @Test func editingASkillFileTriggersExactlyOneRebuildAndOneOnReloadPublicationWithRefreshedMetadata()
        async throws
    {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "editable-skill", in: root, descriptionSuffix: "before edit")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let recorder = MetadataUpdateRecorder()
        let subscription = Self.subscribe(registry, to: recorder)
        defer { subscription.cancel() }

        try ReloadTestSupport.writeSkillFile(id: "editable-skill", in: root, descriptionSuffix: "after edit")
        await Self.expectExactlyOnePublication(recorder, since: 0)

        let latest = try #require(await recorder.publications.last)
        let entry = try #require(latest.first { $0.id == "editable-skill" })
        #expect(entry.description.contains("after edit"))
        #expect(!entry.description.contains("before edit"))
    }

    // MARK: - Reload refreshes preloadedBodies() and diagnostics

    /// Closes a coverage gap distinct from every other test in this file:
    /// none of them ever asserts on `preloadedBodies()` or `diagnostics`
    /// after a reload, only on `metadata()`/`commandListing()`/`call(id:
    /// arguments:)`. Drives a `preload: true` skill through an edit (content
    /// change) and confirms `preloadedBodies()` tracks it, then introduces an
    /// unrelated broken sibling (missing `description:`) and confirms
    /// `diagnostics` reflects the new generation -- without disturbing the
    /// still-valid preloaded skill -- then removes the preloaded skill and
    /// confirms its body is gone.
    @Test func reloadRefreshesPreloadedBodiesAndDiagnostics() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(
            id: "preload-skill", in: root, extraFrontmatter: "preload: true\n", body: "Preload body v1.")

        let registry = SkillsRegistry(roots: [root], watch: true)
        #expect(registry.preloadedBodies().contains("Preload body v1."))
        #expect(registry.diagnostics.isEmpty)

        let recorder = MetadataUpdateRecorder()
        let subscription = Self.subscribe(registry, to: recorder)
        defer { subscription.cancel() }

        // Edit: preloadedBodies() picks up the new content, not the old.
        try ReloadTestSupport.writeSkillFile(
            id: "preload-skill", in: root, extraFrontmatter: "preload: true\n", body: "Preload body v2.")
        await Self.expectExactlyOnePublication(recorder, since: 0)
        #expect(registry.preloadedBodies().contains("Preload body v2."))
        #expect(!registry.preloadedBodies().contains("Preload body v1."))
        #expect(registry.diagnostics.isEmpty, "a well-formed preloaded skill's reload must raise no diagnostics")

        // Introduce a broken sibling (no `description:`) alongside the
        // preloaded skill: diagnostics must reflect the new generation, and
        // the unrelated preloaded skill's own body must be untouched.
        try Self.writeSkillFileMissingDescription(id: "broken-skill", in: root)
        await Self.expectExactlyOnePublication(recorder, since: 1)
        #expect(registry.diagnostics.contains { $0.skillID == "broken-skill" })
        #expect(
            registry.preloadedBodies().contains("Preload body v2."),
            "an unrelated broken sibling must not disturb the preloaded skill's own body")

        // Remove: preloadedBodies() drops it entirely.
        try FileManager.default.removeItem(at: root.appendingPathComponent("preload-skill", isDirectory: true))
        await Self.expectExactlyOnePublication(recorder, since: 2)
        #expect(!registry.preloadedBodies().contains("Preload body"))
    }

    /// Distinct from `reloadRefreshesPreloadedBodiesAndDiagnostics`'s broken
    /// sibling (missing `description:`, a `.warning`): this one's YAML is
    /// genuinely unparseable, the `.skip` severity path
    /// (`DiagnosticsRenderingTests.skipDiagnosticForUnparseableYAMLStillCarriesProvenance`
    /// pins the same fixture shape at construction time) -- proving the
    /// skip diagnostic surfaces post-reload too, not just at construction.
    @Test func reloadIntroducingAGenuinelyMalformedYAMLSkillSurfacesASkipDiagnostic() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "well-formed-skill", in: root)

        let registry = SkillsRegistry(roots: [root], watch: true)
        #expect(registry.diagnostics.isEmpty)

        let recorder = MetadataUpdateRecorder()
        let subscription = Self.subscribe(registry, to: recorder)
        defer { subscription.cancel() }

        try Self.writeSkillFileWithUnparseableYAML(id: "malformed-skill", in: root)
        await Self.expectExactlyOnePublication(recorder, since: 0)

        let skipDiagnostic = try #require(registry.diagnostics.first { $0.skillID == "malformed-skill" })
        #expect(skipDiagnostic.severity == .skip)
        #expect(registry.metadata().contains { $0.id == "well-formed-skill" })
        #expect(!registry.metadata().contains { $0.id == "malformed-skill" })
    }

    // MARK: - call(id:arguments:) reflects the post-reload catalog (TOCTOU regression)

    /// Coverage motivated by the round-1 TOCTOU fix in `call(id:arguments:)`
    /// (plan.md §7, review findings 2026-07-29 07:01): the earlier
    /// implementation read the catalog once to look up `id` and again to
    /// build `UnknownSkillError.validIDs`, so a reload racing between those
    /// two reads could observe two different catalog generations. That fix
    /// itself is a lock-design property, not something a single-threaded
    /// test can reproduce (nothing races *during* the `call()` below --
    /// `onReload` only publishes once `catalogBox.replace(...)` has already
    /// completed, so the catalog is settled by the time this test reads
    /// it). What this test *does* prove, and what was previously
    /// unverified end-to-end: after a completed reload, `call(id:
    /// arguments:)` reflects the new catalog generation -- it returns the
    /// *new* body, not a stale one cached from before the rebuild. The
    /// concurrency stress test below,
    /// `concurrentReadersNeverObserveAPartialCatalogDuringARebuildBurst()`,
    /// is what exercises reads racing an in-flight rebuild.
    @Test func callAfterAReloadReturnsTheNewBodyNotTheStaleOne() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "callable-skill", in: root, body: "v1")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let recorder = MetadataUpdateRecorder()
        let subscription = Self.subscribe(registry, to: recorder)
        defer { subscription.cancel() }

        try ReloadTestSupport.writeSkillFile(id: "callable-skill", in: root, body: "v2")
        await Self.expectExactlyOnePublication(recorder, since: 0)

        let body = try registry.call(id: "callable-skill")
        #expect(body.contains("v2"))
        #expect(!body.contains("v1"))
    }

    // MARK: - Add / remove propagate to metadata() and commandListing()

    @Test func addingASkillDirectoryPropagatesToMetadataAndCommandListing() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "existing-skill", in: root, descriptionSuffix: "v1")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let recorder = MetadataUpdateRecorder()
        let subscription = Self.subscribe(registry, to: recorder)
        defer { subscription.cancel() }

        try ReloadTestSupport.writeSkillFile(id: "new-skill", in: root, descriptionSuffix: "v1")
        await Self.expectExactlyOnePublication(recorder, since: 0)

        #expect(Set(registry.metadata().map(\.id)) == ["existing-skill", "new-skill"])
        #expect(Set(registry.commandListing().map(\.id)) == ["existing-skill", "new-skill"])
    }

    @Test func removingASkillDirectoryPropagatesToMetadataAndCommandListing() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "surviving-skill", in: root, descriptionSuffix: "v1")
        try ReloadTestSupport.writeSkillFile(id: "doomed-skill", in: root, descriptionSuffix: "v1")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let recorder = MetadataUpdateRecorder()
        let subscription = Self.subscribe(registry, to: recorder)
        defer { subscription.cancel() }

        try FileManager.default.removeItem(at: root.appendingPathComponent("doomed-skill", isDirectory: true))
        await Self.expectExactlyOnePublication(recorder, since: 0)

        #expect(Set(registry.metadata().map(\.id)) == ["surviving-skill"])
        #expect(Set(registry.commandListing().map(\.id)) == ["surviving-skill"])
    }

    // MARK: - Concurrent readers never observe a partial catalog

    @Test func concurrentReadersNeverObserveAPartialCatalogDuringARebuildBurst() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let knownIDs = (0..<5).map { "stress-\($0)" }
        for id in knownIDs {
            try ReloadTestSupport.writeSkillFile(id: id, in: root, descriptionSuffix: "v1")
        }

        let registry = SkillsRegistry(roots: [root], watch: true)
        let readerDeadline = ContinuousClock.now.advanced(by: .milliseconds(600))

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    Self.readerTask(registry: registry, deadline: readerDeadline)
                }
            }
            group.addTask {
                for iteration in 0..<15 {
                    let mutatedID = knownIDs[iteration % knownIDs.count]
                    try ReloadTestSupport.writeSkillFile(id: mutatedID, in: root, descriptionSuffix: "rev\(iteration)")
                    try await Task.sleep(for: .milliseconds(20))
                }
            }
            try await group.waitForAll()
        }
    }

    /// Repeatedly reads `registry`'s catalog until `deadline`, asserting
    /// that every read observes a complete, self-consistent catalog
    /// generation -- never a torn one straddling a concurrent rebuild.
    ///
    /// Extracted out of `concurrentReadersNeverObserveAPartialCatalogDuringARebuildBurst()`'s
    /// `addTask` closure so that closure's body is a single call rather than
    /// a nested `while` loop, keeping the test within this project's
    /// 3-level nesting limit.
    ///
    /// - Parameters:
    ///   - registry: The registry to read from.
    ///   - deadline: When to stop reading.
    private static func readerTask(registry: SkillsRegistry, deadline: ContinuousClock.Instant) {
        while ContinuousClock.now < deadline {
            let ids = registry.metadata().map(\.id)
            #expect(Set(ids).count == ids.count, "duplicate ids indicate a torn catalog read")
            #expect(ids.allSatisfy { $0.hasPrefix("stress-") })
            _ = registry.commandListing()
            _ = registry.diagnostics
        }
    }

    // MARK: - watch: false performs no watching

    @Test func watchDefaultsToFalseWhenOmitted() throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "static-skill", in: root, descriptionSuffix: "v1")

        let registry = SkillsRegistry(roots: [root])
        #expect(registry.onReload == nil)
    }

    @Test func watchFalseEditingATempFileChangesNothing() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "static-skill", in: root, descriptionSuffix: "before edit")

        let registry = SkillsRegistry(roots: [root], watch: false)
        #expect(registry.onReload == nil)

        try ReloadTestSupport.writeSkillFile(id: "static-skill", in: root, descriptionSuffix: "after edit")
        // Gives an incorrectly-wired watcher a chance to fire before asserting nothing changed.
        try await Task.sleep(for: Self.noFurtherSignalWindow)

        let entry = try #require(registry.metadata().first { $0.id == "static-skill" })
        #expect(entry.description.contains("before edit"))
        #expect(!entry.description.contains("after edit"))
    }

    // MARK: - Late root creation (^80kravf): end-to-end through the registry

    @Test func aRootThatDidNotExistAtConstructionSurfacesItsSkillOnceCreated() async throws {
        let privateDirectory = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory) }
        let lateRoot = privateDirectory.appendingPathComponent("skills-arrive-later", isDirectory: true)

        let registry = SkillsRegistry(roots: [lateRoot], watch: true)
        #expect(registry.metadata().isEmpty)
        let recorder = MetadataUpdateRecorder()
        let subscription = Self.subscribe(registry, to: recorder)
        defer { subscription.cancel() }

        try ReloadTestSupport.writeSkillFile(id: "late-arrival", in: lateRoot, descriptionSuffix: "v1")
        await Self.expectExactlyOnePublication(recorder, since: 0)

        #expect(registry.metadata().map(\.id) == ["late-arrival"])
    }

    // MARK: - Multi-consumer fan-out (^321b23t): no shared-stream tick stealing

    @Test func twoConcurrentConsumersBothObserveEveryReloadInAFiveReloadBurst() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "burst-skill", in: root, descriptionSuffix: "v0")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let onReloadTally = ReloadTestSupport.EventTally()
        let onReloadSubscription = Task {
            guard let stream = registry.onReload else { return }
            for await _ in stream { await onReloadTally.record() }
        }
        defer { onReloadSubscription.cancel() }

        let commandUpdatesTally = ReloadTestSupport.EventTally()
        let commandUpdatesSubscription = Task {
            guard let stream = registry.commandUpdates else { return }
            for await _ in stream { await commandUpdatesTally.record() }
        }
        defer { commandUpdatesSubscription.cancel() }

        for iteration in 1...5 {
            try ReloadTestSupport.writeSkillFile(id: "burst-skill", in: root, descriptionSuffix: "v\(iteration)")
            await Self.expectCount(onReloadTally, atLeast: iteration, timeout: Self.expectedSignalTimeout)
        }
        // A settling window so a coalesced extra tick (there shouldn't be
        // one) would still show up before the final tally read.
        try await Task.sleep(for: Self.noFurtherSignalWindow)

        let onReloadCount = await onReloadTally.count
        let commandUpdatesCount = await commandUpdatesTally.count
        #expect(onReloadCount == 5, "onReload observed \(onReloadCount) of 5 reloads")
        #expect(commandUpdatesCount == 5, "commandUpdates observed \(commandUpdatesCount) of 5 reloads")
    }

    @Test func aLateCommandUpdatesSubscriberReceivesSubsequentTicks() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "late-subscriber-skill", in: root, descriptionSuffix: "v0")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let earlyTally = ReloadTestSupport.EventTally()
        let earlySubscription = Task {
            guard let stream = registry.commandUpdates else { return }
            for await _ in stream { await earlyTally.record() }
        }
        defer { earlySubscription.cancel() }

        try ReloadTestSupport.writeSkillFile(id: "late-subscriber-skill", in: root, descriptionSuffix: "v1")
        await Self.expectCount(earlyTally, atLeast: 1, timeout: Self.expectedSignalTimeout)

        // A fresh subscription, registered only now -- after the first
        // reload already happened -- must still observe every reload from
        // this point forward, independent of `earlySubscription`.
        let lateTally = ReloadTestSupport.EventTally()
        let lateSubscription = Task {
            guard let stream = registry.commandUpdates else { return }
            for await _ in stream { await lateTally.record() }
        }
        defer { lateSubscription.cancel() }

        try ReloadTestSupport.writeSkillFile(id: "late-subscriber-skill", in: root, descriptionSuffix: "v2")
        await Self.expectCount(lateTally, atLeast: 1, timeout: Self.expectedSignalTimeout)
        await Self.expectCount(earlyTally, atLeast: 2, timeout: Self.expectedSignalTimeout)

        let lateCount = await lateTally.count
        #expect(lateCount == 1)
    }

    @Test func everySubscriberFinishesCleanlyOnRegistryDeinitNoLeakedContinuations() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "deinit-fanout-skill", in: root, descriptionSuffix: "v0")

        var registry: SkillsRegistry? = SkillsRegistry(roots: [root], watch: true)
        let onReloadStream = try #require(registry?.onReload)
        let commandUpdatesStream = try #require(registry?.commandUpdates)
        registry = nil

        let onReloadFinished = FinishTracker()
        let onReloadSubscription = Task {
            for await _ in onReloadStream {}
            await onReloadFinished.markFinished()
        }
        defer { onReloadSubscription.cancel() }

        let commandUpdatesFinished = FinishTracker()
        let commandUpdatesSubscription = Task {
            for await _ in commandUpdatesStream {}
            await commandUpdatesFinished.markFinished()
        }
        defer { commandUpdatesSubscription.cancel() }

        await Self.expectFinishes(onReloadFinished, timeout: Self.expectedSignalTimeout)
        await Self.expectFinishes(commandUpdatesFinished, timeout: Self.expectedSignalTimeout)
    }

    // MARK: - Watcher lifecycle owned by the registry

    @Test func deinitStopsTheWatcherAndDeliversNoFurtherOnReloadPublicationsAfterward() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "short-lived-skill", in: root, descriptionSuffix: "v1")

        var registry: SkillsRegistry? = SkillsRegistry(roots: [root], watch: true)
        let stream = try #require(registry?.onReload)
        registry = nil

        let recorder = MetadataUpdateRecorder()
        let subscription = Task {
            for await metadata in stream { await recorder.record(metadata) }
        }
        defer { subscription.cancel() }

        try ReloadTestSupport.writeSkillFile(id: "short-lived-skill", in: root, descriptionSuffix: "v2")
        try await Task.sleep(for: Self.noFurtherSignalWindow)

        #expect(await recorder.publications.isEmpty)
    }

    // MARK: - Multi-consumer fan-out test helpers

    /// Polls `tally`'s count until it reaches `target` or `timeout` elapses,
    /// then asserts it reached `target`.
    ///
    /// - Parameters:
    ///   - tally: The tally to poll.
    ///   - target: The count to wait for.
    ///   - timeout: How long to keep polling before giving up.
    private static func expectCount(_ tally: ReloadTestSupport.EventTally, atLeast target: Int, timeout: Duration)
        async
    {
        let current = await ReloadTestSupport.poll({ await tally.count }, until: { $0 >= target }, timeout: timeout)
        #expect(current >= target, "expected at least \(target) events, observed \(current)")
    }

    /// Marks whether a subscription's `for await` loop has exited -- proof
    /// its stream finished (rather than merely going quiet), for the
    /// deinit/no-leaked-continuations tests.
    private actor FinishTracker {
        private(set) var isFinished = false

        /// Marks this tracker finished.
        func markFinished() {
            isFinished = true
        }
    }

    /// Polls `tracker` until it's marked finished or `timeout` elapses, then
    /// asserts it finished.
    ///
    /// - Parameters:
    ///   - tracker: The tracker to poll.
    ///   - timeout: How long to keep polling before giving up.
    private static func expectFinishes(_ tracker: FinishTracker, timeout: Duration) async {
        let finished = await ReloadTestSupport.poll({ await tracker.isFinished }, until: { $0 }, timeout: timeout)
        #expect(finished, "subscriber stream did not finish within \(timeout)")
    }

    // MARK: - Test helpers

    /// Tallies every `[SkillMetadata]` list `SkillsRegistry.onReload` publishes
    /// during a test.
    ///
    /// An actor rather than relying on the `AsyncStream` itself for
    /// assertions, mirroring `SkillWatcherTests.SignalRecorder`: polling this
    /// recorder's state sidesteps an `AsyncStream` iterator's single-consumer
    /// limitation entirely. Carries its own metadata payload (unlike
    /// `ReloadTestSupport.EventTally`, which is count-only), so it is not
    /// itself a candidate for that shared type.
    private actor MetadataUpdateRecorder {
        private(set) var publications: [[SkillMetadata]] = []

        /// Appends `metadata` as the next observed publication.
        ///
        /// - Parameter metadata: The published metadata list to record.
        func record(_ metadata: [SkillMetadata]) {
            publications.append(metadata)
        }
    }

    /// Starts a background task that iterates `registry.onReload` (when
    /// non-`nil`) and records every published metadata list into `recorder`.
    ///
    /// - Parameters:
    ///   - registry: The registry whose `onReload` stream to subscribe to.
    ///   - recorder: The recorder to feed.
    /// - Returns: The subscription task; the caller cancels it once done
    ///   observing.
    private static func subscribe(
        _ registry: SkillsRegistry, to recorder: MetadataUpdateRecorder
    ) -> Task<Void, Never> {
        Task {
            guard let stream = registry.onReload else { return }
            for await metadata in stream {
                await recorder.record(metadata)
            }
        }
    }

    /// Asserts that exactly one new publication lands on `recorder` after
    /// `baseline`: the count reaches `baseline + 1` within
    /// `expectedSignalTimeout`, and stays there through
    /// `noFurtherSignalWindow`.
    ///
    /// Mirrors `SkillWatcherTests.expectExactlyOneSignal(_:since:)`.
    ///
    /// - Parameters:
    ///   - recorder: The recorder to assert against.
    ///   - baseline: The publication count observed before the action under
    ///     test.
    /// - Returns: The settled count, for chaining a further action's
    ///   `baseline` in the same test.
    @discardableResult
    private static func expectExactlyOnePublication(_ recorder: MetadataUpdateRecorder, since baseline: Int)
        async -> Int
    {
        await ReloadTestSupport.expectExactlyOneEvent(
            countGetter: { await recorder.publications.count }, since: baseline,
            signalTimeout: Self.expectedSignalTimeout, settleWindow: Self.noFurtherSignalWindow)
    }

    /// Writes `id/SKILL.md` directly under `directory` with no `description:`
    /// at all, creating the skill's own subdirectory first if it does not
    /// already exist -- `SkillValidator`'s `missingDescriptionDiagnostic`
    /// rule draws a `.warning` diagnostic for this (excluded from the
    /// model-facing surface, kept user-invocable and still loaded), a cheap,
    /// deliberate way to raise a diagnostic without hiding the skill
    /// entirely. Not folded into `ReloadTestSupport.writeSkillFile`, whose
    /// `skillFileContents` always emits a `description:` line -- this
    /// fixture's entire point is to omit it.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and the
    ///     frontmatter's `name:` field.
    ///   - directory: The root to write under.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    private static func writeSkillFileMissingDescription(id: String, in directory: URL) throws {
        try Self.writeSkillFileWithRawContents("---\nname: \(id)\n---\nBody text for \(id).\n", id: id, in: directory)
    }

    /// Writes `id/SKILL.md` directly under `directory` with genuinely
    /// unparseable YAML frontmatter (an unterminated flow sequence), the
    /// same shape
    /// `DiagnosticsRenderingTests.skipDiagnosticForUnparseableYAMLStillCarriesProvenance`
    /// pins at construction time -- `SkillValidator`'s `.skipped` outcome
    /// draws a `.skip` diagnostic and the skill is excluded from the
    /// catalog entirely, unlike `writeSkillFileMissingDescription`'s
    /// `.warning` (well-formed YAML, merely missing a field).
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and the
    ///     frontmatter's `name:` field.
    ///   - directory: The root to write under.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    private static func writeSkillFileWithUnparseableYAML(id: String, in directory: URL) throws {
        try Self.writeSkillFileWithRawContents(
            "---\nname: [unterminated\n---\nBody text for \(id).\n", id: id, in: directory)
    }

    /// Writes `id/SKILL.md` directly under `directory` with `contents`
    /// verbatim, creating the skill's own subdirectory first if it does not
    /// already exist -- the shared workhorse
    /// `writeSkillFileMissingDescription` and
    /// `writeSkillFileWithUnparseableYAML` both build on, so each stays a
    /// one-line description of its own fixture shape.
    ///
    /// - Parameters:
    ///   - contents: The complete `SKILL.md` file contents, frontmatter
    ///     fence included.
    ///   - id: The skill id -- the subdirectory name.
    ///   - directory: The root to write under.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    private static func writeSkillFileWithRawContents(_ contents: String, id: String, in directory: URL) throws {
        let skillDirectory = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try contents.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
