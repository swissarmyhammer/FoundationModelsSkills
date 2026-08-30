import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import Operations
import Testing

@testable import FoundationModelsSkills

/// Tests for `SkillsReloadFollower` and the `followReloads:` parameter the
/// three `SkillsTool` factories carry.
///
/// `HotReloadTests` drives the same reload seam with the host loop written
/// out by hand, because that is what a host had to write before this
/// follower existed. This suite drives the seam with no host loop at all:
/// the tool comes out of a factory, a skill file lands on disk, and the
/// tool's own `search skill` answer is the whole proof.
///
/// Every case is GPU-free. No case builds an embedder or a session, thus the
/// searcher every case reads runs keyword retrieval only.
struct SkillsReloadFollowerTests {
    // MARK: - Constants

    /// How long a case waits for a watcher-driven reload to reach the
    /// assembled tool. Generous against `SkillWatcher`'s 200 ms debounce
    /// interval, thus scheduler and filesystem-event jitter never fails a
    /// case (mirrors `HotReloadTests.expectedSignalTimeout`).
    private static let reloadTimeout: Duration = .seconds(10)

    /// How long the release case waits after it drops its last reference to
    /// a follower, thus the cancelled forwarding task has time to stop
    /// before the case reads the counter.
    private static let cancellationWindow: Duration = .milliseconds(300)

    /// How long the release case then watches the counter. A forwarding task
    /// that still runs makes many more forwards inside this window, because
    /// `publicationInterval` is much shorter than it.
    private static let settleWindow: Duration = .milliseconds(500)

    /// How long the counted fixture stream waits before it gives the
    /// follower its next publication.
    private static let publicationInterval: Duration = .milliseconds(10)

    /// The skill every case writes into its temporary root before it builds
    /// a tool, thus no case ever assembles over an empty catalog.
    private static let seededSkillID = "alpha"

    /// The skill the reload cases add or remove after the tool is built.
    private static let reloadedSkillID = "bravo"

    // MARK: - A skill added after the tool was built

