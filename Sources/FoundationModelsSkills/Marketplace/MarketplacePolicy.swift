import Foundation

/// What a host lets a ``MarketplaceStore`` do (marketplace.md §6.7 and §7.3
/// step 4).
///
/// Every field is a count or a host value. The policy names no interval and
/// no age limit: an update runs when the host asks for it, and cleanup counts
/// snapshots.
///
/// ```swift
/// let policy = MarketplacePolicy(credentials: { url in
///     url.host == "git.example.com" ? MarketplaceCredential(username: "reader", token: token) : nil
/// })
/// ```
public struct MarketplacePolicy: Sendable {
    /// The size and the file count that one snapshot may reach.
    public var snapshotLimits: SnapshotLimits

    /// Gives the credential of a private HTTPS source, or `nil` for a host
    /// that has none.
    ///
    /// The store hands the provider to the git transport. The transport asks
    /// it only for an HTTPS source, and it sends the credential only to the
    /// origin of that source. The credential never becomes part of a URL that
    /// the store writes or shows.
    public var credentials: (@Sendable (URL) async -> MarketplaceCredential?)?

    /// Creates a policy.
    ///
    /// - Parameters:
    ///   - snapshotLimits: The size and the file count that one snapshot may
    ///     reach. The default is ``SnapshotLimits/init(maxBytes:maxFiles:)``
    ///     with its own defaults.
    ///   - credentials: Gives the credential of a private HTTPS source. The
    ///     default is `nil`: no credential.
    public init(
        snapshotLimits: SnapshotLimits = SnapshotLimits(),
        credentials: (@Sendable (URL) async -> MarketplaceCredential?)? = nil
    ) {
        self.snapshotLimits = snapshotLimits
        self.credentials = credentials
    }
}
