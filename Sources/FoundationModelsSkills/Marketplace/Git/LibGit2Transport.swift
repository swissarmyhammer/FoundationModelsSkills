import Foundation
import libgit2

/// The libgit2 ``GitTransport`` (marketplace.md §5.1).
///
/// libgit2 builds from source as a SwiftPM target. HTTPS uses the system trust
/// store. SSH uses the libgit2 exec transport, which runs the system OpenSSH.
/// No call starts the `git` binary, runs a hook, or fetches a submodule.
///
/// Each call runs libgit2 on the thread of its task. The `transfer_progress`
/// and `sideband_progress` callbacks read `Task.isCancelled`, and stop libgit2
/// when the task is cancelled. There is no built-in timeout.
internal struct LibGit2Transport: GitTransport {
    /// The step in which a libgit2 call failed. The step decides which
    /// ``GitTransportError`` the failure becomes.
    internal enum Phase: Sendable, CaseIterable {
        /// Making the remote, connecting to it, or listing its refs.
        case connecting

        /// Downloading objects from a connected remote.
        case fetching

        /// Work on the local bare repository.
        case localRepository
    }

    /// The depth of a shallow fetch: the tip commit only.
    internal static let shallowDepth: Int32 = 1

    /// The depth that asks for the full history (`GIT_FETCH_DEPTH_FULL`).
    internal static let fullDepth = Int32(GIT_FETCH_DEPTH_FULL.rawValue)

    /// The number of hex digits in a SHA-1 object id.
    private static let objectIDHexLength = 40

    /// The ref name that names the default branch of a remote.
    private static let headReference = "HEAD"

    /// The suffix of an advertised ref that gives the commit an annotated tag
    /// peels to.
    private static let peeledSuffix = "^{}"

    /// The `is_bare` flag value that makes `git_repository_init` write a bare
    /// repository.
    private static let bareRepositoryFlag: UInt32 = 1

    /// The value that a progress callback returns to let libgit2 continue.
    private static let continueTransfer: Int32 = 0

    /// Starts libgit2 one time for the process. The value is the start count,
    /// or a negative libgit2 error code.
    private static let libraryStartCount: Int32 = git_libgit2_init()

    internal func remoteHead(url: String, ref: String) async throws -> String {
        try Self.check(Self.libraryStartCount, phase: .localRepository)
        var remote: OpaquePointer?
        try Self.check(git_remote_create_detached(&remote, url), phase: .connecting)
        defer { git_remote_free(remote) }
        try Self.connect(remote)
        return try Self.matchingHead(for: ref, in: Self.advertisedHeads(of: remote)).objectID
    }

    internal func fetch(url: String, revision: String, intoBareRepository repositoryURL: URL) async throws -> String {
        try Self.check(Self.libraryStartCount, phase: .localRepository)
        let repository = try Self.openOrCreateBareRepository(at: repositoryURL)
        defer { git_repository_free(repository) }
        var remote: OpaquePointer?
        try Self.check(git_remote_create_anonymous(&remote, repository, url), phase: .connecting)
        defer { git_remote_free(remote) }
        try Self.connect(remote)
        let target = try Self.fetchTarget(for: revision, in: Self.advertisedHeads(of: remote))
        try Self.check(
            Self.fetchShallowFirst { depth in Self.fetch(refspec: target.refspec, from: remote, depth: depth) },
            phase: .fetching)
        return try Self.commitID(peeling: target.objectID, in: repository)
    }

    // MARK: - Shallow fetch

    /// Runs `attempt` with ``shallowDepth``. When libgit2 gives
    /// `GIT_ENOTSUPPORTED`, runs `attempt` one more time with ``fullDepth``.
    ///
    /// The libgit2 local transport (a `file://` URL or a path) refuses a
    /// shallow fetch with `GIT_ENOTSUPPORTED`. Every other status, a success
    /// included, is the result, with no second attempt.
    ///
    /// - Parameter attempt: One fetch at the depth it gets. It returns the
    ///   libgit2 status.
    /// - Returns: The status of the last attempt.
    internal static func fetchShallowFirst(_ attempt: (_ depth: Int32) -> Int32) -> Int32 {
        let shallowStatus = attempt(shallowDepth)
        if shallowStatus == GIT_ENOTSUPPORTED.rawValue {
            return attempt(fullDepth)
        }
        return shallowStatus
    }

