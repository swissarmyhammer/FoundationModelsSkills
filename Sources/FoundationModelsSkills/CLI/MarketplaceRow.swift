import Foundation

/// What the configuration and the cache know about one marketplace, as
/// `marketplace list` shows it (marketplace.md §9.2).
///
/// A row holds no URL that did not parse. A URL with a credential in it is no
/// §5.1 form, thus it never parses, thus a row can never show a credential.
internal struct MarketplaceRow: Sendable {
    /// The text that a column shows when it has no value.
    static let emptyValue = "-"

    /// The status of a marketplace that has no snapshot yet.
    static let notInstalledStatus = "not installed"

    /// The status of a marketplace that holds one commit
    /// (marketplace.md §8.3).
    static let pinnedStatus = "pinned"

    /// The status of a marketplace that is a folder on this computer. The
    /// folder is the layer itself, thus it has no snapshot and no commit
    /// (marketplace.md §5.1).
    static let localStatus = "local folder"

    /// The status of a marketplace that the cache serves.
    static let readyStatus = "ready"

    /// The heading of each column of `marketplace list`.
    static let headings = ["ID", "URL", "CURRENT", "CATALOG", "CHECKED", "STATUS"]

    /// The display id: the `name` field of the catalog of the snapshot that
    /// the cache serves, else the pre-fetch key, else the alias of the
    /// source (marketplace.md §5.3).
    let id: String

    /// The pre-fetch key, or `nil` when the source gives none.
    let key: String?

    /// The normalized URL, or `nil` when the URL is no §5.1 form.
    let url: String?

    /// The commit of the snapshot that the cache serves, or `nil` before the
    /// first install.
    let currentSha: String?

    /// The `version` field of the catalog of that snapshot, or `nil` when the
    /// catalog has none.
    let catalogVersion: String?

    /// When the store last asked the remote for its head, or `nil` when it
    /// never asked.
    let lastChecked: Date?

    /// What the row says about the marketplace.
    let status: String

    /// Whether one id names this marketplace.
    ///
    /// The store answers to the pre-fetch key and to the display id, thus a
    /// row does too.
    ///
    /// - Parameter other: The id that the user gave.
    /// - Returns: `true` when the id names this marketplace.
    func names(_ other: String) -> Bool {
        other == id || other == key
    }

    /// The cells of this row, in the order of ``headings``.
    var cells: [String] {
        [
            id,
            url ?? Self.emptyValue,
            currentSha ?? Self.emptyValue,
            catalogVersion ?? Self.emptyValue,
            lastChecked.map { $0.formatted(.iso8601) } ?? Self.emptyValue,
            status,
        ]
    }

    /// Reads one row for each source of a configuration.
    ///
    /// The call reads `state.json` one time and opens no connection, thus
    /// `marketplace list` does no network work at all.
    ///
    /// - Parameters:
    ///   - sources: The marketplace sources, in list order.
    ///   - cacheDirectory: The cache folder that holds `state.json`.
    /// - Returns: One row for each source, in list order.
    static func rows(of sources: [MarketplaceSource], cacheDirectory: URL) -> [MarketplaceRow] {
        let stateFile = MarketplaceCache.stateFile(inCacheDirectory: cacheDirectory)
        let state = (try? MarketplaceState.load(from: stateFile)) ?? MarketplaceState()
        return sources.map { row(of: $0, state: state) }
    }

    /// Reads the row of one source.
    ///
    /// - Parameters:
    ///   - source: The source.
    ///   - state: The state file of the cache folder.
    /// - Returns: The row. A source that gives no location and no key gets a
    ///   row whose status tells why.
    private static func row(of source: MarketplaceSource, state: MarketplaceState) -> MarketplaceRow {
        do {
            return row(
                of: source, location: try MarketplaceLocation(source: source),
                key: try MarketplaceIdentity.preFetchKey(for: source), state: state)
        } catch {
            return MarketplaceRow(
                id: source.alias ?? emptyValue, key: source.alias, url: nil, currentSha: nil,
                catalogVersion: nil, lastChecked: nil, status: String(describing: error))
        }
    }

    /// Reads the row of one source that gives a location and a key.
    ///
    /// - Parameters:
    ///   - source: The source.
    ///   - location: The location of the source.
    ///   - key: The pre-fetch key of the source.
    ///   - state: The state file of the cache folder.
    /// - Returns: The row.
    private static func row(
        of source: MarketplaceSource, location: MarketplaceLocation, key: String,
        state: MarketplaceState
    ) -> MarketplaceRow {
        guard case .git = location else {
            return MarketplaceRow(
                id: key, key: key, url: location.normalizedURL, currentSha: nil,
                catalogVersion: nil, lastChecked: nil, status: localStatus)
        }
        let folder = MarketplaceIdentity.cacheFolderName(
            key: key, normalizedURL: location.normalizedURL)
        let record = state.marketplaces[folder]
        return MarketplaceRow(
            id: record?.displayID ?? key,
            key: key,
            url: location.normalizedURL,
            currentSha: record?.currentSha,
            catalogVersion: record?.catalogVersion,
            lastChecked: record?.lastChecked,
            status: status(ofRecord: record, source: source))
    }

    /// What the row says about one git marketplace.
    ///
    /// - Parameters:
    ///   - record: The record of the marketplace in `state.json`, or `nil`
    ///     when the cache holds none.
    ///   - source: The source of the marketplace.
    /// - Returns: The message of the last failure, else the status text.
    private static func status(ofRecord record: MarketplaceStateRecord?, source: MarketplaceSource)
        -> String
    {
        if let lastError = record?.lastError {
            return lastError
        }
        guard record?.currentSha != nil else {
            return notInstalledStatus
        }
        return holdsOneCommit(record: record, source: source) ? pinnedStatus : readyStatus
    }

    /// Whether one marketplace holds one commit (marketplace.md §8.3).
    ///
    /// The pin of the user wins over the `sha` field of the source, and an
    /// unpin beats that field too.
    ///
    /// - Parameters:
    ///   - record: The record of the marketplace in `state.json`, or `nil`.
    ///   - source: The source of the marketplace.
    /// - Returns: `true` when the marketplace never moves to the remote head.
    private static func holdsOneCommit(record: MarketplaceStateRecord?, source: MarketplaceSource)
        -> Bool
    {
        if record?.pinnedSha != nil {
            return true
        }
        if record?.unpinned == true {
            return false
        }
        return source.isPinned
    }
}
