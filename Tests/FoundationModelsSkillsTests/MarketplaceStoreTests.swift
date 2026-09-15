import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsSkills

/// Tests for the git half of ``MarketplaceStore`` (marketplace.md §6.1, §6.2,
/// §7.3, and §7.6).
///
/// Every test builds a repository with ``GitFixtureRepository`` and reads it
/// over a `file://` URL with the real ``LibGit2Transport``, thus the suite
/// needs no network and no `git` binary. Each store writes into a temporary
/// cache of its own.
struct MarketplaceStoreTests {
    /// How long a test waits for an expected `onReload` publication before it
    /// treats the absence as a failure (mirrors
    /// `MarketplaceRegistryTests.expectedSignalTimeout`).
    private static let expectedSignalTimeout: Duration = .seconds(10)

    /// How long a test waits, after an expected publication arrived, to
    /// confirm that no second publication follows it.
    private static let noFurtherSignalWindow: Duration = .seconds(1)

    /// The skill id that most fixtures hold.
    private static let skillID = "alpha"

    /// The credential that the credentials test gives. The values are plain
    /// fixture text.
    private static let credential = MarketplaceCredential(username: "fixture-user", token: "fixture-token")

    // MARK: - Cold start

    @Test func aColdStartMakesTheFixtureSkillsReachableThroughTheRegistry() async throws {
        let fixture = try GitFixtureRepository()
        try fixture.commit(files: Self.skillTree(body: "alpha body"))
        let cache = try MarketplaceStoreFixture(sources: [MarketplaceSource(fixture.url)])

        await cache.store.start()

        #expect(try cache.makeRegistry().call(id: Self.skillID).contains("alpha body"))
    }

    @Test func aColdStartReloadsAWaitingRegistryOneTime() async throws {
        let fixture = try GitFixtureRepository()
        try fixture.commit(files: Self.skillTree(body: "alpha body"))
        let cache = try MarketplaceStoreFixture(sources: [MarketplaceSource(fixture.url)])
        let registry = cache.makeRegistry()
        let stream = try #require(registry.onReload, "a marketplace-backed registry publishes reloads")
        let tally = ReloadTestSupport.EventTally()
        let subscription = ReloadTestSupport.tally(stream, into: tally)
        defer { subscription.cancel() }

        await cache.store.start()

        await ReloadTestSupport.expectExactlyOneEvent(
            countGetter: { await tally.count }, since: 0,
            signalTimeout: Self.expectedSignalTimeout, settleWindow: Self.noFurtherSignalWindow)
        #expect(try registry.call(id: Self.skillID).contains("alpha body"))
    }

    @Test func aSecondStartWithNoRemoteChangeDoesNoFetch() async throws {
        let fixture = try GitFixtureRepository()
        try fixture.commit(files: Self.skillTree(body: "alpha body"))
        let transport = RecordingGitTransport()
        let cache = try MarketplaceStoreFixture(sources: [MarketplaceSource(fixture.url)], transport: transport)

        await cache.store.start()
        await cache.store.start()

        #expect(await transport.fetchCount == 1)
        #expect(await transport.remoteHeadCount == 2)
    }

    // MARK: - Update

    @Test func aNewCommitAndAnUpdateSwapTheCurrentSnapshot() async throws {
        let fixture = try GitFixtureRepository()
        let first = try fixture.commit(files: Self.skillTree(body: "alpha body"))
        let cache = try MarketplaceStoreFixture(sources: [MarketplaceSource(fixture.url)])
        await cache.store.start()
        let second = try fixture.commit(files: Self.skillTree(body: "alpha body v2"))

        let events = await cache.store.update()

        #expect(events == [.updated(id: "fixture", from: first, to: second)])
        #expect(cache.store.marketplaceLayers().first?.provenance.sha == second)
        #expect(try cache.makeRegistry().call(id: Self.skillID).contains("alpha body v2"))
    }

    @Test func anUnreachableURLKeepsTheLastGoodSnapshot() async throws {
        let cache = try MarketplaceStoreFixture(sources: [])
        var head = ""
        var url = ""
        do {
            let fixture = try GitFixtureRepository()
            head = try fixture.commit(files: Self.skillTree(body: "alpha body"))
            url = fixture.url
            let served = try MarketplaceStoreFixture(
                sources: [MarketplaceSource(url)], cacheDirectory: cache.cacheDirectory)
            await served.store.start()
        }
        let store = MarketplaceStore(sources: [MarketplaceSource(url)], cacheDirectory: cache.cacheDirectory)

        let events = await store.update(force: true)

        #expect(events.count == 1)
        #expect(Self.keptVersion(ofFirst: events) == head)
        #expect(store.marketplaceLayers().first?.provenance.sha == head)
    }

    // MARK: - Layers