    /// Fetches `refspec` from the connected `remote` at `depth`.
    ///
    /// Tags are not followed, thus only the objects of `refspec` arrive.
    ///
    /// - Returns: The libgit2 status.
    private static func fetch(refspec: String, from remote: OpaquePointer?, depth: Int32) -> Int32 {
        var options = git_fetch_options()
        let initialized = git_fetch_options_init(&options, UInt32(GIT_FETCH_OPTIONS_VERSION))
        if initialized < GIT_OK.rawValue {
            return initialized
        }
        options.callbacks = progressCallbacks()
        options.depth = depth
        options.download_tags = GIT_REMOTE_DOWNLOAD_TAGS_NONE
        return withStringArray(holding: refspec) { refspecs in
            git_remote_fetch(remote, refspecs, &options, nil)
        }
    }

    // MARK: - Remote refs

    /// One ref that a remote advertises.
    private struct AdvertisedHead {
        /// The full ref name, for example `refs/heads/main` or
        /// `refs/tags/v1.0.0^{}`.
        let name: String

        /// The 40-hex SHA of the object that the ref names.
        let objectID: String
    }

    /// What ``fetch(url:revision:intoBareRepository:)`` downloads.
    private struct FetchTarget {
        /// The refspec that names the object on the remote.
        let refspec: String

        /// The 40-hex SHA of the object.
        let objectID: String
    }

    /// Connects `remote` in the fetch direction, with the progress callbacks.
    private static func connect(_ remote: OpaquePointer?) throws {
        var callbacks = progressCallbacks()
        try check(git_remote_connect(remote, GIT_DIRECTION_FETCH, &callbacks, nil, nil), phase: .connecting)
    }

    /// Lists the refs that the connected `remote` advertises.
    private static func advertisedHeads(of remote: OpaquePointer?) throws -> [AdvertisedHead] {
        var heads: UnsafeMutablePointer<UnsafePointer<git_remote_head>?>?
        var count = 0
        try check(git_remote_ls(&heads, &count, remote), phase: .connecting)
        return UnsafeBufferPointer(start: heads, count: count).compactMap { head in
            head.map { AdvertisedHead(name: String(cString: $0.pointee.name), objectID: hex(of: $0.pointee.oid)) }
        }
    }

    /// Finds the advertised ref that `ref` names.
    ///
    /// The search order is `HEAD` (only for `HEAD` itself), then
    /// `refs/heads/<ref>`, then the peeled `refs/tags/<ref>^{}`, then
    /// `refs/tags/<ref>`. Thus a branch wins over a tag with the same name, and
    /// an annotated tag gives its commit.
    ///
    /// - Throws: ``GitTransportError/refNotFound`` when no advertised ref
    ///   matches.
    private static func matchingHead(for ref: String, in heads: [AdvertisedHead]) throws -> AdvertisedHead {
        let match = candidateNames(for: ref).lazy.compactMap { name in heads.first { $0.name == name } }.first
        if let match {
            return match
        }
        throw GitTransportError.refNotFound
    }

    /// The advertised ref names that `ref` can mean, in search order.
    private static func candidateNames(for ref: String) -> [String] {
        if ref == headReference {
            return [headReference]
        }
        return ["refs/heads/\(ref)", "refs/tags/\(ref)\(peeledSuffix)", "refs/tags/\(ref)"]
    }

    /// Decides what to download for `revision`.
    ///
    /// A 40-hex SHA is fetched by its object id. A ref name is fetched by the
    /// name of the advertised ref that it matches.
    private static func fetchTarget(for revision: String, in heads: [AdvertisedHead]) throws -> FetchTarget {
        if revision.count == objectIDHexLength, revision.allSatisfy(\.isHexDigit) {
            return FetchTarget(refspec: revision, objectID: revision)
        }
        let head = try matchingHead(for: revision, in: heads)
        let refspec = head.name.hasSuffix(peeledSuffix) ? String(head.name.dropLast(peeledSuffix.count)) : head.name
        return FetchTarget(refspec: refspec, objectID: head.objectID)
    }

    // MARK: - Local repository

    /// Opens the bare repository at `repositoryURL`, or makes it when it does
    /// not exist.
    ///
    /// - Returns: The repository. The caller frees it.
    private static func openOrCreateBareRepository(at repositoryURL: URL) throws -> OpaquePointer {
        var repository: OpaquePointer?
        if git_repository_open_bare(&repository, repositoryURL.path) < GIT_OK.rawValue {
            try check(git_repository_init(&repository, repositoryURL.path, bareRepositoryFlag), phase: .localRepository)
        }
        if let repository {
            return repository
        }
        throw GitTransportError.libgit2(code: GIT_ERROR.rawValue, message: lastErrorMessage())
    }

