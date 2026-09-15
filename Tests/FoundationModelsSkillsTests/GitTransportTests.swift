import Foundation
import Testing
import libgit2

@testable import FoundationModelsSkills

/// Proves the libgit2 ``LibGit2Transport`` against fixture repositories over
/// `file://` URLs (marketplace.md §5.1 and §13).
///
/// Each fixture is a repository that ``GitFixtureRepository`` builds with
/// libgit2, thus the suite needs no network and no `git` binary.
@Suite("Git transport")
struct GitTransportTests {
    /// The transport under test, reached through the protocol that the
    /// marketplace store uses.
    private let transport: any GitTransport = LibGit2Transport()

    /// The HTTPS source that the credentials callback tests serve.
    private static let httpsSourceURL = "https://git.example.com/owner/skills.git"

    /// The credential that the credentials callback tests give. The values are
    /// plain fixture text.
    private static let credential = MarketplaceCredential(username: "fixture-user", token: "fixture-token")

    // MARK: - remoteHead

    @Test func remoteHeadGivesTheTipOfABranch() async throws {
        let fixture = try GitFixtureRepository()
        let tip = try fixture.commit(files: ["README.md": .file("first")])

        let head = try await transport.remoteHead(url: fixture.url, ref: "main", credentials: nil)

        #expect(head == tip)
    }

    @Test func remoteHeadGivesTheCommitOfALightweightTag() async throws {
        let fixture = try GitFixtureRepository()
        let tagged = try fixture.commit(files: ["README.md": .file("first")])
        try fixture.commit(files: ["README.md": .file("second")])
        try fixture.addLightweightTag(named: "v1.0.0", at: tagged)

        let head = try await transport.remoteHead(url: fixture.url, ref: "v1.0.0", credentials: nil)

        #expect(head == tagged)
    }

    @Test func remoteHeadGivesTheCommitThatAnAnnotatedTagPeelsTo() async throws {
        let fixture = try GitFixtureRepository()
        let tagged = try fixture.commit(files: ["README.md": .file("first")])
        try fixture.commit(files: ["README.md": .file("second")])
        try fixture.addAnnotatedTag(named: "v2.0.0", at: tagged)

        let head = try await transport.remoteHead(url: fixture.url, ref: "v2.0.0", credentials: nil)

        #expect(head == tagged)
    }

    @Test func remoteHeadGivesTheCommitThatHEADNames() async throws {
        let fixture = try GitFixtureRepository()
        let tip = try fixture.commit(files: ["README.md": .file("first")])

        let head = try await transport.remoteHead(url: fixture.url, ref: "HEAD", credentials: nil)

        #expect(head == tip)
    }

