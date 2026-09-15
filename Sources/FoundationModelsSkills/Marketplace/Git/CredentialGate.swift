import Foundation

/// Decides which libgit2 credential request gets the credential of one HTTPS
/// source (marketplace.md §5.1).
///
/// The gate holds at most one credential, and gives it one time. It gives it
/// only to a request whose URL has the same scheme, host, and port as the
/// source URL. The scheme and the host are compared without letter case, and
/// a port that the URL does not write is the default port of HTTPS.
///
/// libgit2 asks again only when the server refused the last credential. Thus a
/// second request means a bad token: the gate refuses it, and libgit2 stops
/// instead of a loop. Each refusal sets ``hasRefused``.
///
/// Only an HTTPS source has an origin. An SSH source uses the exec transport,
/// and a `file://` or plain `http://` source must not get a token. For such a
/// source the gate never asks the host, and it refuses each request.
///
/// The gate is a pure value, thus a test needs no server. ``LibGit2Transport``
/// keeps one gate for each call and lends it to the libgit2 `credentials`
/// callback.
internal struct CredentialGate: Sendable {
    /// The scheme, the host, and the port of a URL.
    private struct Origin: Equatable, Sendable {
        /// The scheme, in lowercase.
        let scheme: String

        /// The host, in lowercase.
        let host: String

        /// The port that the URL writes, else the default port of HTTPS for
        /// an HTTPS URL, else `nil`.
        let port: Int?

        /// Parses the origin of a URL.
        ///
        /// - Parameter url: The URL text.
        /// - Returns: The origin, or `nil` when the text has no scheme or no
        ///   host.
        init?(url: String) {
            guard let components = URLComponents(string: url),
                let scheme = components.scheme?.lowercased(),
                let host = components.host?.lowercased(), !host.isEmpty
            else {
                return nil
            }
            self.scheme = scheme
            self.host = host
            self.port = components.port ?? (scheme == CredentialGate.httpsScheme ? CredentialGate.httpsDefaultPort : nil)
        }
    }

    /// The only scheme that gets a credential.
    private static let httpsScheme = "https"

    /// The port of an HTTPS URL that writes no port.
    private static let httpsDefaultPort = 443

    /// The origin of the source, or `nil` for a source that is not HTTPS.
    private let origin: Origin?

    /// The credential, until the gate gives it.
    private var credential: MarketplaceCredential?

    /// Whether the gate refused a request. A libgit2 stop after a refusal is
    /// an authentication failure, not a cancel.
    private(set) var hasRefused = false

    /// Makes a gate that already holds its credential.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL of the marketplace source.
    ///   - credential: The credential for the source, or `nil` for none. A
    ///     source that is not HTTPS keeps no credential.
    init(sourceURL: String, credential: MarketplaceCredential?) {
        let origin = Origin(url: sourceURL).flatMap { $0.scheme == Self.httpsScheme ? $0 : nil }
        self.origin = origin
        self.credential = origin == nil ? nil : credential
    }

    /// Makes the gate for one git call, and asks the host for the credential
    /// before the call starts.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL of the marketplace source.
    ///   - credentials: Gives the credential for a source URL, or `nil` when
    ///     the host gives no credentials.
    /// - Returns: The gate. The host is asked one time, and only for an HTTPS
    ///   source.
    static func resolved(
        forSourceURL sourceURL: String, credentials: (@Sendable (URL) async -> MarketplaceCredential?)?
    ) async -> CredentialGate {
        let empty = CredentialGate(sourceURL: sourceURL, credential: nil)
        guard empty.origin != nil, let credentials, let url = URL(string: sourceURL) else {
            return empty
        }
        return CredentialGate(sourceURL: sourceURL, credential: await credentials(url))
    }

    /// Gives the credential for one libgit2 request.
    ///
    /// - Parameter requestURL: The URL that libgit2 asks for.
    /// - Returns: The credential for the first request from the origin of the
    ///   source. Every other request gets `nil` and sets ``hasRefused``.
    mutating func credential(forRequestURL requestURL: String) -> MarketplaceCredential? {
        guard let origin, Origin(url: requestURL) == origin, let given = credential.take() else {
            hasRefused = true
            return nil
        }
        return given
    }
}
