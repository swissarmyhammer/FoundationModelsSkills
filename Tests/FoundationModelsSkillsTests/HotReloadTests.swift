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
    // MARK: - The five §13 steps, in one deterministic scenario

    @Test
    func hotReloadEndToEndFiveStepScenario() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "alpha", in: root, descriptionSuffix: "v1")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let embedGate = EmbedGate()
        let embedder = FakeEmbedder(vectorLength: 2, gate: embedGate)
        let diagnostics = Recorder<MetadataDiagnostic>()
        // `weights: cosine: 0` matters beyond "this scenario never asserts
        // on cosine ranking" (already true before this change): step 1
        // deliberately closes `embedGate` around a catalog-item re-embed to
        // observe it mid-flight, and a concurrent `search` call's own cosine
        // scoring would otherwise call `embedder.embed(texts:)` a *second* time
        // for the query -- on the same gate the test's own code is still
        // awaiting the search to return before it can open. A nonzero
        // cosine weight here would self-deadlock step 1 against itself.
        let searcher = MetadataSearcher(
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

    // MARK: - Selection tier: a scripted LanguageModel, GPU-free, post-reload

    /// Closes the other §13 gap distinct from the deterministic scenario
    /// above: that scenario's searcher is always `.retrieval`-mode (a
    /// `FakeEmbedder`, no model at all). This case gives the selection tier a
    /// `ScriptedLanguageModel` and drives one `.selection`-mode search before
    /// a reload and one after. The instructions of the second call must name
    /// the new skill `bravo` as a candidate. Thus `MetadataSearcher.update(items:)`
    /// rebuilt the candidate prefix of the tier on a real content change, and
    /// the tier did not use a stale prefix.
    @Test
    func selectionTierSearchesThroughAScriptedModelAfterReload() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "alpha", in: root, descriptionSuffix: "v1")

        let registry = SkillsRegistry(roots: [root], watch: true)
        let model = ScriptedLanguageModel(#"{"ids":["alpha"]}"#, #"{"ids":["bravo"]}"#)
        let searcher = MetadataSearcher(
            items: registry.metadata().filter(\.isModelVisible), mode: .selection,
            selection: SelectionConfig(model: model))
        let agent = SkillSearchAgent(searcher: searcher)

        let preReloadMatches = try await agent.search(query: "anything", limit: 5)
        #expect(preReloadMatches.map(\.id) == ["alpha"])
        #expect(model.calls.count == 1)

        let updates = ReloadTestSupport.EventTally()
        let subscription = Self.subscribe(registry, forwardingTo: agent, recordingInto: updates)
        defer { subscription.cancel() }

        try ReloadTestSupport.writeSkillFile(id: "bravo", in: root, descriptionSuffix: "v1")
        await Self.expectExactlyOneUpdate(updates, since: 0)

        let postReloadMatches = try await agent.search(query: "anything", limit: 5)
        #expect(postReloadMatches.map(\.id) == ["bravo"])
        #expect(model.calls.count == 2)
        let postReloadInstructions = try #require(model.calls.last?.instructions)
        #expect(
            postReloadInstructions.contains("\nid: bravo\n"),
            "a real content change must rebuild the candidate prefix of the tier")
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
    /// before the write, so `FakeEmbedder.embed(texts:)` blocks the very first
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
    ///   - embedGate: Gates `FakeEmbedder.embed(texts:)` to make the pending
    ///     window deterministic.
    ///   - tool: The fused `skills` tool to dispatch through.
    /// - Returns: `registry.preloadedBodies()`, captured right after this
    ///   step's reload settles -- `charlie`'s v1 body should already be
    ///   present.
    private static func stepOneAdd(
        root: URL, registry: SkillsRegistry, updates: ReloadTestSupport.EventTally,
        diagnostics: Recorder<MetadataDiagnostic>, embedGate: EmbedGate, tool: SkillsCatalogTool
    ) async throws -> String {
        await embedGate.close()
        try ReloadTestSupport.writeSkillFile(id: "bravo", in: root, descriptionSuffix: "v1")
        try ReloadTestSupport.writeSkillFile(
            id: "charlie", in: root, descriptionSuffix: "v1",
            extraFrontmatter: "preload: true\ndisable-model-invocation: true\n",
            body: "Preload payload v1 for charlie.")

        let blocked = await Self.waitUntilBlockedOrTimeout(
            embedGate, timeout: ReloadTestSupport.expectedSignalTimeout)
        #expect(blocked, "expected the embed catch-up to have started (and be blocked on the gate) by now")

        let searchAnswer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "search skill", "query": "bravo"]))
        #expect(
            SkillLineReader.ids(in: searchAnswer).contains("bravo"),
            "keyword/trigram search must succeed on a newly added item while its embed catch-up is still pending")

        // `charlie` (`disable-model-invocation: true`) never reaches the
        // search agent at all -- only `registry.preloadedBodies()` sees it
        // -- so this read is unaffected by the still-closed gate.
        let preloadedAfterAdd = await registry.preloadedBodies()

        await embedGate.open()
        await Self.expectExactlyOneUpdate(updates, since: 0)

        let caughtUp = await Self.waitForDiagnostic(
            diagnostics, timeout: ReloadTestSupport.expectedSignalTimeout
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
        await Self.waitForEmbeddedTextCount(
            embedder, atLeast: countBeforeEdit + 1, timeout: ReloadTestSupport.expectedSignalTimeout)
        let countAfterRealEdit = embedder.embeddedTextCount
        #expect(
            countAfterRealEdit == countBeforeEdit + 1,
            "only the changed, searcher-visible item should re-embed -- charlie is model-hidden and never reaches the embedder")

        let preloadedAfterEdit = await registry.preloadedBodies()
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
        tool: SkillsCatalogTool
    )
        async throws -> String
    {
        let baseline = await updates.count
        try FileManager.default.removeItem(at: root.appendingPathComponent("alpha", isDirectory: true))
        try FileManager.default.removeItem(at: root.appendingPathComponent("charlie", isDirectory: true))
        await Self.expectExactlyOneUpdate(updates, since: baseline)

        let searchAnswer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "search skill", "query": "alpha"]))
        #expect(!SkillLineReader.ids(in: searchAnswer).contains("alpha"))

        let listAnswer = try await tool.call(arguments: GeneratedContent(properties: ["op": "list skill"]))
        let listedIDs = SkillLineReader.ids(in: listAnswer)
        #expect(!listedIDs.isEmpty, "the list must still hold a skill, or the check below proves nothing")
        #expect(!listedIDs.contains("alpha"))

        let useAnswer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "use skill", "id": "alpha"]))
        #expect(useAnswer.contains("not currently usable"))
        #expect(useAnswer.contains("bravo"), "the corrective should carry the current (still-usable) id list")

        let preloadedAfterRemove = await registry.preloadedBodies()
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
        root: URL, updates: ReloadTestSupport.EventTally, tool: SkillsCatalogTool
    ) async throws {
        let baseline = await updates.count
        try ReloadTestSupport.writeSkillFile(
            id: "bravo", in: root, descriptionSuffix: "v2", extraFrontmatter: "disable-model-invocation: true\n")
        await Self.expectExactlyOneUpdate(updates, since: baseline)

        let searchAnswer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "search skill", "query": "bravo"]))
        #expect(!SkillLineReader.ids(in: searchAnswer).contains("bravo"))

        let useAnswer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "use skill", "id": "bravo"]))
        #expect(useAnswer.contains("not currently usable"))
    }

    // MARK: - Step 5: preload + listing refresh, schema stability

    /// Confirms `preloadedBodies()` and `commandListing()` both reflect the
    /// scenario's cumulative changes, that `preloadedBodies()` genuinely
    /// tracked `charlie`'s add/edit/remove across steps 1-3 (not merely
    /// empty because nothing was ever preloaded), and that the fused tool's
    /// schema is byte-identical to what it was before any of the four
    /// preceding steps ran -- the schema, with its `id` enum, is fixed when
    /// the tool is made, and a hot reload never changes it (plan.md §7).
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
        registry: SkillsRegistry, tool: SkillsCatalogTool, schemaBefore: String,
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

        let preloaded = await registry.preloadedBodies()
        #expect(!preloaded.contains("alpha"), "a removed skill's body must never survive in preloadedBodies()")
        #expect(
            !preloaded.contains("Preload payload"),
            "the removed preload: true skill must not reappear by the end of the scenario")

        let schemaAfter = String(describing: tool.parameters)
        #expect(schemaAfter == schemaBefore, "a hot reload must never change the fused tool's schema")
    }

    // MARK: - Update-call subscription

    /// Starts a background task that iterates `registry.onReload`,
    /// forwarding each published metadata list into `agent.update(items:)`
    /// and tallying the forward into `recorder` -- the plan.md §7.1 wiring a
    /// real host is responsible for, exercised here end to end.
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
        ReloadTestSupport.forward(registry.onReload, to: agent, recordingInto: recorder)
    }

    /// Asserts that exactly one new `update(items:)` call lands on `recorder`
    /// after `baseline`: the count reaches `baseline + 1` within
    /// `ReloadTestSupport.expectedSignalTimeout`, and stays there through
    /// `ReloadTestSupport.noFurtherSignalWindow`.
    ///
    /// - Parameters:
    ///   - recorder: The recorder to assert against.
    ///   - baseline: The call count observed before the action under test.
    private static func expectExactlyOneUpdate(_ recorder: ReloadTestSupport.EventTally, since baseline: Int) async {
        await ReloadTestSupport.expectExactlyOneEvent(
            countGetter: { await recorder.count }, since: baseline,
            signalTimeout: ReloadTestSupport.expectedSignalTimeout,
            settleWindow: ReloadTestSupport.noFurtherSignalWindow)
    }

    // MARK: - Diagnostic polling

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
        _ recorder: Recorder<MetadataDiagnostic>, timeout: Duration,
        matching matches: @escaping (MetadataDiagnostic) -> Bool
    ) async -> Bool {
        await ReloadTestSupport.poll(
            { recorder.recorded.contains(where: matches) }, until: { $0 }, timeout: timeout)
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
    /// - Returns: `true` if `gate` reported a blocked `embed(texts:)` call
    ///   before `timeout`; `false` otherwise.
    private static func waitUntilBlockedOrTimeout(_ gate: EmbedGate, timeout: Duration) async -> Bool {
        await ReloadTestSupport.poll({ await gate.isBlocked }, until: { $0 }, timeout: timeout)
    }
}
