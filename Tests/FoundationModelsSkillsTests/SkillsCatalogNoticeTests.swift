import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import Testing
import ULID

@testable import FoundationModelsSkills

/// Tests for the catalog-change notice of the `skills` tool.
///
/// A host mounts the tool on a session with `ToolMounting.makeWrapped`, and
/// the session joins the `CatalogNoticeBoard` of the tool. On each registry
/// reload that changes the listed catalog, the `SkillsCatalogNoticeFollower`
/// posts one `CatalogChangeNotice` to the board. The sink of each live session
/// gets it. The description and the schema of the tool never change.
///
/// Most cases drive a real watched registry: a skill file lands on disk, and
/// the sink of the session is the whole proof. No case builds an embedder or
/// a model session.
struct SkillsCatalogNoticeTests {
    // MARK: - Constants

    /// The skill every case writes before it builds a tool.
    private static let seededSkillID = "alpha"

    /// The skill the first reload of a case adds.
    private static let firstAddedSkillID = "bravo"

    /// The skill the second reload of a case adds.
    private static let secondAddedSkillID = "charlie"

    /// The frontmatter line that hides a skill from the model.
    private static let hiddenFrontmatter = "disable-model-invocation: true\n"

    /// The body a body-only edit writes. The description stays the same.
    private static let editedBody = "An edited body, which the list never shows."

    /// The op of the run that starts a child session, in the child case.
    private static let childStartOp = "use skill"

    /// How long the release case watches the sink after it releases the
    /// follower. A follower that still runs posts inside this window.
    private static let releaseWindow: Duration = .milliseconds(300)

    // MARK: - One notice for a visible change

    @Test(.timeLimit(.minutes(1)))
    func aReloadThatAddsAVisibleSkillPostsOneNoticeThatNamesItUnderNew() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let session = Session()
        session.mount(fixture.tool)

        try ReloadTestSupport.writeSkillFile(id: Self.firstAddedSkillID, in: fixture.root)

