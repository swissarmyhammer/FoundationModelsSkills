import Foundation
import Testing

@testable import FoundationModelsSkills

/// Tests for the pins of ``MarketplaceStore`` and for
/// ``MarketplacePolicy/ApplyUpdates/nextLaunch`` (marketplace.md §8.3 and
/// §8.4).
///
/// The package holds no time value of its own. A pending snapshot is a flag
/// in `state.json` that the next ``MarketplaceStore/start()`` reads, thus no
/// test here waits for real time: each assertion follows a call of the store
/// or a record on the disk.
struct MarketplacePinTests {
    /// The display id of a fixture marketplace, which is its repository name.
    private static let fixtureID = "fixture"

    /// The body of the first commit of a fixture repository.
    private static let firstBody = "alpha body"

    /// The body of the second commit, which the remote head names when the
    /// fixture is made.
    private static let headBody = "alpha body v2"

    /// The body of a commit that a test adds after the store started.
    private static let laterBody = "alpha body v3"

    /// The id that no marketplace of a fixture has.
    private static let unknownID = "no-such-marketplace"

    /// A commit that no fixture repository holds. It is a hexadecimal object
    /// name, thus only the kind of the marketplace can refuse the pin.
    private static let wellFormedCommit = "0123456789abcdef0123456789abcdef01234567"

    /// A pin that is no commit at all.
    private static let malformedCommit = "not-a-commit"

    // MARK: - The pin of a source (§8.3)

    @Test func theShaFieldOfASourceInstallsThatCommitAndNotTheHead() async throws {
        let pinned = try PinFixture(pinToFirstCommit: true)

        await pinned.store.start()

        #expect(pinned.store.marketplaceLayers().first?.provenance.sha == pinned.first)
    }

    @Test func aCheckOfAPinnedSourceReportsTheNewerHead() async throws {
        let pinned = try PinFixture(pinToFirstCommit: true)
        await pinned.store.start()

        let statuses = await pinned.store.check()

        #expect(statuses.first?.current == pinned.first)
        #expect(statuses.first?.latest == pinned.head)
        #expect(statuses.first?.updateAvailable == true)
    }

    // MARK: - pin and unpin (§8.3)

    @Test func pinStopsTheNextUpdateAtTheNamedCommit() async throws {
        let fixture = try PinFixture()
        await fixture.store.start()
        try fixture.repository.commit(files: MarketplaceTestSupport.skillTree(body: Self.laterBody))

        try await fixture.store.pin(Self.fixtureID, sha: fixture.head)
        await fixture.store.update()

        #expect(fixture.store.marketplaceLayers().first?.provenance.sha == fixture.head)
    }

    @Test func pinWritesTheCommitIntoTheStateFile() async throws {
        let fixture = try PinFixture()
        await fixture.store.start()

        try await fixture.store.pin(Self.fixtureID, sha: fixture.first)

        #expect(try Self.record(inCacheOf: fixture)?.pinnedSha == fixture.first)
    }

    @Test func unpinLetsTheNextUpdateFetchTheHead() async throws {
        let pinned = try PinFixture(pinToFirstCommit: true)
        await pinned.store.start()

        try await pinned.store.unpin(Self.fixtureID)
        await pinned.store.update()

        #expect(pinned.store.marketplaceLayers().first?.provenance.sha == pinned.head)
    }

    @Test func unpinClearsTheCommitInTheStateFile() async throws {
        let fixture = try PinFixture()
        await fixture.store.start()
        try await fixture.store.pin(Self.fixtureID, sha: fixture.first)

        try await fixture.store.unpin(Self.fixtureID)

        let record = try Self.record(inCacheOf: fixture)
        #expect(record?.pinnedSha == nil)
        #expect(record?.unpinned == true)
    }

    @Test func aForcedUpdateOfAPinnedSourceKeepsThePinnedCommit() async throws {
        let pinned = try PinFixture(pinToFirstCommit: true)
        await pinned.store.start()

        await pinned.store.update(Self.fixtureID, force: true)

        #expect(pinned.store.marketplaceLayers().first?.provenance.sha == pinned.first)
    }

