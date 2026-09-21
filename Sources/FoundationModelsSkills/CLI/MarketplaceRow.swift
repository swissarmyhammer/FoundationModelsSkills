import Foundation
import Marketplace

/// What the configuration and the cache know about one marketplace, as
/// `marketplace list` shows it (marketplace.md §9.2).
///
/// One row wraps one ``MarketplaceListing`` of the `Marketplace` module, and
/// it adds what only a command line needs: the column headings, the status
/// word, and the test that tells whether an id names this marketplace.
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

    /// What the cache and the configuration know about this marketplace.
    let listing: MarketplaceListing

    /// The display id: the `name` field of the catalog of the snapshot that
    /// the cache serves, else the pre-fetch key, else the alias of the
    /// source (marketplace.md §5.3).
    ///
    /// A source that gives none of the three has the empty id in its
    /// listing, thus the row shows ``emptyValue`` in its place.
    var id: String {
        listing.id.isEmpty ? Self.emptyValue : listing.id
    }

    /// The pre-fetch key: the alias of the source, else the repository name
    /// without `.git`. It is `nil` when the URL of the source is of no
    /// supported form.
    var key: String? {
        listing.key
    }

    /// The message of the last failure, or `nil` when the last attempt was
    /// good. A source whose URL the parser refuses carries the message of
    /// the parser here.
    var lastError: String? {
        listing.lastError
    }

    /// What the row says about the marketplace.
    var status: String {
        if let lastError = listing.lastError {
            return lastError
        }
        if listing.isLocalFolder {
            return Self.localStatus
        }
        guard listing.currentSha != nil else {
            return Self.notInstalledStatus
        }
        return listing.holdsOneCommit ? Self.pinnedStatus : Self.readyStatus
    }

    /// Whether one id names this marketplace.
    ///
    /// The store answers to the pre-fetch key and to the display id, thus a
    /// row does too.
    ///
    /// - Parameter other: The id that the user gave.
    /// - Returns: `true` when the id names this marketplace.
    func names(_ other: String) -> Bool {
        other == listing.id || other == listing.key
    }

    /// The cells of this row, in the order of ``headings``.
    var cells: [String] {
        [
            id,
            listing.url ?? Self.emptyValue,
            listing.currentSha ?? Self.emptyValue,
            listing.catalogVersion ?? Self.emptyValue,
            listing.lastChecked.map { $0.formatted(.iso8601) } ?? Self.emptyValue,
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
        MarketplaceStore.listings(of: sources, cacheDirectory: cacheDirectory)
            .map { MarketplaceRow(listing: $0) }
    }
}