    /// Looks up `objectID` in `repository`, and peels it to a commit.
    ///
    /// - Returns: The 40-hex SHA of the commit.
    /// - Throws: ``GitTransportError/refNotFound`` when the fetch did not
    ///   bring the object.
    private static func commitID(peeling objectID: String, in repository: OpaquePointer) throws -> String {
        var target = git_oid()
        try check(git_oid_fromstr(&target, objectID), phase: .localRepository)
        var object: OpaquePointer?
        try check(git_object_lookup(&object, repository, &target, GIT_OBJECT_ANY), phase: .fetching)
        defer { git_object_free(object) }
        var commit: OpaquePointer?
        try check(git_object_peel(&commit, object, GIT_OBJECT_COMMIT), phase: .localRepository)
        defer { git_object_free(commit) }
        return hex(of: git_object_id(commit).pointee)
    }

    // MARK: - Callbacks

    /// The remote callbacks: each progress callback stops libgit2 when the
    /// current task is cancelled.
    private static func progressCallbacks() -> git_remote_callbacks {
        var callbacks = git_remote_callbacks()
        git_remote_init_callbacks(&callbacks, UInt32(GIT_REMOTE_CALLBACKS_VERSION))
        callbacks.transfer_progress = { _, _ in LibGit2Transport.progressVerdict() }
        callbacks.sideband_progress = { _, _, _ in LibGit2Transport.progressVerdict() }
        return callbacks
    }

    /// `GIT_EUSER` when the current task is cancelled, which stops libgit2,
    /// else ``continueTransfer``.
    private static func progressVerdict() -> Int32 {
        Task.isCancelled ? GIT_EUSER.rawValue : continueTransfer
    }

    // MARK: - Errors

    /// Maps a libgit2 failure to a ``GitTransportError``.
    ///
    /// `GIT_EUSER` comes only from a progress callback that stopped for a
    /// cancelled task, thus it is ``GitTransportError/cancelled`` in every
    /// phase. `GIT_TIMEOUT` is ``GitTransportError/timedOut`` in every phase.
    /// Any other failure while connecting is
    /// ``GitTransportError/unreachable``. A missing object while fetching is
    /// ``GitTransportError/refNotFound``.
    ///
    /// - Parameters:
    ///   - code: The negative libgit2 status.
    ///   - message: The message of the last libgit2 error.
    ///   - phase: The step that failed.
    /// - Returns: The error to throw.
    internal static func transportError(code: Int32, message: String, phase: Phase) -> GitTransportError {
        switch code {
        case GIT_EUSER.rawValue:
            .cancelled
        case GIT_TIMEOUT.rawValue:
            .timedOut
        default:
            phaseError(code: code, message: message, phase: phase)
        }
    }

    /// Maps a failure that is not a cancel and not a timeout, by its phase.
    private static func phaseError(code: Int32, message: String, phase: Phase) -> GitTransportError {
        switch phase {
        case .connecting:
            .unreachable
        case .fetching where code == GIT_ENOTFOUND.rawValue:
            .refNotFound
        case .fetching, .localRepository:
            .libgit2(code: code, message: message)
        }
    }

    /// Throws the mapped ``GitTransportError`` when `status` is a libgit2
    /// error code.
    private static func check(_ status: Int32, phase: Phase) throws {
        if status < GIT_OK.rawValue {
            throw transportError(code: status, message: lastErrorMessage(), phase: phase)
        }
    }

    /// The message of the last libgit2 error on this thread.
    private static func lastErrorMessage() -> String {
        if let error = git_error_last(), let message = error.pointee.message {
            return String(cString: message)
        }
        return ""
    }

    // MARK: - Conversions

    /// Formats `objectID` as 40 hex digits.
    private static func hex(of objectID: git_oid) -> String {
        var objectID = objectID
        return String(cString: git_oid_tostr_s(&objectID))
    }

    /// Gives `body` a one-element `git_strarray` that holds `string`.
    private static func withStringArray<Result>(
        holding string: String, _ body: (UnsafePointer<git_strarray>) -> Result
    ) -> Result {
        string.withCString { characters in
            var element: UnsafeMutablePointer<CChar>? = UnsafeMutablePointer(mutating: characters)
            return withUnsafeMutablePointer(to: &element) { strings in
                withUnsafePointer(to: git_strarray(strings: strings, count: 1)) { body($0) }
            }
        }
    }
}
