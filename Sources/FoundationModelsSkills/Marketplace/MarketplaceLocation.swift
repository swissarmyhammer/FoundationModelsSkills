import Foundation

/// Where a marketplace comes from, parsed from ``MarketplaceSource/url``
/// (marketplace.md §5.1).
///
/// The forms are:
/// - scp-like SSH: `git@github.com:owner/repo.git`
/// - HTTPS: `https://github.com/owner/repo.git`
/// - the GitHub shorthand `github:owner/repo`, which expands to
///   `https://github.com/owner/repo.git`
/// - a `#ref` suffix on each git form
/// - a local folder: `file:///Users/me/skills`
///
/// A git form must end in `.git`. Thus a later HTTPS `marketplace.json` form
/// cannot be read as a git repository. The scheme and the host are not case
/// sensitive; the parser writes both in lowercase.
internal enum MarketplaceLocation: Sendable, Hashable {
    /// A git repository.
    ///
    /// `url` is the normalized URL: the shorthand is expanded, the host is in
    /// lowercase, and there is no trailing `/` and no `#ref` suffix. `ref` is
    /// the revision to fetch: the `sha` field, else the `ref` field, else the
    /// `#ref` suffix. It is `nil` for the remote `HEAD`.
    case git(url: String, ref: String?)

    /// A local folder that the store reads directly.
    case local(URL)

    /// The character between a git URL and its ref.
    private static let refSeparator: Character = "#"

    /// The text between a scheme and the rest of a URL.
    private static let schemeSeparator = "://"

    /// The scheme of an HTTPS git URL.
    private static let httpsScheme = "https"

    /// The scheme of a local folder URL.
    private static let fileScheme = "file"

    /// The host name that a `file://` URL can have.
    private static let localHostName = "localhost"

    /// The prefix of the GitHub shorthand, in lowercase.
    private static let githubShorthandPrefix = "github:"

    /// The start of the HTTPS URL that the GitHub shorthand expands to.
    private static let githubRepositoryBase = "https://github.com/"

    /// The number of path components in the GitHub shorthand: the owner and
    /// the repository.
    private static let githubShorthandComponentCount = 2

    /// The suffix of a git repository path.
    private static let gitSuffix = ".git"

    /// The character between the host and the path of an scp-like URL.
    private static let scpPathSeparator: Character = ":"

    /// The character between the user and the host of an scp-like URL.
    private static let userSeparator: Character = "@"

    /// The character between the components of a path.
    private static let pathSeparator: Character = "/"

    /// Parses the location of `source`.
    ///
    /// - Parameter source: The source to parse. Its `sha` field wins over its
    ///   `ref` field, and its `ref` field wins over a `#ref` suffix.
    /// - Throws: ``MarketplaceSourceError`` when the URL is not a §5.1 form,
    ///   or when a local folder has a ref.
    init(source: MarketplaceSource) throws {
        guard !source.url.isEmpty else {
            throw MarketplaceSourceError.emptyURL
        }
        let (address, suffixRef) = try Self.splitRef(source.url)
        let ref = source.sha ?? source.ref ?? suffixRef
        guard ref?.isEmpty != true else {
            throw MarketplaceSourceError.emptyRef
        }
        if Self.scheme(of: address) == Self.fileScheme {
            guard ref == nil else {
                throw MarketplaceSourceError.refOnLocalFolder
            }
            self = .local(try Self.localFolder(address))
        } else {
            self = .git(url: try Self.gitURL(address), ref: ref)
        }
    }

    /// The normalized URL: the git URL with no ref, or `file://` and the
    /// folder path with no trailing `/`.
    var normalizedURL: String {
        switch self {
        case .git(let url, _): url
        case .local(let folder): "\(Self.fileScheme)\(Self.schemeSeparator)\(folder.path)"
        }
    }

    /// The last path component of the repository or of the folder, without
    /// `.git`.
    var repositoryName: String {
        switch self {
        case .git(let url, _): Self.repositoryName(inPath: url)
        case .local(let folder): folder.lastPathComponent
        }
    }

    // MARK: - Parts of a URL

    /// Splits a `#ref` suffix from `text`.
    ///
    /// - Parameter text: The URL text.
    /// - Returns: The text before the first `#`, and the ref after it, or
    ///   `nil` when there is no `#`.
    /// - Throws: ``MarketplaceSourceError/emptyRef`` when the `#` has no text
    ///   after it.
    private static func splitRef(_ text: String) throws -> (address: String, ref: String?) {
        guard let separator = text.firstIndex(of: refSeparator) else {
            return (text, nil)
        }
        let ref = String(text[text.index(after: separator)...])
        guard !ref.isEmpty else {
            throw MarketplaceSourceError.emptyRef
        }
        return (String(text[..<separator]), ref)
    }

    /// The scheme of `address` in lowercase, or `nil` when it has no `://`.
    ///
    /// - Parameter address: The URL text with no ref.
    /// - Returns: The scheme, or `nil`.
    private static func scheme(of address: String) -> String? {
        address.range(of: schemeSeparator).map { address[..<$0.lowerBound].lowercased() }
    }

    /// The last path component of `path`, without `.git`.
    ///
    /// - Parameter path: A repository path or a full git URL. Both `/` and
    ///   `:` end a component, thus an scp-like URL gives its repository name.
    /// - Returns: The repository name. It is empty when the path has none.
    private static func repositoryName(inPath path: String) -> String {
        let lastComponent = path.split { $0 == pathSeparator || $0 == scpPathSeparator }.last ?? ""
        return String(removingGitSuffix(lastComponent))
    }

