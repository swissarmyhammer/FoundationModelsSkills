/// Why a `marketplace` command cannot do its work.
///
/// No message holds a URL or a credential: it names only the id that the user
/// gave.
internal enum MarketplaceCLIError: Error, Equatable, Sendable {
    /// The user configuration already has a marketplace with this pre-fetch
    /// key. Two sources with the same key make the store refuse the whole
    /// list, thus `add` stops before it writes.
    ///
    /// - Parameter key: The pre-fetch key of the new source.
    case duplicateMarketplace(key: String)

    /// The configuration stack has no user layer, thus `add` and `remove`
    /// have no file to write.
    case noUserLayer

    /// The URL of the new source is of no supported form, thus the reader
    /// gave it no pre-fetch key.
    ///
    /// - Parameter reason: The message of the reader, which never holds a
    ///   URL and never holds a credential, or `nil` when the reader gave no
    ///   message.
    case unusableSource(reason: String?)
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
        case .unusableSource(let reason):
            reason ?? Self.unusableSourceText
        }
    }

    /// What ``unusableSource(reason:)`` says when the reader gave no message.
    ///
    /// The sentence names the supported forms, thus a user who wrote an SSH
    /// URL or a URL with a credential in it reads what to write instead.
    private static let unusableSourceText = """
        The URL of the marketplace is of no supported form. Write \
        https://host/owner/repo.git, github:owner/repo, or file:///path, and put no credential \
        in the URL.
        """
}
