import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Operations
import Testing

/// The explicit, named hot-reload end-to-end case (plan.md §13, an M4
/// acceptance criterion, not incidental coverage).
///
/// Drives a REAL `MetadataSearcher` through `SkillSearchAgent` (never a
/// searcher mock), GPU-free via a counting `FakeEmbedder` -- mirroring
/// `FoundationModelsMetadataRegistry`'s own `HotReloadTests`/`FakeEmbedder`
/// pattern (`../FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/HotReloadTests.swift`).
/// This wiring -- `SkillsRegistry.onReload` forwarded into
/// `SkillSearchAgent.update(items:)` -- is exactly the seam plan.md §7.1
/// documents as the *caller's* responsibility, not something either type
/// does automatically; this test is also the one place that seam is
/// exercised end to end.
struct HotReloadTests {
    /// How long the test waits for an expected `update(items:)` call to
    /// reach the searcher before treating its absence as a failure.
    /// Generous relative to `SkillWatcher`'s default 200ms debounce interval
    /// to absorb scheduler and filesystem-event jitter in a sandboxed test
    /// environment (mirrors `SkillsRegistryReloadTests.expectedSignalTimeout`).
    private static let expectedSignalTimeout: Duration = .seconds(10)

    /// How long the test waits, after an expected `update(items:)` call
    /// already arrived, to confirm no *second* call follows it (mirrors
    /// `SkillsRegistryReloadTests.noFurtherSignalWindow`).
    private static let noFurtherSignalWindow: Duration = .seconds(1)

    // MARK: - The five §13 steps, in one deterministic scenario

    @Test
    func hotReloadEndToEndFiveStepScenario() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFile(id: "alpha", in: root, descriptionSuffix: "v1")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let embedder = FakeEmbedder(dimension: 2)
        let diagnostics = DiagnosticRecorder()
        let searcher = await MetadataSearcher(
            items: registry.metadata().filter(\.isModelVisible),
            embedder: embedder,
            onDiagnostic: { diagnostics.record($0) }
        )
        let agent = SkillSearchAgent(searcher: searcher)
        let updates = UpdateCallRecorder()
        let subscription = Self.subscribe(registry, forwardingTo: agent, recordingInto: updates)
        defer { subscription.cancel() }

        let tool = try SkillsTool.make(context: SkillsToolContext(registry: registry, searchAgent: agent))
        let schemaBefore = String(describing: tool.parameters)