    /// Removes one `.git` suffix from `name`.
    ///
    /// - Parameter name: A repository name.
    /// - Returns: The name without the suffix.
    private static func removingGitSuffix(_ name: Substring) -> Substring {
        name.hasSuffix(gitSuffix) ? name.dropLast(gitSuffix.count) : name
    }

    /// Removes the trailing `/` characters of a repository path, and checks
    /// that the path names a repository that ends in `.git`.
    ///
    /// - Parameter path: The path part of a git URL.
    /// - Returns: The path with no trailing `/`.
    /// - Throws: ``MarketplaceSourceError/missingRepository`` or
    ///   ``MarketplaceSourceError/missingGitSuffix``.
    private static func repositoryPath(_ path: String) throws -> String {
        let trimmed = String(path.reversed().drop { $0 == pathSeparator }.reversed())
        guard !repositoryName(inPath: trimmed).isEmpty else {
            throw MarketplaceSourceError.missingRepository
        }
        guard trimmed.hasSuffix(gitSuffix) else {
            throw MarketplaceSourceError.missingGitSuffix
        }
        return trimmed
    }

    // MARK: - Forms

    /// Parses a git form into its normalized URL.
    ///
    /// - Parameter address: The URL text with no ref.
    /// - Returns: The normalized git URL.
    /// - Throws: ``MarketplaceSourceError``.
    private static func gitURL(_ address: String) throws -> String {
        if let scheme = scheme(of: address) {
            guard scheme == httpsScheme else {
                throw MarketplaceSourceError.unsupportedForm
            }
            return try httpsURL(address)
        }
        if address.lowercased().hasPrefix(githubShorthandPrefix) {
            return try githubURL(repository: address.dropFirst(githubShorthandPrefix.count))
        }
        return try scpURL(address)
    }

    /// Parses an HTTPS git URL.
    ///
    /// - Parameter address: The URL text with no ref.
    /// - Returns: The URL with the scheme and the host in lowercase and no
    ///   trailing `/`.
    /// - Throws: ``MarketplaceSourceError``.
    private static func httpsURL(_ address: String) throws -> String {
        guard var components = URLComponents(string: address) else {
            throw MarketplaceSourceError.unsupportedForm
        }
        guard let host = components.host, !host.isEmpty else {
            throw MarketplaceSourceError.missingHost
        }
        guard components.user == nil, components.password == nil else {
            throw MarketplaceSourceError.credentialsInURL
        }
        components.scheme = httpsScheme
        components.host = host.lowercased()
        components.path = try repositoryPath(components.path)
        guard let url = components.string else {
            throw MarketplaceSourceError.unsupportedForm
        }
        return url
    }

    /// Expands the GitHub shorthand.
    ///
    /// - Parameter repository: The text after `github:`, `owner/repo`. A
    ///   `.git` suffix is permitted.
    /// - Returns: `https://github.com/owner/repo.git`.
    /// - Throws: ``MarketplaceSourceError/invalidShorthand``.
    private static func githubURL(repository: Substring) throws -> String {
        let components = repository.split(separator: pathSeparator, omittingEmptySubsequences: false)
        guard components.count == githubShorthandComponentCount,
            let owner = components.first, !owner.isEmpty,
            let name = components.last.map(removingGitSuffix), !name.isEmpty
        else {
            throw MarketplaceSourceError.invalidShorthand
        }
        return "\(githubRepositoryBase)\(owner)\(pathSeparator)\(name)\(gitSuffix)"
    }

    /// Parses an scp-like SSH URL, `[user@]host:path`.
    ///
    /// - Parameter address: The URL text with no ref.
    /// - Returns: The URL with the host in lowercase and no trailing `/`.
    /// - Throws: ``MarketplaceSourceError``.
    private static func scpURL(_ address: String) throws -> String {
        guard let colon = address.firstIndex(of: scpPathSeparator),
            !address[..<colon].contains(pathSeparator)
        else {
            throw MarketplaceSourceError.unsupportedForm
        }
        let authority = address[..<colon]
        let hostStart = authority.lastIndex(of: userSeparator).map { authority.index(after: $0) } ?? authority.startIndex
        let host = authority[hostStart...]
        guard !host.isEmpty else {
            throw MarketplaceSourceError.missingHost
        }
        let path = try repositoryPath(String(address[address.index(after: colon)...]))
        return "\(authority[..<hostStart])\(host.lowercased())\(scpPathSeparator)\(path)"
    }

    /// Parses a `file://` URL into a folder URL.
    ///
    /// - Parameter address: The URL text.
    /// - Returns: The standardized folder URL.
    /// - Throws: ``MarketplaceSourceError/invalidLocalPath`` when the URL has
    ///   a remote host or no absolute path.
    private static func localFolder(_ address: String) throws -> URL {
        guard let url = URL(string: address),
            isLocalHost(url.host),
            url.path.first == pathSeparator
        else {
            throw MarketplaceSourceError.invalidLocalPath
        }
        return URL(fileURLWithPath: url.path, isDirectory: true).standardizedFileURL
    }

    /// Tells whether `host` names this computer: no host, an empty host, or
    /// `localhost`.
    ///
    /// - Parameter host: The host of a `file://` URL.
    /// - Returns: `true` for a local host.
    private static func isLocalHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else {
            return true
        }
        return host.lowercased() == localHostName
    }
}