    @Test(.timeLimit(.minutes(1)))
    func theFactoryToolFindsASkillWrittenAfterTheToolWasBuilt() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: Self.seededSkillID, in: root)

        let tool = try await SkillsTool.make(registry: SkillsRegistry(roots: [root], watch: true))
        try ReloadTestSupport.writeSkillFile(id: Self.reloadedSkillID, in: root)

        let json = try await Self.searchOnceReloaded(through: tool, query: Self.reloadedSkillID) {
            $0.contains(Self.idField(Self.reloadedSkillID))
        }

        #expect(
            json.contains(Self.idField(Self.reloadedSkillID)),
            "the factory must follow the registry's reloads itself, with no host loop between")
    }

    // MARK: - A skill whose directory is removed

    @Test(.timeLimit(.minutes(1)))
    func theFactoryToolDropsASkillWhoseDirectoryIsRemoved() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: Self.seededSkillID, in: root)
        try ReloadTestSupport.writeSkillFile(id: Self.reloadedSkillID, in: root)

        let tool = try await SkillsTool.make(registry: SkillsRegistry(roots: [root], watch: true))
        let seeded = try await Self.searchJSON(through: tool, query: Self.reloadedSkillID)
        #expect(
            seeded.contains(Self.idField(Self.reloadedSkillID)),
            "the seeded catalog must carry the skill this case removes, or the case proves nothing")

        try FileManager.default.removeItem(
            at: root.appendingPathComponent(Self.reloadedSkillID, isDirectory: true))

        let json = try await Self.searchOnceReloaded(through: tool, query: Self.reloadedSkillID) {
            !$0.contains(Self.idField(Self.reloadedSkillID))
        }

        #expect(!json.contains(Self.idField(Self.reloadedSkillID)))
    }

    // MARK: - Which registry gets a follower

    @Test func theFollowerStandsOnAWatchedRegistryAndNowhereElse() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: Self.seededSkillID, in: root)

        let watched = await Self.makeContext(registry: SkillsRegistry(roots: [root], watch: true))
        let unwatched = await Self.makeContext(registry: SkillsRegistry(roots: [root], watch: false))

        #expect(watched.reloadFollower != nil)
        #expect(unwatched.reloadFollower == nil, "a registry that never reloads has nothing to follow")
    }

    @Test func askingForNoFollowedReloadsLeavesTheFollowerNil() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: Self.seededSkillID, in: root)

        let context = await Self.makeContext(
            registry: SkillsRegistry(roots: [root], watch: true), followReloads: false)

        #expect(context.reloadFollower == nil, "a host that pumps the stream itself must get no follower")
    }

    // MARK: - The forwarding task stops with its follower

    /// Shows that no forwarding task outlives its follower.
    ///
    /// The fixture stream counts every publication the forwarding task pulls
    /// from it, thus the counter measures the task's own liveness. The case
    /// drops its last reference and then watches the counter: a stopped task
    /// pulls nothing more, and the count holds still.
    ///
    /// A forwarding task that captured `self` would keep its follower alive
    /// for ever, `deinit` would never run, and the count would keep rising.
    /// The time limit is the second net: it fails this case rather than
    /// hanging the suite if a wait ever stops terminating.
    @Test(.timeLimit(.minutes(1)))
    func releasingTheLastReferenceStopsTheForwardingTask() async throws {
        let counter = ForwardCounter()
        let agent = SkillSearchAgent(searcher: MetadataSearcher<SkillMetadata>(items: [], mode: .retrieval))

        do {
            let follower = SkillsReloadFollower(
                reloads: Self.makeCountedStream(counter: counter), agent: agent)
            let forwarded = await ReloadTestSupport.poll(
                { await counter.count }, until: { $0 > 0 }, timeout: Self.reloadTimeout)
            #expect(forwarded > 0, "the forwarding task must forward while its follower lives")
            withExtendedLifetime(follower) {}
        }

        try await Task.sleep(for: Self.cancellationWindow)
        let afterCancellation = await counter.count
        try await Task.sleep(for: Self.settleWindow)

        #expect(
            await counter.count == afterCancellation,
            "a released follower must make no further forward")
    }

    // MARK: - Assembly

    /// Assembles a `SkillsToolContext` the way every `SkillsTool` factory
    /// does, with the retrieval tier and no embedder.
    ///
    /// - Parameters:
    ///   - registry: The registry the assembled context wraps.
    ///   - followReloads: Whether the assembly builds a follower. Defaults
    ///     to `true`, the factories' own default.
    /// - Returns: The assembled context.
    private static func makeContext(
        registry: SkillsRegistry, followReloads: Bool = true
    ) async -> SkillsToolContext {
        await SkillsTool.makeContext(
            registry: registry,
            mode: .retrieval,
            embedder: nil,
            selection: nil,
            followReloads: followReloads,
            visibilityPredicate: { $0.isModelVisible })
    }

    // MARK: - Dispatch

    /// Dispatches one `search skill` operation through `tool`.
    ///
    /// - Parameters:
    ///   - tool: The assembled `skills` tool to dispatch through.
    ///   - query: The search query.
    /// - Returns: The operation's JSON answer.
    /// - Throws: Whatever `OperationTool.call(arguments:)` throws.
    private static func searchJSON(
        through tool: OperationTool<SkillsToolContext>, query: String
    ) async throws -> String {
        try await tool.call(arguments: GeneratedContent(properties: ["op": "search skill", "query": query]))
    }

    /// Dispatches `search skill` until its answer satisfies `isSatisfied` or
    /// `reloadTimeout` elapses, then dispatches one final time and gives
    /// back that answer.
    ///
    /// The final dispatch is the one the caller asserts on, and it lets a
    /// dispatch failure reach the caller instead of reading as a reload that
    /// never landed.
    ///
    /// - Parameters:
    ///   - tool: The assembled `skills` tool to dispatch through.
    ///   - query: The search query.
    ///   - isSatisfied: Whether an answer shows the awaited reload landed.
    /// - Returns: The final answer.
    /// - Throws: Whatever `OperationTool.call(arguments:)` throws.
    private static func searchOnceReloaded(
        through tool: OperationTool<SkillsToolContext>, query: String, until isSatisfied: (String) -> Bool
    ) async throws -> String {
        _ = await ReloadTestSupport.poll(
            { (try? await Self.searchJSON(through: tool, query: query)) ?? "" },
            until: isSatisfied,
            timeout: Self.reloadTimeout)
        return try await Self.searchJSON(through: tool, query: query)
    }

    /// The `id` field a `search skill` answer carries for `id`.
    ///
    /// `AnyOperation` encodes with sorted keys and no whitespace, thus this
    /// is the exact text a match for `id` writes.
    ///
    /// - Parameter id: The skill id to look for.
    /// - Returns: The encoded field text.
    private static func idField(_ id: String) -> String {
        "\"id\":\"\(id)\""
    }

    // MARK: - Counted fixture stream

    /// Counts every publication a follower's forwarding task pulls.
    private actor ForwardCounter {
        private(set) var count = 0

        /// Records one more pulled publication.
        func record() {
            count += 1
        }
    }

    /// Builds a reload stream that counts each publication it hands out and
    /// then waits `publicationInterval` before the next one.
    ///
    /// Each publication is an empty catalog, because the release case asserts
    /// on the count alone and never on what the agent holds.
    ///
    /// - Parameter counter: The counter each publication is recorded into.
    /// - Returns: The counted stream.
    private static func makeCountedStream(counter: ForwardCounter) -> AsyncStream<[SkillMetadata]> {
        AsyncStream<[SkillMetadata]>(unfolding: {
            await counter.record()
            try? await Task.sleep(for: Self.publicationInterval)
            return []
        })
    }
}
