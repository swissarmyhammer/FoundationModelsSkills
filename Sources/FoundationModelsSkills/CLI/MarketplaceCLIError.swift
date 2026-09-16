/// Why a `marketplace` command cannot do its work (marketplace.md §9.2).
///
/// No message holds a URL or a credential: it names only the id that the user
/// gave.
internal enum MarketplaceCLIError: Error, Equatable, Sendable {
    /// The user configuration already has a marketplace with this pre-fetch
    /// key. Two sources with the same key make the store refuse the whole
    /// list, thus `add` stops before it writes (marketplace.md §5.3).
    ///
    /// - Parameter key: The pre-fetch key of the new source.
    case duplicateMarketplace(key: String)

    /// The configuration stack has no user layer, thus `add` and `remove`
    /// have no file to write.
    case noUserLayer
}

extension MarketplaceCLIError: CustomStringConvertible {
    /// A sentence that tells the problem and, when possible, the correction.
    var description: String {
        switch self {
        case .duplicateMarketplace(let key):
            #"""
            A marketplace with the id "\#(key)" is already in the user configuration. Give the new marketplace another alias.
            """#
        case .noUserLayer:
            "The configuration stack has no user layer, thus the command cannot write marketplaces.yaml."
        }
    }
}
