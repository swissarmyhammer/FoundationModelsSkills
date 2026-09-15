import Foundation
import Testing

@testable import FoundationModelsSkills

/// Proves the cache of marketplace.md §7: where the cache folder is, what one
/// marketplace folder holds, how an install swaps `current`, how cleanup keeps
/// two snapshots, and how `state.json` reads and writes.
///
/// Each test makes its own temporary cache, so no test reads the real home
/// folder or the files of another test.
@Suite("Marketplace cache")
struct MarketplaceCacheTests {
    // MARK: - Fixture

    /// The number of hex digits of a commit sha.
    private static let shaHexLength = 40

    /// The base of a hex digit.
    private static let hexRadix = 16

    /// The number of snapshots that the install tests write.
    private static let exampleShaCount = 4

    /// The number of snapshots that cleanup keeps: the one that `current`
    /// names, and the one before it.
    private static let keptShaCount = 2

    /// The number of installs of the cleanup tests: one more than the cache
    /// keeps.
    private static let cleanupInstallCount = keptShaCount + 1

    /// One sha for each install of a test, each with its own hex digit.
    private static let exampleShas = (0..<exampleShaCount).map { index in
        String(repeating: String(index, radix: hexRadix), count: shaHexLength)
    }

    /// The ref that the install tests write.
    private static let exampleRef = "main"

    /// The file that each staged snapshot holds. Its text is the sha of the
    /// snapshot, so a reader can tell which snapshot it read.
    private static let markerPath = "example-skill/SKILL.md"

    /// The name of the folder that holds the staged snapshots of a test.
    private static let stagingDirectoryName = "staging"

    /// A temporary cache with one marketplace folder in it.
    private struct CacheFixture: Sendable {
        /// The cache directory that holds `state.json` and the marketplace
        /// folders.
        let root: URL

        /// The cache of the one marketplace of the fixture.
        let cache: MarketplaceCache

        /// Makes a new temporary cache directory.
        ///
        /// - Throws: The error of the folder.
        init() throws {
            root = try MarketplaceTestSupport.makeTempDirectory()
            cache = MarketplaceCache(
                root: root,
                folderName: MarketplaceIdentity.cacheFolderName(
                    key: "skills", normalizedURL: "https://example.test/acme/skills.git"))
        }

        /// Deletes the temporary cache directory.
        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        /// Writes a staged snapshot folder that holds one marker file.
        ///
        /// - Parameter sha: The commit of the snapshot. It is the name of the
        ///   staged folder and the text of the marker file.
        /// - Returns: The staged folder.
        /// - Throws: The error of the folder or of the file write.
        func stageSnapshot(sha: String) throws -> URL {
            let staged = root
                .appendingPathComponent(stagingDirectoryName, isDirectory: true)
                .appendingPathComponent(sha, isDirectory: true)
            try MarketplaceTestSupport.writeFile(
                text: sha, to: staged.appendingPathComponent(markerPath))
            return staged
        }

        /// Stages one snapshot and installs it.
        ///
        /// - Parameter sha: The commit of the snapshot.
        /// - Throws: The error of the staging or of the install.
        func install(sha: String) throws {
            try cache.install(snapshotAt: try stageSnapshot(sha: sha), sha: sha, ref: exampleRef)
        }

        /// Reads the marker file of the snapshot that `current` names.
        ///
        /// - Returns: The sha that the marker file holds, or `nil` when no
        ///   install has happened yet.
        /// - Throws: The error of the file read. A read that throws means that
        ///   `current` named a folder that is missing or not complete.
        func readCurrentMarker() throws -> String? {
            try cache.currentSnapshot().map { current in
                try String(
                    contentsOf: current.appendingPathComponent(markerPath), encoding: .utf8)
            }
        }

        /// Reads `current` again and again, and counts the reads that gave a
        /// complete snapshot.
        ///
        /// - Parameter times: How many reads to do.
        /// - Returns: The number of reads whose marker file named the snapshot
        ///   that `current` named.
        /// - Throws: The error of a file read.
        func countCompleteReads(times: Int) async throws -> Int {
            var complete = 0
            for _ in 0..<times {
                if let marker = try readCurrentMarker(), marker == cache.currentSha() {
                    complete += 1
                }
                await Task.yield()
            }
            return complete
        }
    }

    // MARK: - Location

    @Test func theVariableNamesTheCacheDirectory() {
        let directory = MarketplaceCache.cacheDirectory(
            environment: [MarketplaceCache.cacheVariable: "/tmp/skills-cache"])

        #expect(directory.path == "/tmp/skills-cache")
    }

    @Test func anEmptyVariableFallsBackToTheHomeCache() {
        let directory = MarketplaceCache.cacheDirectory(
            environment: [MarketplaceCache.cacheVariable: ""])

        #expect(directory.path == Self.homeCachePath)
    }

    @Test func anAbsentVariableFallsBackToTheHomeCache() {
        let directory = MarketplaceCache.cacheDirectory(environment: [:])

        #expect(directory.path == Self.homeCachePath)
    }