    @Test func eachLayerCarriesTheGrantsOfItsSource() async throws {
        let fixture = try GitFixtureRepository()
        try fixture.commit(files: Self.skillTree(body: "alpha body"))
        let source = MarketplaceSource(fixture.url, grants: MarketplaceGrants(shellInjection: true, scripts: true))
        let cache = try MarketplaceStoreFixture(sources: [source])

        await cache.store.start()

        let layer = try #require(cache.store.marketplaceLayers().first)
        #expect(layer.grants == MarketplaceGrants(shellInjection: true, scripts: true))
        #expect(layer.provenance.url == fixture.url)
    }

    @Test func aDuplicatePreFetchKeyRefusesTheWholeList() async throws {
        let first = try GitFixtureRepository()
        try first.commit(files: Self.skillTree(body: "first"))
        let second = try GitFixtureRepository()
        try second.commit(files: Self.skillTree(body: "second"))
        let cache = try MarketplaceStoreFixture(
            sources: [MarketplaceSource(first.url), MarketplaceSource(second.url)])

        await cache.store.start()

        #expect(cache.store.marketplaceLayers().isEmpty)
        #expect(cache.store.diagnostics.contains { $0.severity == .error && $0.message.contains("pre-fetch key") })
    }

    // MARK: - Locks

    @Test func theSnapshotThatOneStoreServesSurvivesCleanupByASecondStore() async throws {
        let fixture = try GitFixtureRepository()
        let first = try fixture.commit(files: Self.skillTree(body: "alpha body"))
        let cache = try MarketplaceStoreFixture(sources: [MarketplaceSource(fixture.url)])
        await cache.store.start()
        let other = MarketplaceStore(
            sources: [MarketplaceSource(fixture.url)], cacheDirectory: cache.cacheDirectory)

        try fixture.commit(files: Self.skillTree(body: "alpha body v2"))
        await other.update()
        try fixture.commit(files: Self.skillTree(body: "alpha body v3"))
        await other.update()

        #expect(cache.store.marketplaceLayers().first?.provenance.sha == first)
        #expect(try cache.makeRegistry().call(id: Self.skillID).contains("alpha body"))
    }

    // MARK: - Credentials and the display id

    @Test func theCredentialsClosureOfThePolicyReachesTheFetch() async throws {
        let fixture = try GitFixtureRepository()
        try fixture.commit(files: Self.skillTree(body: "alpha body"))
        let transport = RecordingGitTransport()
        let policy = MarketplacePolicy(credentials: { _ in Self.credential })
        let cache = try MarketplaceStoreFixture(
            sources: [MarketplaceSource(fixture.url)], policy: policy, transport: transport)

        await cache.store.start()

        #expect(await transport.fetchCredentials == [Self.credential])
    }

    @Test func twoSourcesWithTheSameCatalogNameGiveADiagnostic() async throws {
        let first = try GitFixtureRepository()
        try first.commit(files: Self.catalogTree(name: "shared", body: "first"))
        let second = try GitFixtureRepository()
        try second.commit(files: Self.catalogTree(name: "shared", body: "second"))
        let cache = try MarketplaceStoreFixture(
            sources: [
                MarketplaceSource(first.url, alias: "one"), MarketplaceSource(second.url, alias: "two"),
            ],
            transport: RecordingGitTransport())

        await cache.store.start()

        #expect(cache.store.marketplaceLayers().map(\.provenance.id) == ["shared", "shared"])
        #expect(cache.store.diagnostics.contains { $0.message.contains(#"the display id "shared""#) })
    }

    // MARK: - Support

    /// The commit that the first ``MarketplaceEvent/failed(id:error:keptVersion:)``
    /// of a list kept.
    ///
    /// - Parameter events: The events of one update.
    /// - Returns: The kept commit, or `nil` when the first event is no
    ///   failure.
    private static func keptVersion(ofFirst events: [MarketplaceEvent]) -> String? {
        if case .failed(_, _, let keptVersion) = events.first {
            return keptVersion
        }
        return nil
    }

    /// The tree of a fixture that has no catalog: one skill folder that a
    /// repository scan finds.
    ///
    /// - Parameter body: The body of the skill.
    /// - Returns: The tree, one entry for each path.
    private static func skillTree(body: String) -> [String: GitFixtureRepository.Entry] {
        ["skills/\(skillID)/SKILL.md": .file(ReloadTestSupport.skillFileContents(id: skillID, body: body))]
    }

    /// The tree of a fixture that has a Claude catalog with one plugin.
    ///
    /// - Parameters:
    ///   - name: The `name` field of the catalog, which becomes the display
    ///     id of the marketplace.
    ///   - body: The body of the skill.
    /// - Returns: The tree, one entry for each path.
    private static func catalogTree(name: String, body: String) -> [String: GitFixtureRepository.Entry] {
        let catalog = """
            {"name": "\(name)", "plugins": [{"name": "p", "source": "./", "skills": ["./skills/\(skillID)"]}]}
            """
        return skillTree(body: body).merging([".claude-plugin/marketplace.json": .file(catalog)]) { _, later in later }
    }
}
