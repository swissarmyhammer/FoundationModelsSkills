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
///
/// A `charlie` skill (`preload: true`, `disable-model-invocation: true`)
/// rides alongside `alpha`/`bravo` across steps 1-3, so `preloadedBodies()`
/// is genuinely exercised through an add/edit/remove -- not merely asserted
/// empty because nothing in the scenario was ever preloaded. Its
/// `disable-model-invocation: true` keeps it out of the search agent
/// entirely (`SkillSearchAgent.update(items:)` filters to
/// `isModelVisible` before ever reaching `MetadataSearcher`), so it never
/// perturbs the embed-count/diagnostic assertions steps 1-2 already make
/// about `alpha`/`bravo`.
///
/// The count-only event tally, generic polling, "exactly one event" wait,
/// and `SKILL.md` fixture-writing helpers all live in shared
/// `ReloadTestSupport`, not reimplemented here -- `SkillsRegistryReloadTests`
/// waits on the identical reload signal shape (review findings, 2026-07-29
/// 21:57).
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
        try ReloadTestSupport.writeSkillFile(id: "alpha", in: root, descriptionSuffix: "v1")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let embedGate = EmbedGate()
        let embedder = FakeEmbedder(dimension: 2, gate: embedGate)
        let diagnostics = DiagnosticRecorder()
        // `weights: cosine: 0` matters beyond "this scenario never asserts
        // on cosine ranking" (already true before this change): step 1
        // deliberately closes `embedGate` around a catalog-item re-embed to
        // observe it mid-flight, and a concurrent `search` call's own cosine
        // scoring would otherwise call `embedder.embed(_:)` a *second* time
        // for the query -- on the same gate the test's own code is still
        // awaiting the search to return before it can open. A nonzero
        // cosine weight here would self-deadlock step 1 against itself.
        let searcher = await MetadataSearcher(
            items: registry.metadata().filter(\.isModelVisible),
            weights: Weights(cosine: 0),
            embedder: embedder,
            onDiagnostic: { diagnostics.record($0) }
        )
        let agent = SkillSearchAgent(searcher: searcher)
        let updates = ReloadTestSupport.EventTally()
        let subscription = Self.subscribe(registry, forwardingTo: agent, recordingInto: updates)
        defer { subscription.cancel() }

        let tool = try SkillsTool.make(context: SkillsToolContext(registry: registry, searchAgent: agent))
        let schemaBefore = String(describing: tool.parameters)

        let preloadedAfterAdd = try await Self.stepOneAdd(
            root: root, registry: registry, updates: updates, diagnostics: diagnostics, embedGate: embedGate,
            tool: tool)
        let preloadedAfterEdit = try await Self.stepTwoEdit(
            root: root, registry: registry, updates: updates, embedder: embedder)
        let preloadedAfterRemove = try await Self.stepThreeRemove(
            root: root, registry: registry, updates: updates, tool: tool)
        try await Self.stepFourVisibilityFlip(root: root, updates: updates, tool: tool)
        try await Self.stepFivePreloadAndListing(
            registry: registry, tool: tool, schemaBefore: schemaBefore, preloadedAfterAdd: preloadedAfterAdd,
            preloadedAfterEdit: preloadedAfterEdit, preloadedAfterRemove: preloadedAfterRemove)
    }

    // MARK: - Selection tier: a scripted AgentSession double, GPU-free, post-reload

    /// Closes the other §13 gap distinct from the deterministic scenario
    /// above: that scenario's searcher is always `.retrieval`-mode (a
    /// `FakeEmbedder`, no `AgentSession` at all) -- the selection tier had
    /// zero GPU-free coverage anywhere in this package. Mirrors
    /// `FoundationModelsMetadataRegistryTests.TestSupport.ScriptedAgentSession`
    /// (this package's own zero-GPU stand-in for the selection tier's
    /// session seam) and drives one `.selection`-mode search before a reload
    /// and one after, proving `MetadataSearcher.update(items:)` genuinely
    /// rebuilds the whole `SelectionTier` -- and therefore its id-enum
    /// grammar and cached root session -- on a real content change, rather
    /// than serving a stale one: `SelectionSessionFactory.callCount`
    /// reaching `2` proves `SelectionConfig.model` was invoked a *second*
    /// time, which only happens if the tier was rebuilt.
    @Test
    func selectionTierSearchesThroughAScriptedAgentSessionAfterReload() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "alpha", in: root, descriptionSuffix: "v1")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let sessionFactory = SelectionSessionFactory(responsesPerCall: [
            [#"{"ids":["alpha"]}"#],
            [#"{"ids":["bravo"]}"#],
        ])
        let config = SelectionConfig(model: { _ in sessionFactory.makeSession() })
        let searcher = MetadataSearcher(
            items: registry.metadata().filter(\.isModelVisible), mode: .selection, selection: config)
        let agent = SkillSearchAgent(searcher: searcher)

        let preReloadMatches = try await agent.search(query: "anything", limit: 5)
        #expect(preReloadMatches.map(\.id) == ["alpha"])
        #expect(sessionFactory.callCount == 1)

        let updates = ReloadTestSupport.EventTally()
        let subscription = Self.subscribe(registry, forwardingTo: agent, recordingInto: updates)
        defer { subscription.cancel() }

        try ReloadTestSupport.writeSkillFile(id: "bravo", in: root, descriptionSuffix: "v1")
        await Self.expectExactlyOneUpdate(updates, since: 0)

        let postReloadMatches = try await agent.search(query: "anything", limit: 5)
        #expect(postReloadMatches.map(\.id) == ["bravo"])
        #expect(sessionFactory.callCount == 2, "a real content change must rebuild the tier's cached root session")
    }

    // MARK: - Step 1: add

    /// Adds a new `SKILL.md` (plus a `preload: true` sibling, `charlie`),
    /// confirms exactly one `update(items:)` call reaches the searcher, that
    /// the new id is immediately keyword-searchable *while the async cosine
    /// catch-up is still genuinely pending* (not merely asserted before an
    /// unenforced race), and that the catch-up eventually reports
    /// `.embedCatchUp(pending:total:)`.
    ///
    /// The pending window is made deterministic by `embedGate`: closed
    /// before the write, so `FakeEmbedder.embed(_:)` blocks the very first
    /// time `MetadataSearcher.update(items:)` reaches it --
    /// `waitUntilBlockedOrTimeout(_:timeout:)` confirms that block has
    /// genuinely started (proving the synchronous
    /// keyword/trigram rebuild already happened, per `update(items:)`'s own
    /// documented ordering) before this method's own search runs
    /// concurrently against the same actor, which Swift's actor reentrancy
    /// permits precisely because `update(items:)` is suspended, not
    /// synchronously blocking the actor.
    ///
    /// - Parameters:
    ///   - root: The watched temp root.
    ///   - registry: The registry under test.
    ///   - updates: Tallies every forwarded `update(items:)` call.
    ///   - diagnostics: Tallies every `MetadataDiagnostic` the searcher emits.
    ///   - embedGate: Gates `FakeEmbedder.embed(_:)` to make the pending
    ///     window deterministic.
    ///   - tool: The fused `skills` tool to dispatch through.
    /// - Returns: `registry.preloadedBodies()`, captured right after this
    ///   step's reload settles -- `charlie`'s v1 body should already be
    ///   present.
    private static func stepOneAdd(
        root: URL, registry: SkillsRegistry, updates: ReloadTestSupport.EventTally,
        diagnostics: DiagnosticRecorder, embedGate: EmbedGate, tool: OperationTool<SkillsToolContext>
    ) async throws -> String {
        await embedGate.close()
        try ReloadTestSupport.writeSkillFile(id: "bravo", in: root, descriptionSuffix: "v1")
        try ReloadTestSupport.writeSkillFile(
            id: "charlie", in: root, descriptionSuffix: "v1",
            extraFrontmatter: "preload: true\ndisable-model-invocation: true\n",
            body: "Preload payload v1 for charlie.")

        let blocked = await Self.waitUntilBlockedOrTimeout(embedGate, timeout: Self.expectedSignalTimeout)
        #expect(blocked, "expected the embed catch-up to have started (and be blocked on the gate) by now")

        let searchJSON = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "search skill", "query": "bravo"]))
        #expect(
            searchJSON.contains("\"id\":\"bravo\""),
            "keyword/trigram search must succeed on a newly added item while its embed catch-up is still pending")

        // `charlie` (`disable-model-invocation: true`) never reaches the
        // search agent at all -- only `registry.preloadedBodies()` sees it
        // -- so this read is unaffected by the still-closed gate.
        let preloadedAfterAdd = registry.preloadedBodies()

        await embedGate.open()
        await Self.expectExactlyOneUpdate(updates, since: 0)

        let caughtUp = await Self.waitForDiagnostic(
            diagnostics, timeout: Self.expectedSignalTimeout
        ) { diagnostic in
            if case .embedCatchUp(_, let total) = diagnostic { return total == 2 }
            return false
        }
        #expect(caughtUp, "expected an .embedCatchUp diagnostic covering both catalog items")

        return preloadedAfterAdd
    }

    // MARK: - Step 2: edit

    /// Edits `bravo`'s description (the text `renderBlock()` actually
    /// indexes -- `SkillMetadata.renderBlock()` never includes a skill's
    /// body) and `charlie`'s preloaded body, confirming only the changed
    /// searcher-visible item re-embeds, then re-writes `bravo` with
    /// identical content, confirming zero further re-embeds.
    ///
    /// - Parameters:
    ///   - root: The watched temp root.
    ///   - registry: The registry under test.
    ///   - updates: Tallies every forwarded `update(items:)` call.
    ///   - embedder: The counting embedder to assert re-embed counts against.
    /// - Returns: `registry.preloadedBodies()`, captured right after this
    ///   step's reload settles -- `charlie`'s v2 body should have replaced
    ///   v1.
    private static func stepTwoEdit(
        root: URL, registry: SkillsRegistry, updates: ReloadTestSupport.EventTally, embedder: FakeEmbedder
    ) async throws -> String {
        let baseline = await updates.count
        let countBeforeEdit = embedder.embeddedTextCount

        try ReloadTestSupport.writeSkillFile(id: "bravo", in: root, descriptionSuffix: "v2")
        try ReloadTestSupport.writeSkillFile(
            id: "charlie", in: root, descriptionSuffix: "v1",
            extraFrontmatter: "preload: true\ndisable-model-invocation: true\n",
            body: "Preload payload v2 for charlie.")
        await Self.expectExactlyOneUpdate(updates, since: baseline)
        await Self.waitForEmbeddedTextCount(embedder, atLeast: countBeforeEdit + 1, timeout: Self.expectedSignalTimeout)
        let countAfterRealEdit = embedder.embeddedTextCount
        #expect(
            countAfterRealEdit == countBeforeEdit + 1,
            "only the changed, searcher-visible item should re-embed -- charlie is model-hidden and never reaches the embedder")

        let preloadedAfterEdit = registry.preloadedBodies()
        #expect(preloadedAfterEdit.contains("Preload payload v2 for charlie."))
        #expect(!preloadedAfterEdit.contains("Preload payload v1 for charlie."))

        let secondBaseline = await updates.count
        try ReloadTestSupport.writeSkillFile(id: "bravo", in: root, descriptionSuffix: "v2")
        await Self.expectExactlyOneUpdate(updates, since: secondBaseline)
        // No async catch-up follows a no-op touch, so there is nothing to
        // poll for -- the noFurtherSignalWindow the update-count wait above
        // already spent is long enough for a wrongly-triggered re-embed to
        // have started.
        #expect(embedder.embeddedTextCount == countAfterRealEdit, "a no-op touch (unchanged content) must not re-embed")

        return preloadedAfterEdit
    }

    // MARK: - Step 3: remove

    /// Removes `alpha` and `charlie`, confirming `alpha`'s id disappears
    /// from `search skill` / `list skill`, that `use skill` against it draws
    /// the corrective carrying the current id list, and that `charlie`'s
    /// preloaded body no longer survives in `preloadedBodies()`.
    ///
    /// - Parameters:
    ///   - root: The watched temp root.
    ///   - registry: The registry under test.
    ///   - updates: Tallies every forwarded `update(items:)` call.
    ///   - tool: The fused `skills` tool to dispatch through.
    /// - Returns: `registry.preloadedBodies()`, captured right after this
    ///   step's reload settles -- `charlie`'s body should be entirely gone.
    private static func stepThreeRemove(
        root: URL, registry: SkillsRegistry, updates: ReloadTestSupport.EventTally,
        tool: OperationTool<SkillsToolContext>
    )
        async throws -> String
    {
        let baseline = await updates.count
        try FileManager.default.removeItem(at: root.appendingPathComponent("alpha", isDirectory: true))
        try FileManager.default.removeItem(at: root.appendingPathComponent("charlie", isDirectory: true))
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

        let preloadedAfterRemove = registry.preloadedBodies()
        #expect(
            !preloadedAfterRemove.contains("Preload payload"),
            "a removed preload: true skill's body must never survive in preloadedBodies()")

        return preloadedAfterRemove
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
        root: URL, updates: ReloadTestSupport.EventTally, tool: OperationTool<SkillsToolContext>
    ) async throws {
        let baseline = await updates.count
        try ReloadTestSupport.writeSkillFile(
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
    /// scenario's cumulative changes, that `preloadedBodies()` genuinely
    /// tracked `charlie`'s add/edit/remove across steps 1-3 (not merely
    /// empty because nothing was ever preloaded), and that the fused tool's
    /// schema is byte-identical to what it was before any of the four
    /// preceding steps ran -- the schema is a pure function of the fixed
    /// operation set, never of catalog content (plan.md §7).
    ///
    /// - Parameters:
    ///   - registry: The registry under test.
    ///   - tool: The fused `skills` tool the schema is read from.
    ///   - schemaBefore: The tool's schema description captured before step 1.
    ///   - preloadedAfterAdd: `registry.preloadedBodies()`, captured right
    ///     after step 1's reload settled.
    ///   - preloadedAfterEdit: `registry.preloadedBodies()`, captured right
    ///     after step 2's reload settled.
    ///   - preloadedAfterRemove: `registry.preloadedBodies()`, captured
    ///     right after step 3's reload settled.
    private static func stepFivePreloadAndListing(
        registry: SkillsRegistry, tool: OperationTool<SkillsToolContext>, schemaBefore: String,
        preloadedAfterAdd: String, preloadedAfterEdit: String, preloadedAfterRemove: String
    ) async throws {
        // `bravo` is now `disable-model-invocation: true` -- user-invocable
        // but not model-visible -- so it still appears on the user-facing
        // `commandListing()`. `alpha` was removed in step 3 and must appear
        // nowhere.
        let listing = registry.commandListing()
        #expect(listing.contains { $0.id == "bravo" })
        #expect(!listing.contains { $0.id == "alpha" })

        // The §13 preload half, actually exercised: each snapshot below was
        // captured right after its own step's reload settled, proving
        // `preloadedBodies()` tracked `charlie`'s add, then edit, then
        // removal -- not merely that it's empty because nothing in the
        // scenario was ever preloaded.
        #expect(preloadedAfterAdd.contains("Preload payload v1 for charlie."))
        #expect(preloadedAfterEdit.contains("Preload payload v2 for charlie."))
        #expect(!preloadedAfterEdit.contains("Preload payload v1 for charlie."))
        #expect(!preloadedAfterRemove.contains("Preload payload"))

        let preloaded = registry.preloadedBodies()
        #expect(!preloaded.contains("alpha"), "a removed skill's body must never survive in preloadedBodies()")
        #expect(
            !preloaded.contains("Preload payload"),
            "the removed preload: true skill must not reappear by the end of the scenario")

        let schemaAfter = String(describing: tool.parameters)
        #expect(schemaAfter == schemaBefore, "the fused tool's schema must never vary with catalog content")
    }

    // MARK: - Update-call subscription

    /// Starts a background task that iterates `registry.onReload` (when
    /// non-`nil`), forwarding each published metadata list into
    /// `agent.update(items:)` and tallying the forward into `recorder` --
    /// the plan.md §7.1 wiring a real host is responsible for, exercised
    /// here end to end.
    ///
    /// The stream is subscribed on the caller's thread, before the task is
    /// created. A subscription made inside the task registers only when the
    /// task first runs, and under a loaded cooperative pool that can be
    /// later than the watcher's first publication -- the publication is
    /// then lost, and every wait on it times out (^n89yw8p).
    ///
    /// - Parameters:
    ///   - registry: The registry whose `onReload` stream to subscribe to.
    ///   - agent: The search agent each publication is forwarded to.
    ///   - recorder: The recorder each forward is tallied into.
    /// - Returns: The subscription task; the caller cancels it once done
    ///   observing.
    private static func subscribe(
        _ registry: SkillsRegistry, forwardingTo agent: SkillSearchAgent, recordingInto recorder: ReloadTestSupport.EventTally
    ) -> Task<Void, Never> {
        let stream = registry.onReload
        return Task {
            guard let stream else { return }
            for await metadata in stream {
                await agent.update(items: metadata)
                await recorder.record()
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
    private static func expectExactlyOneUpdate(_ recorder: ReloadTestSupport.EventTally, since baseline: Int) async {
        await ReloadTestSupport.expectExactlyOneEvent(
            countGetter: { await recorder.count }, since: baseline,
            signalTimeout: Self.expectedSignalTimeout, settleWindow: Self.noFurtherSignalWindow)
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
        _ recorder: DiagnosticRecorder, timeout: Duration, matching matches: @escaping (MetadataDiagnostic) -> Bool
    ) async -> Bool {
        await ReloadTestSupport.poll(
            { recorder.snapshot.contains(where: matches) }, until: { $0 }, timeout: timeout)
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
        _ = await ReloadTestSupport.poll({ embedder.embeddedTextCount }, until: { $0 >= target }, timeout: timeout)
    }

    /// Polls `gate.isBlocked` until it is `true` or `timeout` elapses, so a
    /// step waiting for the embed catch-up to have genuinely started never
    /// hangs forever if that assumption ever stops holding (e.g. a future
    /// upstream change makes `MetadataSearcher.update(items:)` skip the
    /// embedder entirely, or the reload publication never arrives).
    ///
    /// A poll, not a suspended continuation raced against a sleep: a task
    /// group waits for every child before it returns, and a child parked on
    /// a continuation nothing resumes ignores cancellation. That shape kept
    /// the whole test process alive after the timeout won (^n89yw8p).
    ///
    /// - Parameters:
    ///   - gate: The gate to wait on.
    ///   - timeout: How long to wait before giving up.
    /// - Returns: `true` if `gate` reported a blocked `embed(_:)` call
    ///   before `timeout`; `false` otherwise.
    private static func waitUntilBlockedOrTimeout(_ gate: EmbedGate, timeout: Duration) async -> Bool {
        await ReloadTestSupport.poll({ await gate.isBlocked }, until: { $0 }, timeout: timeout)
    }

    // MARK: - Fixture embedder

    /// A deterministic `TextEmbedding` test double, mirroring
    /// `FoundationModelsMetadataRegistryTests.FakeEmbedder`.
    ///
    /// Every text embeds to an all-zero vector -- this scenario never
    /// asserts on cosine ranking, only on *counts* (how many texts were
    /// embedded) and on the `.embedCatchUp` diagnostic's presence, so no
    /// registered vector table is needed. An optional `gate` lets step 1
    /// deterministically observe an in-flight (not-yet-complete) embed call.
    private final class FakeEmbedder: TextEmbedding {
        let dimension: Int
        private let counter: EmbedCallCounter
        private let gate: EmbedGate?

        /// Creates a fake embedder that returns an all-zero vector for every
        /// text.
        ///
        /// - Parameters:
        ///   - dimension: The length of every embedding vector this
        ///     embedder produces.
        ///   - gate: Blocks every `embed(_:)` call until the gate is open,
        ///     or `nil` to never block. Defaults to `nil`.
        init(dimension: Int, gate: EmbedGate? = nil) {
            self.dimension = dimension
            self.counter = EmbedCallCounter()
            self.gate = gate
        }

        /// The total number of texts passed to `embed(_:)` across every call
        /// so far.
        var embeddedTextCount: Int { counter.count }

        func embed(_ texts: [String]) async throws -> [[Float]] {
            if let gate { await gate.waitUntilOpen() }
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

    /// A gate `FakeEmbedder.embed(_:)` can be told to block on, so step 1 can
    /// observe a deterministic window where the async embed catch-up is
    /// confirmed in flight (blocked awaiting this gate) but not yet
    /// complete -- proving a concurrent keyword search still succeeds during
    /// that window, per `MetadataSearcher.update(items:)`'s own reentrancy
    /// documentation (a concurrent `search` interleaves while `update` is
    /// suspended awaiting the embedder, since both are calls into the same
    /// actor and `update` is suspended, not synchronously blocking it).
    ///
    /// Starts open, so every construction-time embed and every step 2+ embed
    /// never blocks; step 1 closes it for one deliberate window, then
    /// reopens it for the rest of the scenario.
    private actor EmbedGate {
        private var isOpen = true
        private var openWaiters: [CheckedContinuation<Void, Never>] = []

        /// Whether some `embed(_:)` call is currently blocked on this gate.
        /// `waitUntilBlockedOrTimeout(_:timeout:)` polls it, so no caller
        /// ever suspends on a continuation this gate might never resume.
        private(set) var isBlocked = false

        /// Closes the gate: every subsequent `embed(_:)` call blocks in
        /// `waitUntilOpen()` until `open()` runs.
        func close() {
            isOpen = false
            isBlocked = false
        }

        /// Opens the gate, resuming every call currently blocked in
        /// `waitUntilOpen()` and letting every future call through
        /// immediately.
        func open() {
            isOpen = true
            let waiting = openWaiters
            openWaiters = []
            for continuation in waiting { continuation.resume() }
        }

        /// Called by `FakeEmbedder.embed(_:)`: returns immediately while the
        /// gate is open; otherwise marks the gate blocked (so a poll of
        /// `isBlocked` observes it) and suspends until `open()` runs.
        func waitUntilOpen() async {
            guard !isOpen else { return }
            isBlocked = true
            await withCheckedContinuation { openWaiters.append($0) }
        }
    }

    // MARK: - Scripted AgentSession (selection tier, GPU-free)

    /// A scripted `AgentSession` test double, mirroring
    /// `FoundationModelsMetadataRegistryTests.TestSupport.ScriptedAgentSession`
    /// (this package's own zero-GPU stand-in for the selection tier's
    /// session seam, plan.md §6/§8): returns each of `responses` in order,
    /// one per `respond(to:)` call, regardless of the prompt. Uses the
    /// protocol's default `fork()` (returns `self`) since nothing here needs
    /// to assert on fork call counts.
    ///
    /// `final class ... @unchecked Sendable`: `respond(to:)` needs to
    /// advance a call index across an `await` boundary; state lives behind
    /// `lock`, mirroring `EmbedCallCounter`'s pattern in this same file.
    private final class ScriptedAgentSession: AgentSession, @unchecked Sendable {
        /// Thrown once every scripted response has been consumed -- a test
        /// bug (an under-scripted fixture), never expected in practice.
        private struct ExhaustedScriptedResponses: Error {}

        private let responses: [String]
        private let lock = NSLock()
        private var callIndex = 0

        /// Creates a scripted session that returns `responses` in order, one
        /// per `respond(to:)` call.
        ///
        /// - Parameter responses: The canned responses to return, in call
        ///   order.
        init(_ responses: [String]) {
            self.responses = responses
        }

        func respond(to prompt: String) async throws -> String {
            let index = lock.withLock { () -> Int in
                let index = callIndex
                callIndex += 1
                return index
            }
            guard index < responses.count else { throw ExhaustedScriptedResponses() }
            return responses[index]
        }
    }

    /// Vends a fresh `ScriptedAgentSession` per call, one canned response
    /// array per invocation -- lets a test script the selection tier's
    /// pre-reload and post-reload sessions independently. `SelectionTier`
    /// rebuilds its cached root session (and therefore calls
    /// `SelectionConfig.model` again) only when
    /// `MetadataSearcher.update(items:)` observes a genuine content change,
    /// so `callCount` reaching `2` after a reload is itself proof the tier
    /// was rebuilt, not merely reused.
    ///
    /// `final class ... @unchecked Sendable`: mirrors `EmbedCallCounter`'s
    /// lock-guarded-state pattern.
    private final class SelectionSessionFactory: @unchecked Sendable {
        private let responsesPerCall: [[String]]
        private let lock = NSLock()
        private var callIndex = 0

        /// Creates a factory that vends one freshly-scripted session per
        /// call, drawing that call's canned responses from
        /// `responsesPerCall` in order.
        ///
        /// - Parameter responsesPerCall: One scripted-response array per
        ///   expected `makeSession()` call, in call order.
        init(responsesPerCall: [[String]]) {
            self.responsesPerCall = responsesPerCall
        }

        /// How many times `makeSession()` has been called so far.
        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return callIndex
        }

        /// Creates and returns the next freshly-scripted session --
        /// `SelectionConfig`'s `model` factory parameter. The closure
        /// ignores the `instructions` text, because a scripted session
        /// gives the same answers for all instructions.
        func makeSession() -> any AgentSession {
            lock.lock()
            let index = callIndex
            callIndex += 1
            lock.unlock()
            let responses = index < responsesPerCall.count ? responsesPerCall[index] : []
            return ScriptedAgentSession(responses)
        }
    }
}