    @Test func aTildeInTheVariableExpandsToTheHomeFolder() {
        let directory = MarketplaceCache.cacheDirectory(
            environment: [MarketplaceCache.cacheVariable: "~/skills-cache"])

        #expect(
            directory.path
                == FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("skills-cache").path)
    }

    /// The path of `~/.cache/skills/marketplaces`, which §7.1 names as the
    /// fallback.
    private static var homeCachePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/skills/marketplaces").path
    }

    // MARK: - Layout

    @Test func theMarketplaceFolderHoldsTheLayoutOfSectionSevenTwo() throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let cache = fixture.cache

        #expect(cache.folder.deletingLastPathComponent().path == fixture.root.path)
        #expect(cache.repositoryDirectory.lastPathComponent == "repo.git")
        #expect(cache.refsDirectory.lastPathComponent == "refs")
        #expect(cache.snapshotsDirectory.lastPathComponent == "snapshots")
        #expect(cache.currentLink.lastPathComponent == "current")
        #expect(cache.lockFile.lastPathComponent == "lock")
        #expect(
            MarketplaceCache.stateFile(inCacheDirectory: fixture.root).lastPathComponent
                == MarketplaceState.fileName)
    }

    // MARK: - Install and swap

    @Test func installMakesCurrentNameTheNewSnapshot() throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let sha = try #require(Self.exampleShas.first)

        try fixture.install(sha: sha)

        #expect(fixture.cache.currentSnapshot() == fixture.cache.snapshotDirectory(forSha: sha))
        #expect(try fixture.readCurrentMarker() == sha)
    }

    @Test func installMovesTheStagedFolderAway() throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let sha = try #require(Self.exampleShas.first)
        let staged = try fixture.stageSnapshot(sha: sha)

        try fixture.cache.install(snapshotAt: staged, sha: sha, ref: Self.exampleRef)

        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test func installWritesTheRefFile() throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let sha = try #require(Self.exampleShas.first)

        try fixture.install(sha: sha)

        #expect(try fixture.cache.sha(forRef: Self.exampleRef) == sha)
    }

    @Test func aSecondInstallKeepsTheFirstSnapshotForRollback() throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let shas = Array(Self.exampleShas.prefix(Self.keptShaCount))

        for sha in shas {
            try fixture.install(sha: sha)
        }

        #expect(try Set(fixture.cache.installedShas()) == Set(shas))
        #expect(fixture.cache.currentSha() == shas.last)
    }

    @Test func threeInstallsLeaveTwoSnapshots() throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let shas = Array(Self.exampleShas.prefix(Self.cleanupInstallCount))

        for sha in shas {
            try fixture.install(sha: sha)
        }

        #expect(try Set(fixture.cache.installedShas()) == Set(shas.suffix(Self.keptShaCount)))
        #expect(fixture.cache.currentSha() == shas.last)
    }

    @Test func cleanupKeepsASnapshotThatASharedLockHolds() throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let shas = Array(Self.exampleShas.prefix(Self.cleanupInstallCount))
        let held = try #require(shas.first)
        let last = try #require(shas.last)
        for sha in shas.dropLast() {
            try fixture.install(sha: sha)
        }

        try fixture.cache.withSnapshotInUse(sha: held) { _ in
            try fixture.install(sha: last)
        }

        #expect(try Set(fixture.cache.installedShas()) == Set(shas))
    }

    // MARK: - State

    @Test func aMissingStateFileGivesAnEmptyState() throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }

        let state = try MarketplaceState.load(
            from: MarketplaceCache.stateFile(inCacheDirectory: fixture.root))

        #expect(state.version == MarketplaceState.currentVersion)
        #expect(state.marketplaces.isEmpty)
    }

    @Test func theStateFileRoundTrips() throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let file = MarketplaceCache.stateFile(inCacheDirectory: fixture.root)
        var state = MarketplaceState()
        state.marketplaces[fixture.cache.folderName] = MarketplaceStateRecord(
            url: "git@github.com:swissarmyhammer/skills.git",
            ref: Self.exampleRef,
            currentSha: Self.exampleShas.first,
            catalogVersion: "1.2.0",
            lastChecked: Date(timeIntervalSince1970: 0),
            lastUpdated: Date(timeIntervalSince1970: 0))

        try state.save(to: file)

        #expect(try MarketplaceState.load(from: file) == state)
    }

    @Test func theDocumentedStateFileDecodes() throws {
        let sha = try #require(Self.exampleShas.first)
        let text = """
            {
              "version": 1,
              "marketplaces": {
                "swissarmyhammer-skills-1a2b3c4d": {
                  "url": "git@github.com:swissarmyhammer/skills.git",
                  "ref": "main", "pinnedSha": null,
                  "currentSha": "\(sha)", "catalogVersion": "1.2.0",
                  "lastChecked": "2026-09-14T19:55:43Z", "lastUpdated": "2026-09-12T08:10:00Z",
                  "lastError": null
                }
              }
            }
            """

        let state = try MarketplaceState.decode(from: Data(text.utf8))

        let record = try #require(state.marketplaces["swissarmyhammer-skills-1a2b3c4d"])
        #expect(state.version == MarketplaceState.currentVersion)
        #expect(record.ref == Self.exampleRef)
        #expect(record.pinnedSha == nil)
        #expect(record.currentSha == sha)
        #expect(record.catalogVersion == "1.2.0")
        #expect(record.lastError == nil)
        #expect(record.lastChecked != nil)
    }

    // MARK: - A reader during installs

    @Test func aReaderResolvesACompleteSnapshotDuringRepeatedInstalls() async throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let shas = Self.exampleShas
        try fixture.install(sha: try #require(shas.first))
        let reads = shas.count

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for sha in shas.dropFirst() {
                    try fixture.install(sha: sha)
                }
            }
            #expect(try await fixture.countCompleteReads(times: reads) == reads)
            try await group.waitForAll()
        }
    }
}
