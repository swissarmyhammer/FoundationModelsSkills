import Foundation

/// The git operations that the marketplace store needs (marketplace.md §5.1,
/// decision 10).
///
/// The package never starts the `git` binary. ``LibGit2Transport`` does this
/// work with libgit2. The protocol is internal: the store gets a
/// `GitTransport` value, and a store test gives a counting double instead
/// (marketplace.md §13). A change of the libgit2 package changes only the
/// concrete type.
///
/// No implementation has a built-in timeout. A call stops when its task is
/// cancelled, and it then throws ``GitTransportError/cancelled``.
internal protocol GitTransport: Sendable {
    /// Reads the commit that `ref` names on the remote, with no download of
    /// content (the `ls-remote` equivalent).
    ///
    /// - Parameters:
    ///   - url: The git URL of the remote.
    ///   - ref: A branch name, a tag name, or `HEAD`. A branch wins over a tag
    ///     with the same name. An annotated tag gives the commit that it peels
    ///     to.
    /// - Returns: The 40-hex SHA of the commit.
    /// - Throws: ``GitTransportError``.
    func remoteHead(url: String, ref: String) async throws -> String

    /// Fetches one commit into a bare repository, as a shallow fetch.
    ///
    /// - Parameters:
    ///   - url: The git URL of the remote.
    ///   - revision: A 40-hex SHA, or a ref name in the form that
    ///     ``remoteHead(url:ref:)`` takes.
    ///   - repositoryURL: The directory of the bare repository. The call makes
    ///     the repository when it does not exist.
    /// - Returns: The 40-hex SHA of the fetched commit.
    /// - Throws: ``GitTransportError``.
    func fetch(url: String, revision: String, intoBareRepository repositoryURL: URL) async throws -> String
}

/// Why a ``GitTransport`` call failed.
internal enum GitTransportError: Error, Equatable, Sendable {
    /// The remote cannot be reached: the host, the network, the
    /// authentication, or the path failed before the remote listed its refs.
    case unreachable

    /// The remote has no ref or object with the requested name.
    case refNotFound

    /// The task of the call was cancelled, and the call stopped.
    case cancelled

    /// The network or the server stopped the operation with a timeout. The
    /// transport has no timeout of its own.
    case timedOut

    /// Another libgit2 failure, with its code and message.
    case libgit2(code: Int32, message: String)
}
