import Foundation

/// What a host lets a ``MarketplaceStore`` do (marketplace.md §6.7, §7.3
/// step 4, and §8.2).
///
/// Every field is a count or a host value. The package names no interval, no
/// jitter, and no age limit of its own: a check runs at `start()` and on
/// request, a periodic check runs only when the host gives
/// ``checkInterval``, a fetch stops early only when the host gives
/// ``fetchTimeout``, and cleanup counts snapshots (decision 13).
///
/// ```swift
/// let policy = MarketplacePolicy(credentials: { url in
///     url.host == "git.example.com" ? MarketplaceCredential(username: "reader", token: token) : nil
/// })
/// ```
public struct MarketplacePolicy: Sendable {
    /// The name of the environment variable that stops every automatic
    /// update (marketplace.md §8.3).
    public static let automaticUpdateVariable = "SKILLS_MARKETPLACE_AUTOUPDATE"

    /// The value of ``automaticUpdateVariable`` that stops every automatic
    /// update.
    private static let automaticUpdateOffValue = "0"

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

    /// How long the store waits between two periodic checks, or `nil` for no
    /// periodic check.
    ///
    /// The package has no interval of its own. With `nil`, the store checks
    /// at `start()` and on request, and never again by itself. A long-running
    /// host, such as an agent server or an editor, gives a value here; a
    /// short command-line run does not need one (marketplace.md §8.2).
    public var checkInterval: Duration?

    /// Whether a check that finds a new commit also installs it.
    ///
    /// With `false`, the store publishes
    /// ``MarketplaceEvent/updateAvailable(id:from:to:)`` and fetches nothing.
    /// The host or the command line then asks for the update
    /// (marketplace.md §8.3).
    public var autoUpdate: Bool

    /// Whether the store only reports, and never installs.
    ///
    /// With `true`, every update request becomes a check: the store reads the
    /// remote head, publishes what it found, and downloads no content. This
    /// is the dry run of marketplace.md §8.3.
    public var checkOnly: Bool

    /// How long one fetch may take, or `nil` for no limit.
    ///
    /// The package has no timeout of its own. With a value, a fetch that
    /// takes longer is cancelled, and the store publishes
    /// ``MarketplaceEvent/failed(id:error:keptVersion:)`` and keeps the
    /// snapshot that `current` names (marketplace.md §5.1).
    public var fetchTimeout: Duration?

    /// Creates a policy.
    ///
    /// - Parameters:
    ///   - snapshotLimits: The size and the file count that one snapshot may
    ///     reach. The default is ``SnapshotLimits/init(maxBytes:maxFiles:)``
    ///     with its own defaults.
    ///   - credentials: Gives the credential of a private HTTPS source. The
    ///     default is `nil`: no credential.
    ///   - checkInterval: How long the store waits between two periodic
    ///     checks. The default is `nil`: no periodic check.
    ///   - autoUpdate: Whether a check that finds a new commit also installs
    ///     it. The default is `true`.
    ///   - checkOnly: Whether the store only reports. The default is `false`.
    ///   - fetchTimeout: How long one fetch may take. The default is `nil`:
    ///     no limit.
    ///   - environment: The environment to read. `SKILLS_MARKETPLACE_AUTOUPDATE=0`
    ///     there has the same effect as `autoUpdate: false`. The default is
    ///     the environment of this process.
    public init(
        snapshotLimits: SnapshotLimits = SnapshotLimits(),
        credentials: (@Sendable (URL) async -> MarketplaceCredential?)? = nil,
        checkInterval: Duration? = nil,
        autoUpdate: Bool = true,
        checkOnly: Bool = false,
        fetchTimeout: Duration? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.snapshotLimits = snapshotLimits
        self.credentials = credentials
        self.checkInterval = checkInterval
        self.autoUpdate = autoUpdate && Self.automaticUpdatesAllowed(environment: environment)
        self.checkOnly = checkOnly
        self.fetchTimeout = fetchTimeout
    }

    /// Whether an environment lets the store update by itself
    /// (marketplace.md §8.3).
    ///
    /// The call is a pure function of the environment, thus a test gives its
    /// own.
    ///
    /// - Parameter environment: The environment to read. The default is the
    ///   environment of this process.
    /// - Returns: `false` when ``automaticUpdateVariable`` is `0`, else
    ///   `true`.
    public static func automaticUpdatesAllowed(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[automaticUpdateVariable] != automaticUpdateOffValue
    }
}
