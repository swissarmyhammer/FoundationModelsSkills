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
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFile(id: "editable-skill", in: root, descriptionSuffix: "before edit")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let recorder = MetadataUpdateRecorder()
        let subscription = Self.subscribe(registry, to: recorder)
        defer { subscription.cancel() }

        try Self.writeSkillFile(id: "editable-skill", in: root, descriptionSuffix: "after edit")
        await Self.expectExactlyOnePublication(recorder, since: 0)

        let latest = try #require(await recorder.publications.last)
        let entry = try #require(latest.first { $0.id == "editable-skill" })
        #expect(entry.description.contains("after edit"))
        #expect(!entry.description.contains("before edit"))
    }

    // MARK: - Add / remove propagate to metadata() and commandListing()

    @Test func addingASkillDirectoryPropagatesToMetadataAndCommandListing() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFile(id: "existing-skill", in: root, descriptionSuffix: "v1")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let recorder = MetadataUpdateRecorder()
        let subscription = Self.subscribe(registry, to: recorder)
        defer { subscription.cancel() }

        try Self.writeSkillFile(id: "new-skill", in: root, descriptionSuffix: "v1")
        await Self.expectExactlyOnePublication(recorder, since: 0)

        #expect(Set(registry.metadata().map(\.id)) == ["existing-skill", "new-skill"])
        #expect(Set(registry.commandListing().map(\.id)) == ["existing-skill", "new-skill"])
    }

    @Test func removingASkillDirectoryPropagatesToMetadataAndCommandListing() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFile(id: "surviving-skill", in: root, descriptionSuffix: "v1")
        try Self.writeSkillFile(id: "doomed-skill", in: root, descriptionSuffix: "v1")

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
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let knownIDs = (0..<5).map { "stress-\($0)" }
        for id in knownIDs {
            try Self.writeSkillFile(id: id, in: root, descriptionSuffix: "v1")
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
                    try Self.writeSkillFile(id: mutatedID, in: root, descriptionSuffix: "rev\(iteration)")
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
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFile(id: "static-skill", in: root, descriptionSuffix: "v1")

        let registry = SkillsRegistry(roots: [root])
        #expect(registry.onReload == nil)
    }

    @Test func watchFalseEditingATempFileChangesNothing() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFile(id: "static-skill", in: root, descriptionSuffix: "before edit")

        let registry = SkillsRegistry(roots: [root], watch: false)
        #expect(registry.onReload == nil)

        try Self.writeSkillFile(id: "static-skill", in: root, descriptionSuffix: "after edit")
        // Gives an incorrectly-wired watcher a chance to fire before asserting nothing changed.
        try await Task.sleep(for: Self.noFurtherSignalWindow)

        let entry = try #require(registry.metadata().first { $0.id == "static-skill" })
        #expect(entry.description.contains("before edit"))
        #expect(!entry.description.contains("after edit"))
    }

    // MARK: - Watcher lifecycle owned by the registry

    @Test func deinitStopsTheWatcherAndDeliversNoFurtherOnReloadPublicationsAfterward() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFile(id: "short-lived-skill", in: root, descriptionSuffix: "v1")

        var registry: SkillsRegistry? = SkillsRegistry(roots: [root], watch: true)
        let stream = try #require(registry?.onReload)
        registry = nil

        let recorder = MetadataUpdateRecorder()
        let subscription = Task {
            for await metadata in stream { await recorder.record(metadata) }
        }
        defer { subscription.cancel() }

        try Self.writeSkillFile(id: "short-lived-skill", in: root, descriptionSuffix: "v2")
        try await Task.sleep(for: Self.noFurtherSignalWindow)

        #expect(await recorder.publications.isEmpty)
    }

    // MARK: - Test helpers

    /// Tallies every `[SkillMetadata]` list `SkillsRegistry.onReload` publishes
    /// during a test.
    ///
    /// An actor rather than relying on the `AsyncStream` itself for
    /// assertions, mirroring `SkillWatcherTests.SignalRecorder`: polling this
    /// recorder's state sidesteps an `AsyncStream` iterator's single-consumer
    /// limitation entirely.
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
        let afterFirst = await Self.waitForPublicationCount(
            recorder, atLeast: baseline + 1, timeout: Self.expectedSignalTimeout)
        #expect(afterFirst == baseline + 1)

        let afterSettling = await Self.waitForPublicationCount(
            recorder, atLeast: baseline + 2, timeout: Self.noFurtherSignalWindow)
        #expect(afterSettling == baseline + 1)
        return afterSettling
    }

    /// Polls `recorder`'s publication count until it reaches `target` or
    /// `timeout` elapses.
    ///
    /// - Parameters:
    ///   - recorder: The recorder to poll.
    ///   - target: The publication count to wait for.
    ///   - timeout: How long to keep polling before giving up.
    /// - Returns: The observed publication count at the moment polling
    ///   stopped, whether or not it reached `target`.
    private static func waitForPublicationCount(
        _ recorder: MetadataUpdateRecorder, atLeast target: Int, timeout: Duration
    ) async -> Int {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var current = await recorder.publications.count
        while current < target, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            current = await recorder.publications.count
        }
        return current
    }

    /// Creates a fresh, empty temporary directory for a test root, so one
    /// test's filesystem activity can never be observed by another.
    ///
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    /// - Returns: The new directory's URL.
    private static func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Builds a minimal but structurally valid `SKILL.md` body for `id`,
    /// with `descriptionSuffix` folded into `description:` so a caller can
    /// observe a genuinely different `SkillMetadata.description` after an
    /// edit.
    ///
    /// - Parameters:
    ///   - id: The skill id the frontmatter's `name:` field carries.
    ///   - descriptionSuffix: Text appended to `description:`, so successive
    ///     calls with different suffixes produce distinguishable metadata.
    /// - Returns: The `SKILL.md` file contents.
    private static func skillFileContents(id: String, descriptionSuffix: String) -> String {
        "---\nname: \(id)\ndescription: reload fixture \(descriptionSuffix)\n---\nBody text for \(id).\n"
    }

    /// Writes `id/SKILL.md` directly under `directory`, creating the
    /// skill's own subdirectory first if it does not already exist.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and the
    ///     frontmatter's `name:` field.
    ///   - directory: The root to write under.
    ///   - descriptionSuffix: Forwarded to `skillFileContents(id:descriptionSuffix:)`.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    private static func writeSkillFile(id: String, in directory: URL, descriptionSuffix: String) throws {
        let skillDirectory = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try Self.skillFileContents(id: id, descriptionSuffix: descriptionSuffix)
            .write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