    @Test func remoteHeadThrowsRefNotFoundForAMissingRef() async throws {
        let fixture = try GitFixtureRepository()
        try fixture.commit(files: ["README.md": .file("first")])

        await #expect(throws: GitTransportError.refNotFound) {
            try await transport.remoteHead(url: fixture.url, ref: "missing", credentials: nil)
        }
    }

    @Test func remoteHeadThrowsUnreachableForAMissingPath() async throws {
        let parent = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let absent = parent.appendingPathComponent("absent", isDirectory: true).absoluteString

        await #expect(throws: GitTransportError.unreachable) {
            try await transport.remoteHead(url: absent, ref: "main", credentials: nil)
        }
    }

    // MARK: - fetch

    @Test func fetchPutsTheBranchTipInANewBareRepository() async throws {
        let fixture = try GitFixtureRepository()
        let tip = try fixture.commit(files: ["skills/commit/SKILL.md": .file("body"), "run.sh": .executable("echo")])
        let destination = try Self.makeDestination()
        defer { Self.removeDestination(destination) }

        let fetched = try await transport.fetch(
            url: fixture.url, revision: "main", intoBareRepository: destination, credentials: nil)

        #expect(fetched == tip)
        #expect(try GitFixtureRepository.containsCommit(sha: tip, inRepositoryAt: destination))
    }

    @Test func fetchGetsTheNewerCommitAfterTheBranchMoves() async throws {
        let fixture = try GitFixtureRepository()
        let first = try fixture.commit(files: ["README.md": .file("first")])
        let destination = try Self.makeDestination()
        defer { Self.removeDestination(destination) }
        let firstFetch = try await transport.fetch(
            url: fixture.url, revision: "main", intoBareRepository: destination, credentials: nil)
        let newer = try fixture.commit(
            files: ["README.md": .file("newer"), "link": .symlink(target: "README.md")], on: "next")
        try fixture.moveBranch(named: "main", to: newer)

        let secondFetch = try await transport.fetch(
            url: fixture.url, revision: "main", intoBareRepository: destination, credentials: nil)

        #expect(firstFetch == first)
        #expect(secondFetch == newer)
        #expect(try GitFixtureRepository.containsCommit(sha: newer, inRepositoryAt: destination))
    }

    @Test func fetchOfAPinnedSHAGivesThatCommit() async throws {
        let fixture = try GitFixtureRepository()
        let pinned = try fixture.commit(files: ["README.md": .file("first")])
        try fixture.commit(files: ["README.md": .file("second")])
        let destination = try Self.makeDestination()
        defer { Self.removeDestination(destination) }

        let fetched = try await transport.fetch(
            url: fixture.url, revision: pinned, intoBareRepository: destination, credentials: nil)

        #expect(fetched == pinned)
        #expect(try GitFixtureRepository.containsCommit(sha: pinned, inRepositoryAt: destination))
    }

    @Test func fetchOfAnAnnotatedTagGivesTheCommit() async throws {
        let fixture = try GitFixtureRepository()
        let tagged = try fixture.commit(files: ["README.md": .file("first")])
        try fixture.addAnnotatedTag(named: "v2.0.0", at: tagged)
        let destination = try Self.makeDestination()
        defer { Self.removeDestination(destination) }

        let fetched = try await transport.fetch(
            url: fixture.url, revision: "v2.0.0", intoBareRepository: destination, credentials: nil)

        #expect(fetched == tagged)
    }

    @Test func fetchOfAMissingRefThrowsRefNotFound() async throws {
        let fixture = try GitFixtureRepository()
        try fixture.commit(files: ["README.md": .file("first")])
        let destination = try Self.makeDestination()
        defer { Self.removeDestination(destination) }

        await #expect(throws: GitTransportError.refNotFound) {
            try await transport.fetch(
                url: fixture.url, revision: "missing", intoBareRepository: destination, credentials: nil)
        }
    }

    @Test func fetchThrowsUnreachableForAMissingPath() async throws {
        let destination = try Self.makeDestination()
        defer { Self.removeDestination(destination) }
        let absent = destination.deletingLastPathComponent()
            .appendingPathComponent("absent", isDirectory: true).absoluteString

        await #expect(throws: GitTransportError.unreachable) {
            try await transport.fetch(url: absent, revision: "main", intoBareRepository: destination, credentials: nil)
        }
    }

    @Test func fetchInACancelledTaskThrowsCancelled() async throws {
        let fixture = try GitFixtureRepository()
        try fixture.commit(files: ["README.md": .file("first")])
        let destination = try Self.makeDestination()
        defer { Self.removeDestination(destination) }
        let url = fixture.url
        let transport = transport

        let fetch = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.fetch(url: url, revision: "main", intoBareRepository: destination, credentials: nil)
        }

        await #expect(throws: GitTransportError.cancelled) {
            try await fetch.value
        }
    }

    // MARK: - Shallow fetch and the retry

    @Test func aShallowFetchThatIsNotSupportedIsTriedAgainWithFullDepth() {
        var depths: [Int32] = []

        let status = LibGit2Transport.fetchShallowFirst { depth in
            depths.append(depth)
            return depth == LibGit2Transport.shallowDepth ? GIT_ENOTSUPPORTED.rawValue : GIT_OK.rawValue
        }

        #expect(depths == [LibGit2Transport.shallowDepth, LibGit2Transport.fullDepth])
        #expect(status == GIT_OK.rawValue)
    }

    @Test(arguments: [
        GIT_OK.rawValue, GIT_ERROR.rawValue, GIT_ENOTFOUND.rawValue, GIT_EUSER.rawValue, GIT_TIMEOUT.rawValue,
    ])
    func aShallowFetchIsTriedAgainOnlyWhenNotSupported(status: Int32) {
        var depths: [Int32] = []

        let result = LibGit2Transport.fetchShallowFirst { depth in
            depths.append(depth)
            return status
        }

        #expect(depths == [LibGit2Transport.shallowDepth])
        #expect(result == status)
    }

    // MARK: - Credentials

    @Test func aFileSourceFetchesWithNoCredentialRequest() async throws {
        let fixture = try GitFixtureRepository()
        let tip = try fixture.commit(files: ["README.md": .file("first")])
        let destination = try Self.makeDestination()
        defer { Self.removeDestination(destination) }
        let requests = CredentialRequestCounter()

        let fetched = try await transport.fetch(
            url: fixture.url, revision: "main", intoBareRepository: destination,
            credentials: requests.provider(giving: Self.credential))

        #expect(fetched == tip)
        #expect(await requests.count == 0)
    }

    @Test func theCredentialsCallbackGivesTheCredentialOneTime() throws {
        var gate = CredentialGate(sourceURL: Self.httpsSourceURL, credential: Self.credential)
        var first: UnsafeMutablePointer<git_credential>?
        var second: UnsafeMutablePointer<git_credential>?

        let statuses = withUnsafeMutablePointer(to: &gate) { gate in
            [
                LibGit2Transport.credentialStatus(into: &first, requestURL: Self.httpsSourceURL, gate: gate),
                LibGit2Transport.credentialStatus(into: &second, requestURL: Self.httpsSourceURL, gate: gate),
            ]
        }
        defer { git_credential_free(first) }
        let given: UnsafeMutablePointer<git_credential> = try #require(first)

        #expect(statuses == [GIT_OK.rawValue, GIT_EUSER.rawValue])
        #expect(String(cString: git_credential_get_username(given)) == Self.credential.username)
        #expect(second == nil)
    }

    @Test func theCredentialsCallbackRefusesARequestFromAnotherOrigin() {
        var gate = CredentialGate(sourceURL: Self.httpsSourceURL, credential: Self.credential)
        var given: UnsafeMutablePointer<git_credential>?

        let status = withUnsafeMutablePointer(to: &gate) { gate in
            LibGit2Transport.credentialStatus(
                into: &given, requestURL: "https://other.example.com/owner/skills.git", gate: gate)
        }

        #expect(status == GIT_EUSER.rawValue)
        #expect(given == nil)
    }

    // MARK: - Error mapping

    @Test(arguments: LibGit2Transport.Phase.allCases)
    func aStopFromAProgressCallbackIsCancelled(phase: LibGit2Transport.Phase) {
        let error = LibGit2Transport.transportError(code: GIT_EUSER.rawValue, message: "stopped", phase: phase)

        #expect(error == .cancelled)
    }

    @Test(arguments: LibGit2Transport.Phase.allCases)
    func aStopFromARefusedCredentialRequestIsUnreachable(phase: LibGit2Transport.Phase) {
        let error = LibGit2Transport.transportError(
            code: GIT_EUSER.rawValue, message: "stopped", phase: phase, credentialRefused: true)

        #expect(error == .unreachable)
    }

    @Test(arguments: LibGit2Transport.Phase.allCases)
    func aTimeoutFromTheNetworkIsTimedOut(phase: LibGit2Transport.Phase) {
        let error = LibGit2Transport.transportError(code: GIT_TIMEOUT.rawValue, message: "timed out", phase: phase)

        #expect(error == .timedOut)
    }

    @Test func anyOtherConnectFailureIsUnreachable() {
        let error = LibGit2Transport.transportError(
            code: GIT_ERROR.rawValue, message: "failed to resolve address", phase: .connecting)

        #expect(error == .unreachable)
    }

    @Test func aMissingObjectDuringTheFetchIsRefNotFound() {
        let error = LibGit2Transport.transportError(
            code: GIT_ENOTFOUND.rawValue, message: "object not found", phase: .fetching)

        #expect(error == .refNotFound)
    }

    @Test(arguments: [LibGit2Transport.Phase.fetching, .localRepository])
    func anyOtherFailureKeepsTheLibgit2CodeAndMessage(phase: LibGit2Transport.Phase) {
        let error = LibGit2Transport.transportError(code: GIT_ERROR.rawValue, message: "disk full", phase: phase)

        #expect(error == .libgit2(code: GIT_ERROR.rawValue, message: "disk full"))
    }

    // MARK: - Support

    /// A path for a bare repository that does not exist yet, in a new
    /// temporary directory.
    private static func makeDestination() throws -> URL {
        try WatcherTestSupport.makeTempDirectory().appendingPathComponent("repo.git", isDirectory: true)
    }

    /// Removes the temporary directory that ``makeDestination()`` made.
    private static func removeDestination(_ destination: URL) {
        try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
    }
}

/// Counts the requests that a credential provider gets.
private actor CredentialRequestCounter {
    /// The number of requests.
    private(set) var count = 0

    /// Counts one request.
    func recordRequest() {
        count += 1
    }

    /// Makes a provider that counts each request and gives `credential`.
    ///
    /// - Parameter credential: The credential that the provider gives.
    /// - Returns: The provider.
    nonisolated func provider(giving credential: MarketplaceCredential) -> @Sendable (URL) async -> MarketplaceCredential? {
        { _ in
            await self.recordRequest()
            return credential
        }
    }
}