        try await Self.stepOneAdd(root: root, registry: registry, updates: updates, diagnostics: diagnostics, tool: tool)
        try await Self.stepTwoEdit(root: root, updates: updates, embedder: embedder)
        try await Self.stepThreeRemove(root: root, updates: updates, tool: tool)
        try await Self.stepFourVisibilityFlip(root: root, updates: updates, tool: tool)
        try await Self.stepFivePreloadAndListing(registry: registry, tool: tool, schemaBefore: schemaBefore)
    }

    // MARK: - Step 1: add

    /// Adds a new `SKILL.md`, confirms exactly one `update(items:)` call
    /// reaches the searcher, that the new id is immediately keyword-searchable,
    /// and that the async cosine catch-up eventually reports
    /// `.embedCatchUp(pending:total:)`.
    ///
    /// - Parameters:
    ///   - root: The watched temp root.
    ///   - registry: The registry under test.
    ///   - updates: Tallies every forwarded `update(items:)` call.
    ///   - diagnostics: Tallies every `MetadataDiagnostic` the searcher emits.
    ///   - tool: The fused `skills` tool to dispatch through.
    private static func stepOneAdd(
        root: URL, registry: SkillsRegistry, updates: UpdateCallRecorder, diagnostics: DiagnosticRecorder,
        tool: OperationTool<SkillsToolContext>
    ) async throws {
        try Self.writeSkillFile(id: "bravo", in: root, descriptionSuffix: "v1")
        await Self.expectExactlyOneUpdate(updates, since: 0)

        let searchJSON = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "search skill", "query": "bravo"]))
        #expect(searchJSON.contains("\"id\":\"bravo\""))

        let caughtUp = await Self.waitForDiagnostic(
            diagnostics, timeout: Self.expectedSignalTimeout
        ) { diagnostic in
            if case .embedCatchUp(_, let total) = diagnostic { return total == 2 }
            return false
        }
        #expect(caughtUp, "expected an .embedCatchUp diagnostic covering both catalog items")
    }

    // MARK: - Step 2: edit

    /// Edits `bravo`'s description (the text `renderBlock()` actually
    /// indexes -- `SkillMetadata.renderBlock()` never includes a skill's
    /// body), confirming only the changed item re-embeds, then re-writes it
    /// with identical content, confirming zero further re-embeds.
    ///
    /// - Parameters:
    ///   - root: The watched temp root.
    ///   - updates: Tallies every forwarded `update(items:)` call.
    ///   - embedder: The counting embedder to assert re-embed counts against.
    private static func stepTwoEdit(root: URL, updates: UpdateCallRecorder, embedder: FakeEmbedder) async throws {
        let baseline = await updates.callCount
        let countBeforeEdit = embedder.embeddedTextCount

        try Self.writeSkillFile(id: "bravo", in: root, descriptionSuffix: "v2")
        await Self.expectExactlyOneUpdate(updates, since: baseline)
        await Self.waitForEmbeddedTextCount(embedder, atLeast: countBeforeEdit + 1, timeout: Self.expectedSignalTimeout)
        let countAfterRealEdit = embedder.embeddedTextCount
        #expect(countAfterRealEdit == countBeforeEdit + 1, "only the changed item's block should re-embed")

        let secondBaseline = await updates.callCount
        try Self.writeSkillFile(id: "bravo", in: root, descriptionSuffix: "v2")
        await Self.expectExactlyOneUpdate(updates, since: secondBaseline)
        // No async catch-up follows a no-op touch, so there is nothing to
        // poll for -- the noFurtherSignalWindow the update-count wait above
        // already spent is long enough for a wrongly-triggered re-embed to
        // have started.
        #expect(embedder.embeddedTextCount == countAfterRealEdit, "a no-op touch (unchanged content) must not re-embed")
    }

    // MARK: - Step 3: remove

    /// Removes `alpha`, confirming its id disappears from `search skill` /
    /// `list skill`, and that `use skill` against it draws the corrective
    /// carrying the current id list.
    ///
    /// - Parameters:
    ///   - root: The watched temp root.
    ///   - updates: Tallies every forwarded `update(items:)` call.
    ///   - tool: The fused `skills` tool to dispatch through.
    private static func stepThreeRemove(root: URL, updates: UpdateCallRecorder, tool: OperationTool<SkillsToolContext>)
        async throws
    {
        let baseline = await updates.callCount
        try FileManager.default.removeItem(at: root.appendingPathComponent("alpha", isDirectory: true))
        await Self.expectExactlyOneUpdate(updates, since: baseline)

        let searchJSON = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "search skill", "query": "alpha"]))
        #expect(!searchJSON.contains("\"id\":\"alpha\""))

        let listJSON = try await tool.call(arguments: GeneratedContent(properties: ["op": "list skill"]))
        #expect(!listJSON.contains("\"id\":\"alpha\""))

        let useJSON = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "use skill", "id": "alpha"]))
        #expect(useJSON.contains("not currently usable"))
        #expect(useJSON.contains("bravo"), "the corrective should carry the current (still-usable) id list")
    }

    // MARK: - Step 4: visibility flip on reload

    /// Adds `disable-model-invocation: true` to `bravo`'s frontmatter,
    /// confirming the model-visible subset forwarded to `update(items:)`
    /// shrinks -- `bravo` becomes unusable on every model-facing op even
    /// though it still exists on disk.
    ///
    /// - Parameters:
    ///   - root: The watched temp root.
    ///   - updates: Tallies every forwarded `update(items:)` call.
    ///   - tool: The fused `skills` tool to dispatch through.
    private static func stepFourVisibilityFlip(
        root: URL, updates: UpdateCallRecorder, tool: OperationTool<SkillsToolContext>
    ) async throws {
        let baseline = await updates.callCount
        try Self.writeSkillFile(
            id: "bravo", in: root, descriptionSuffix: "v2", extraFrontmatter: "disable-model-invocation: true\n")
        await Self.expectExactlyOneUpdate(updates, since: baseline)

        let searchJSON = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "search skill", "query": "bravo"]))
        #expect(!searchJSON.contains("\"id\":\"bravo\""))

        let useJSON = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "use skill", "id": "bravo"]))
        #expect(useJSON.contains("not currently usable"))
    }

    // MARK: - Step 5: preload + listing refresh, schema stability

    /// Confirms `preloadedBodies()` and `commandListing()` both reflect the
    /// scenario's cumulative changes, and that the fused tool's schema is
    /// byte-identical to what it was before any of the four preceding steps
    /// ran -- the schema is a pure function of the fixed operation set, never
    /// of catalog content (plan.md §7).
    ///
    /// - Parameters:
    ///   - registry: The registry under test.
    ///   - tool: The fused `skills` tool the schema is read from.
    ///   - schemaBefore: The tool's schema description captured before step 1.
    private static func stepFivePreloadAndListing(
        registry: SkillsRegistry, tool: OperationTool<SkillsToolContext>, schemaBefore: String
    ) async throws {
        // `bravo` is now `disable-model-invocation: true` -- user-invocable
        // but not model-visible -- so it still appears on the user-facing
        // `commandListing()`. `alpha` was removed in step 3 and must appear
        // nowhere.
        let listing = registry.commandListing()
        #expect(listing.contains { $0.id == "bravo" })
        #expect(!listing.contains { $0.id == "alpha" })

        let preloaded = registry.preloadedBodies()
        #expect(!preloaded.contains("alpha"), "a removed skill's body must never survive in preloadedBodies()")

        let schemaAfter = String(describing: tool.parameters)
        #expect(schemaAfter == schemaBefore, "the fused tool's schema must never vary with catalog content")
    }

    // MARK: - Update-call recorder

    /// Tallies every `SkillSearchAgent.update(items:)` call this test's
    /// `onReload` subscription forwards.
    private actor UpdateCallRecorder {
        private(set) var callCount = 0

        /// Records one forwarded `update(items:)` call.
        func recordUpdate() {
            callCount += 1
        }
    }

    /// Starts a background task that iterates `registry.onReload` (when
    /// non-`nil`), forwarding each published metadata list into
    /// `agent.update(items:)` and tallying the forward into `recorder` --
    /// the plan.md §7.1 wiring a real host is responsible for, exercised
    /// here end to end.
    ///
    /// - Parameters:
    ///   - registry: The registry whose `onReload` stream to subscribe to.
    ///   - agent: The search agent each publication is forwarded to.
    ///   - recorder: The recorder each forward is tallied into.
    /// - Returns: The subscription task; the caller cancels it once done
    ///   observing.
    private static func subscribe(
        _ registry: SkillsRegistry, forwardingTo agent: SkillSearchAgent, recordingInto recorder: UpdateCallRecorder
    ) -> Task<Void, Never> {
        Task {
            guard let stream = registry.onReload else { return }
            for await metadata in stream {
                await agent.update(items: metadata)
                await recorder.recordUpdate()
            }
        }
    }

    /// Asserts that exactly one new `update(items:)` call lands on `recorder`
    /// after `baseline`: the count reaches `baseline + 1` within
    /// `expectedSignalTimeout`, and stays there through
    /// `noFurtherSignalWindow`.
    ///
    /// - Parameters:
    ///   - recorder: The recorder to assert against.
    ///   - baseline: The call count observed before the action under test.
    private static func expectExactlyOneUpdate(_ recorder: UpdateCallRecorder, since baseline: Int) async {
        let afterFirst = await Self.waitForUpdateCount(recorder, atLeast: baseline + 1, timeout: Self.expectedSignalTimeout)
        #expect(afterFirst == baseline + 1)

        let afterSettling = await Self.waitForUpdateCount(recorder, atLeast: baseline + 2, timeout: Self.noFurtherSignalWindow)
        #expect(afterSettling == baseline + 1)
    }

    /// Polls `recorder`'s call count until it reaches `target` or `timeout`
    /// elapses.
    ///
    /// - Parameters:
    ///   - recorder: The recorder to poll.
    ///   - target: The call count to wait for.
    ///   - timeout: How long to keep polling before giving up.
    /// - Returns: The observed call count at the moment polling stopped,
    ///   whether or not it reached `target`.
    private static func waitForUpdateCount(_ recorder: UpdateCallRecorder, atLeast target: Int, timeout: Duration)
        async -> Int
    {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var current = await recorder.callCount
        while current < target, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            current = await recorder.callCount
        }
        return current
    }

    // MARK: - Diagnostic recorder

    /// Tallies every `MetadataDiagnostic` the searcher under test emits,
    /// mirroring `FoundationModelsMetadataRegistryTests.DiagnosticRecorder`.
    ///
    /// `@unchecked Sendable`: every access to `diagnostics` goes through
    /// `record(_:)` or `snapshot`, both of which hold `lock` for their
    /// entire critical section.
    private final class DiagnosticRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var diagnostics: [MetadataDiagnostic] = []

        /// Records `diagnostic` as observed.
        ///
        /// - Parameter diagnostic: The diagnostic to record.
        func record(_ diagnostic: MetadataDiagnostic) {
            lock.lock()
            defer { lock.unlock() }
            diagnostics.append(diagnostic)
        }

        /// A snapshot of every diagnostic recorded so far.
        var snapshot: [MetadataDiagnostic] {
            lock.lock()
            defer { lock.unlock() }
            return diagnostics
        }
    }

    /// Polls `recorder` until some recorded diagnostic satisfies `matches`,
    /// or `timeout` elapses.
    ///
    /// - Parameters:
    ///   - recorder: The recorder to poll.
    ///   - timeout: How long to keep polling before giving up.
    ///   - matches: The predicate a recorded diagnostic must satisfy.
    /// - Returns: `true` if a matching diagnostic was observed before
    ///   `timeout`; `false` otherwise.
    private static func waitForDiagnostic(
        _ recorder: DiagnosticRecorder, timeout: Duration, matching matches: (MetadataDiagnostic) -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if recorder.snapshot.contains(where: matches) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return recorder.snapshot.contains(where: matches)
    }

    /// Polls `embedder`'s embedded-text count until it reaches `target` or
    /// `timeout` elapses -- the async re-embed catch-up this test's step 2
    /// waits for is not signaled by `update(items:)` itself (which returns
    /// once the synchronous keyword/trigram rebuild completes, before the
    /// embed call finishes).
    ///
    /// - Parameters:
    ///   - embedder: The counting embedder to poll.
    ///   - target: The embedded-text count to wait for.
    ///   - timeout: How long to keep polling before giving up.
    private static func waitForEmbeddedTextCount(_ embedder: FakeEmbedder, atLeast target: Int, timeout: Duration)
        async
    {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while embedder.embeddedTextCount < target, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Fixture embedder

    /// A deterministic `TextEmbedding` test double, mirroring
    /// `FoundationModelsMetadataRegistryTests.FakeEmbedder`.
    ///
    /// Every text embeds to an all-zero vector -- this scenario never
    /// asserts on cosine ranking, only on *counts* (how many texts were
    /// embedded) and on the `.embedCatchUp` diagnostic's presence, so no
    /// registered vector table is needed.
    private final class FakeEmbedder: TextEmbedding {
        let dimension: Int
        private let counter: EmbedCallCounter

        /// Creates a fake embedder that returns an all-zero vector for every
        /// text.
        ///
        /// - Parameter dimension: The length of every embedding vector this
        ///   embedder produces.
        init(dimension: Int) {
            self.dimension = dimension
            self.counter = EmbedCallCounter()
        }

        /// The total number of texts passed to `embed(_:)` across every call
        /// so far.
        var embeddedTextCount: Int { counter.count }

        func embed(_ texts: [String]) async throws -> [[Float]] {
            counter.increment(by: texts.count)
            return texts.map { _ in [Float](repeating: 0, count: dimension) }
        }
    }

    /// A thread-safe call counter for `FakeEmbedder`.
    ///
    /// `@unchecked Sendable`: every access to `value` goes through `count`
    /// or `increment(by:)`, both of which hold `lock` for their entire
    /// critical section.
    private final class EmbedCallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        /// Adds `amount` to the running count.
        ///
        /// - Parameter amount: The amount to add.
        func increment(by amount: Int) {
            lock.lock()
            defer { lock.unlock() }
            value += amount
        }
    }

    // MARK: - Fixture file helpers

    /// Builds a minimal but structurally valid `SKILL.md` body for `id`,
    /// with `descriptionSuffix` folded into `description:` -- the field
    /// `SkillMetadata.renderBlock()` actually indexes, unlike the body,
    /// which `renderBlock()` never includes.
    ///
    /// - Parameters:
    ///   - id: The skill id the frontmatter's `name:` field carries.
    ///   - descriptionSuffix: Text appended to `description:`, so successive
    ///     calls with different suffixes produce a genuinely different
    ///     indexed block.
    ///   - extraFrontmatter: Additional raw frontmatter lines (each already
    ///     newline-terminated) inserted before the closing `---`, or empty
    ///     for none.
    /// - Returns: The `SKILL.md` file contents.
    private static func skillFileContents(id: String, descriptionSuffix: String, extraFrontmatter: String) -> String {
        "---\nname: \(id)\ndescription: hot-reload fixture \(descriptionSuffix)\n\(extraFrontmatter)---\nBody text for \(id).\n"
    }

    /// Writes `id/SKILL.md` directly under `directory`, creating the skill's
    /// own subdirectory first if it does not already exist.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and the
    ///     frontmatter's `name:` field.
    ///   - directory: The root to write under.
    ///   - descriptionSuffix: Forwarded to
    ///     `skillFileContents(id:descriptionSuffix:extraFrontmatter:)`.
    ///   - extraFrontmatter: Forwarded to
    ///     `skillFileContents(id:descriptionSuffix:extraFrontmatter:)`;
    ///     defaults to none.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    private static func writeSkillFile(
        id: String, in directory: URL, descriptionSuffix: String, extraFrontmatter: String = ""
    ) throws {
        let skillDirectory = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try Self.skillFileContents(id: id, descriptionSuffix: descriptionSuffix, extraFrontmatter: extraFrontmatter)
            .write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