        await ReloadTestSupport.expectExactlyOneEvent(
            countGetter: { await session.sink.notices.count }, since: 0,
            signalTimeout: ReloadTestSupport.expectedSignalTimeout,
            settleWindow: ReloadTestSupport.noFurtherSignalWindow)
        let notice = try #require(await session.sink.notices.first)
        #expect(notice.kind == .skills)
        #expect(notice.added.map(\.name) == [Self.firstAddedSkillID])
        #expect(notice.text.contains("New: `\(Self.firstAddedSkillID)`"))
    }

    // MARK: - No notice for a change the list does not show

    @Test(.timeLimit(.minutes(1)))
    func aBodyOnlyEditPostsNoNotice() async throws {
        try await Self.expectNoNotice { root in
            try ReloadTestSupport.writeSkillFile(id: Self.seededSkillID, in: root, body: Self.editedBody)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aReloadThatAddsAHiddenSkillPostsNoNotice() async throws {
        try await Self.expectNoNotice { root in
            try ReloadTestSupport.writeSkillFile(
                id: Self.firstAddedSkillID, in: root, extraFrontmatter: Self.hiddenFrontmatter)
        }
    }

    // MARK: - Each notice is diffed against the catalog before it

    @Test(.timeLimit(.minutes(1)))
    func twoReloadsPostTwoNoticesEachDiffedAgainstTheCatalogBeforeIt() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let session = Session()
        session.mount(fixture.tool)
        let expected = [[Self.firstAddedSkillID], [Self.secondAddedSkillID]]

        try ReloadTestSupport.writeSkillFile(id: Self.firstAddedSkillID, in: fixture.root)
        _ = await session.notices(reaching: 1)
        try ReloadTestSupport.writeSkillFile(id: Self.secondAddedSkillID, in: fixture.root)
        let notices = await session.notices(reaching: expected.count)

        #expect(notices.map { $0.added.map(\.name) } == expected)
        #expect(notices.allSatisfy { $0.removed.isEmpty && $0.changed.isEmpty })
    }

    // MARK: - The tool definition stays the same

    @Test(.timeLimit(.minutes(1)))
    func aReloadLeavesTheDescriptionAndTheParametersByteIdentical() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let session = Session()
        session.mount(fixture.tool)
        let description = fixture.tool.description
        let parameters = try Self.encoded(fixture.tool.parameters)

        try ReloadTestSupport.writeSkillFile(id: Self.firstAddedSkillID, in: fixture.root)
        _ = await session.notices(reaching: 1)

        #expect(Data(fixture.tool.description.utf8) == Data(description.utf8))
        #expect(try Self.encoded(fixture.tool.parameters) == parameters)
    }

    // MARK: - Which sessions get the notice

    @Test(.timeLimit(.minutes(1)))
    func aRootAndAChildSessionEachGetTheNoticeAndAClosedSessionGetsNone() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let root = Session()
        root.mount(fixture.tool)
        let child = root.makeChild()
        child.mount(fixture.tool)
        let closed = Session()
        closed.mount(fixture.tool)
        closed.registry.close()

        try ReloadTestSupport.writeSkillFile(id: Self.firstAddedSkillID, in: fixture.root)
        let rootNotices = await root.notices(reaching: 1)
        let childNotices = await child.notices(reaching: 1)

        #expect(rootNotices.map { $0.added.map(\.name) } == [[Self.firstAddedSkillID]])
        #expect(childNotices == rootNotices)
        #expect(await closed.sink.notices.isEmpty)
        #expect(fixture.tool.catalogNoticeBoard.sessionIDs == [root.registry.sessionID, child.registry.sessionID])
    }

    // MARK: - The race of a late mount

    /// Pins the race of a session that mounts the tool after a reload.
    ///
    /// The tool lists the catalog of the time it was made. A reload that
    /// lands before a session mounts the tool reaches only the sessions that
    /// joined before it. The late session thus never hears of that reload.
    /// Its next notice is diffed against the catalog of that reload, not
    /// against the catalog of the description.
    @Test(.timeLimit(.minutes(1)))
    func aSessionThatMountsAfterAReloadMissesItsNoticeAndGetsTheNextOne() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let early = Session()
        early.mount(fixture.tool)
        try ReloadTestSupport.writeSkillFile(id: Self.firstAddedSkillID, in: fixture.root)
        _ = await early.notices(reaching: 1)

        let late = Session()
        late.mount(fixture.tool)
        try ReloadTestSupport.writeSkillFile(id: Self.secondAddedSkillID, in: fixture.root)
        let earlyNotices = await early.notices(reaching: [Self.firstAddedSkillID, Self.secondAddedSkillID].count)
        let lateNotices = await late.notices(reaching: 1)

        #expect(fixture.tool.skillIDs == [Self.seededSkillID])
        #expect(lateNotices.map { $0.added.map(\.name) } == [[Self.secondAddedSkillID]])
        #expect(earlyNotices.last == lateNotices.first)
    }

    // MARK: - The follower stops with its last reference

    @Test(.timeLimit(.minutes(1)))
    func aReleasedFollowerPostsNoMoreNotices() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: Self.seededSkillID, in: root)
        let registry = SkillsRegistry(roots: [root])
        let seed = registry.metadata()
        let (reloads, publish) = AsyncStream.makeStream(of: [SkillMetadata].self)
        let session = Session()
        let board: CatalogNoticeBoard

        do {
            let follower = SkillsCatalogNoticeFollower(
                reloads: reloads, seed: seed, visibilityPredicate: { $0.isModelVisible })
            board = follower.board
            let tool = try SkillsTool.make(
                context: SkillsToolContext(
                    registry: registry,
                    searchAgent: SkillSearchAgent(searcher: MetadataSearcher(items: seed, mode: .retrieval)),
                    catalogNoticeFollower: follower))
            session.mount(tool)
            publish.yield(seed + [Self.visibleSkill(Self.firstAddedSkillID)])
            #expect(await session.notices(reaching: 1).count == 1)
        }

        publish.yield(seed + [Self.visibleSkill(Self.secondAddedSkillID)])
        try await Task.sleep(for: Self.releaseWindow)

        #expect(await session.sink.notices.count == 1, "a released follower must post no more notices")
        #expect(board.sessionIDs == [session.registry.sessionID])
    }

    // MARK: - Assembly

    @Test func aWatchedRegistryGetsANoticeFollowerAndAnUnwatchedOneNone() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: Self.seededSkillID, in: root)

        let watched = await Self.makeContext(registry: SkillsRegistry(roots: [root], watch: true))
        let unwatched = await Self.makeContext(registry: SkillsRegistry(roots: [root], watch: false))

        let follower = try #require(watched.catalogNoticeFollower)
        #expect(follower.board === watched.catalogNoticeBoard)
        #expect(unwatched.catalogNoticeFollower == nil, "a registry that never reloads posts no notice")
    }

    @Test func aHostThatPumpsTheSearchAgentItselfStillGetsANoticeFollower() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: Self.seededSkillID, in: root)

        let context = await Self.makeContext(
            registry: SkillsRegistry(roots: [root], watch: true), followReloads: false)

        #expect(context.reloadFollower == nil)
        #expect(context.catalogNoticeFollower != nil, "followReloads names the search agent, not the notices")
    }

    @Test func eachToolOfAContextGetsTheBoardOfThatContext() throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: Self.seededSkillID, in: root)
        let context = ResourceTestSupport.makeContext(roots: [root])

        let first = try SkillsTool.make(context: context)
        let second = try SkillsTool.make(context: context)

        #expect(first.catalogNoticeBoard === context.catalogNoticeBoard)
        #expect(second.catalogNoticeBoard === context.catalogNoticeBoard)
    }

    // MARK: - Helpers

    /// Builds a tool over a watched registry, applies `change` to its root,
    /// and asserts that the change posts no notice.
    ///
    /// The case first waits for the reload of `change` on a stream of its
    /// own. It then adds `secondAddedSkillID`, and waits for that notice. The
    /// follower reads the reloads in order, thus the one notice proves that
    /// the reload of `change` posted nothing.
    ///
    /// - Parameter change: Writes the change under test into the root.
    /// - Throws: Whatever `change`, the fixture, or a file write throws.
    private static func expectNoNotice(after change: (URL) throws -> Void) async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let session = Session()
        session.mount(fixture.tool)
        let reloads = ReloadTestSupport.EventTally()
        let tally = ReloadTestSupport.tally(fixture.registry.onReload, into: reloads)
        defer { tally.cancel() }

        try change(fixture.root)
        await ReloadTestSupport.expectExactlyOneEvent(reloads)
        try ReloadTestSupport.writeSkillFile(id: Self.secondAddedSkillID, in: fixture.root)
        let notices = await session.notices(reaching: 1)

        #expect(notices.map { $0.added.map(\.name) } == [[Self.secondAddedSkillID]])
        #expect(notices.allSatisfy { $0.removed.isEmpty && $0.changed.isEmpty })
    }

    /// Builds the metadata row of a skill that the model sees.
    ///
    /// - Parameter id: The skill id. The description names it.
    /// - Returns: The metadata row.
    private static func visibleSkill(_ id: String) -> SkillMetadata {
        SkillMetadata(id: id, description: "Does \(id).", isModelVisible: true)
    }

    /// Encodes `schema` with sorted keys, thus two equal schemas give the
    /// same bytes.
    ///
    /// - Parameter schema: The schema to encode.
    /// - Returns: The JSON bytes of the schema.
    /// - Throws: Whatever `JSONEncoder.encode(_:)` throws.
    private static func encoded(_ schema: GenerationSchema) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(schema)
    }

    /// Assembles a `SkillsToolContext` the way every `SkillsTool` factory
    /// does, with the retrieval tier and no embedder.
    ///
    /// - Parameters:
    ///   - registry: The registry the assembled context wraps.
    ///   - followReloads: Whether the assembly builds a reload follower for
    ///     the search agent. Defaults to `true`, the factories' own default.
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

    // MARK: - Fixtures

    /// A temporary root that holds `seededSkillID`, a watched registry over
    /// it, and the factory tool over that registry.
    private struct Fixture {
        /// The temporary layer root.
        let root: URL

        /// The watched registry over `root`.
        let registry: SkillsRegistry

        /// The tool the keyword-only factory builds over `registry`.
        let tool: SkillsCatalogTool

        /// Writes `seededSkillID` into a new root, and builds the registry
        /// and the tool.
        ///
        /// - Throws: Whatever the directory, the file write, or the factory
        ///   throws.
        init() async throws {
            root = try HotReloadTestSupport.makeTempDirectory()
            try ReloadTestSupport.writeSkillFile(id: SkillsCatalogNoticeTests.seededSkillID, in: root)
            registry = SkillsRegistry(roots: [root], watch: true)
            tool = try await SkillsTool.make(registry: registry)
        }

        /// Deletes the temporary root.
        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A session sink that keeps each catalog notice, in post order.
    private actor NoticeSink: OperationEventSink, CatalogNoticeSink {
        /// Each notice, in post order.
        private(set) var notices: [CatalogChangeNotice] = []

        /// Drops `event`: these cases read only the notices.
        ///
        /// - Parameter event: The event.
        func post(event: OperationEvent) {}

        /// Keeps `notice`.
        ///
        /// - Parameter notice: The notice.
        func post(catalogNotice notice: CatalogChangeNotice) {
            notices.append(notice)
        }
    }

    /// One session: its registry, its run plane, its sink and its mount site.
    private struct Session {
        /// The work registry of the session. A close makes it leave the board.
        let registry: WorkRegistry

        /// The run plane of the session.
        let runPlane: RunPlane

        /// The session sink, which keeps each notice.
        let sink: NoticeSink

        /// The mount site of the session.
        let site: MountSite

        /// Makes a root session with a new id.
        init() {
            let sessionID = ULID()
            registry = WorkRegistry(sessionID: sessionID)
            runPlane = RunPlane(workRegistry: registry)
            sink = NoticeSink()
            site = MountSite(sessionID: sessionID, runPlane: runPlane, sink: sink)
        }

        /// Makes a session from its parts.
        ///
        /// - Parameters:
        ///   - registry: The work registry of the session.
        ///   - runPlane: The run plane of the session.
        ///   - sink: The session sink.
        ///   - site: The mount site of the session.
        private init(registry: WorkRegistry, runPlane: RunPlane, sink: NoticeSink, site: MountSite) {
            self.registry = registry
            self.runPlane = runPlane
            self.sink = sink
            self.site = site
        }

        /// Makes a child session of this session, the way a call of this
        /// session starts a subagent.
        ///
        /// - Returns: The child session.
        func makeChild() -> Session {
            let context = ToolContext(
                sessionID: registry.sessionID, runPlane: runPlane, sink: sink, tool: SkillsTool.toolName,
                op: SkillsCatalogNoticeTests.childStartOp, completionToken: RunPlane.makeCompletionToken(),
                isCancelled: { false })
            let childID = ULID()
            let childRegistry = WorkRegistry(sessionID: childID)
            let childRunPlane = RunPlane(workRegistry: childRegistry)
            let childSink = NoticeSink()
            let childSite = context.childSite(sessionID: childID, runPlane: childRunPlane, sink: childSink)
            return Session(registry: childRegistry, runPlane: childRunPlane, sink: childSink, site: childSite)
        }

        /// Mounts `tool` on this session, as a host does at session start.
        ///
        /// - Parameter tool: The tool to mount.
        func mount(_ tool: any Tool) {
            _ = ToolMounting.makeWrapped(tool: tool, site: site, configuration: .synchronous)
        }

        /// Waits until the sink holds at least `count` notices, or until
        /// `ReloadTestSupport.expectedSignalTimeout` elapses.
        ///
        /// - Parameter count: The number of notices to wait for.
        /// - Returns: The notices the sink holds at the end of the wait.
        func notices(reaching count: Int) async -> [CatalogChangeNotice] {
            await ReloadTestSupport.poll(
                { await sink.notices }, until: { $0.count >= count },
                timeout: ReloadTestSupport.expectedSignalTimeout)
        }
    }
}