    @Test func pinOfAnUnknownMarketplaceThrows() async throws {
        let fixture = try PinFixture()

        await #expect(throws: MarketplacePinError.unknownMarketplace(id: Self.unknownID)) {
            try await fixture.store.pin(Self.unknownID, sha: fixture.first)
        }
    }

    @Test func unpinOfAnUnknownMarketplaceThrows() async throws {
        let fixture = try PinFixture()

        await #expect(throws: MarketplacePinError.unknownMarketplace(id: Self.unknownID)) {
            try await fixture.store.unpin(Self.unknownID)
        }
    }

    @Test func aPinThatIsNoCommitThrows() async throws {
        let fixture = try PinFixture()

        await #expect(throws: (any Error).self) {
            try await fixture.store.pin(Self.fixtureID, sha: Self.malformedCommit)
        }
    }

    @Test func pinOfAFolderOnThisComputerThrows() async throws {
        let folder = try MarketplaceTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try MarketplaceStoreFixture(
            sources: [MarketplaceSource("file://\(folder.path)")])
        let id = try #require(store.store.marketplaceLayers().first?.provenance.id)

        await #expect(throws: MarketplacePinError.notAGitMarketplace(id: id)) {
            try await store.store.pin(id, sha: Self.wellFormedCommit)
        }
    }

    // MARK: - .nextLaunch (§8.4)

    @Test func nextLaunchLeavesTheServedSnapshotWhereItIs() async throws {
        let fixture = try PinFixture(policy: MarketplacePolicy(applyUpdates: .nextLaunch))
        await fixture.store.start()
        try fixture.repository.commit(files: MarketplaceTestSupport.skillTree(body: Self.laterBody))

        await fixture.store.update()

        #expect(fixture.store.marketplaceLayers().first?.provenance.sha == fixture.head)
    }

    @Test func nextLaunchReportsTheStagedSnapshotAsAvailable() async throws {
        let fixture = try PinFixture(policy: MarketplacePolicy(applyUpdates: .nextLaunch))
        await fixture.store.start()
        let later = try fixture.repository.commit(
            files: MarketplaceTestSupport.skillTree(body: Self.laterBody))

        let events = await fixture.store.update()

        #expect(
            events == [.updateAvailable(id: Self.fixtureID, from: fixture.head, to: later)])
    }

    @Test func nextLaunchSwapsTheSnapshotAtTheNextStart() async throws {
        let fixture = try PinFixture(policy: MarketplacePolicy(applyUpdates: .nextLaunch))
        await fixture.store.start()
        let later = try fixture.repository.commit(
            files: MarketplaceTestSupport.skillTree(body: Self.laterBody))
        await fixture.store.update()

        await fixture.store.start()

        #expect(fixture.store.marketplaceLayers().first?.provenance.sha == later)
    }

    @Test func aPendingSnapshotSurvivesANewStoreOverTheSameCache() async throws {
        let fixture = try PinFixture(policy: MarketplacePolicy(applyUpdates: .nextLaunch))
        await fixture.store.start()
        let later = try fixture.repository.commit(
            files: MarketplaceTestSupport.skillTree(body: Self.laterBody))
        await fixture.store.update()
        let restarted = try PinFixture(
            policy: MarketplacePolicy(applyUpdates: .nextLaunch), sharing: fixture)

        await restarted.store.start()

        #expect(restarted.store.marketplaceLayers().first?.provenance.sha == later)
    }

    // MARK: - Fixtures

    /// One fixture repository with two commits, and a store over a temporary
    /// cache.
    ///
    /// The type is a class, thus the repository and the cache live as long as
    /// the test that holds them.
    private final class PinFixture {
        /// The repository that the marketplace source names.
        let repository: GitFixtureRepository

        /// The first commit of the repository.
        let first: String

        /// The second commit, which the remote head named when the fixture
        /// was made.
        let head: String

        /// The store and its cache.
        let cache: MarketplaceStoreFixture

        /// The store under test.
        var store: MarketplaceStore {
            cache.store
        }

        /// Makes a repository with two commits, and a store over it.
        ///
        /// - Parameters:
        ///   - pinToFirstCommit: Whether the `sha` field of the source names
        ///     the first commit, which the remote head no longer names. The
        ///     default is `false`.
        ///   - policy: The policy of the store. The default is
        ///     `MarketplacePolicy()`.
        /// - Throws: The error of a fixture step.
        init(pinToFirstCommit: Bool = false, policy: MarketplacePolicy = MarketplacePolicy()) throws {
            repository = try GitFixtureRepository()
            first = try repository.commit(
                files: MarketplaceTestSupport.skillTree(body: MarketplacePinTests.firstBody))
            head = try repository.commit(
                files: MarketplaceTestSupport.skillTree(body: MarketplacePinTests.headBody))
            cache = try MarketplaceStoreFixture(
                sources: [MarketplaceSource(repository.url, sha: pinToFirstCommit ? first : nil)],
                policy: policy)
        }

        /// Makes a second store over the repository and the cache of another
        /// fixture, as a new process would.
        ///
        /// - Parameters:
        ///   - policy: The policy of the store. The default is
        ///     `MarketplacePolicy()`.
        ///   - other: The fixture that owns the repository and the cache.
        /// - Throws: The error of a fixture step.
        init(policy: MarketplacePolicy = MarketplacePolicy(), sharing other: PinFixture) throws {
            repository = other.repository
            first = other.first
            head = other.head
            cache = try MarketplaceStoreFixture(
                sources: [MarketplaceSource(other.repository.url)],
                cacheDirectory: other.cache.cacheDirectory, policy: policy)
        }
    }

    /// The one state record of the cache of a fixture.
    ///
    /// - Parameter fixture: The fixture whose cache holds `state.json`.
    /// - Returns: The record, or `nil` when the file holds none.
    /// - Throws: The error of the file read or of the JSON decoder.
    private static func record(inCacheOf fixture: PinFixture) throws -> MarketplaceStateRecord? {
        let file = MarketplaceCache.stateFile(inCacheDirectory: fixture.cache.cacheDirectory)
        return try MarketplaceState.load(from: file).marketplaces.values.first
    }
}
