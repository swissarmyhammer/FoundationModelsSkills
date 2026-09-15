/// What a ``MarketplaceStore`` did with one marketplace (marketplace.md
/// §6.2).
///
/// A host reads the events to show progress and to report a failure. The
/// registry does not read them: it follows
/// ``MarketplaceLayerProviding/layerUpdates`` instead.
///
/// No case carries a URL or a credential, thus an event that a log line shows
/// holds no secret.
public enum MarketplaceEvent: Sendable, Hashable {
    /// The store installed a new snapshot, and `current` now names it. The
    /// registry rebuilds its catalog.
    ///
    /// - Parameters:
    ///   - id: The display id of the marketplace.
    ///   - from: The commit of the snapshot before this one, or `nil` for a
    ///     cold start.
    ///   - to: The commit of the new snapshot.
    case updated(id: String, from: String?, to: String)

    /// The store could not bring the marketplace to its remote head. The last
    /// good snapshot stays in place (marketplace.md §7.5).
    ///
    /// - Parameters:
    ///   - id: The display id of the marketplace.
    ///   - error: The text of the failure. It never holds a credential.
    ///   - keptVersion: The commit of the snapshot that stays, or `nil` when
    ///     there is none yet.
    case failed(id: String, error: String, keptVersion: String?)
}
