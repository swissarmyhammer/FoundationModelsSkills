import Foundation
import Synchronization

/// One run of the `marketplace` command group: the folders that the
/// subcommands read, and the lines that they wrote
/// (marketplace.md §9.2).
///
/// ``MarketplaceCLI/run(arguments:context:)`` puts a session in ``current``
/// before it parses. Thus every subcommand of that run reads the same folders
/// and writes into the same list, and the call gives the text back instead of
/// printing it. A subcommand that a host runs inside its own command tree
/// finds no session there, and it writes each line to standard output.
///
/// Every stored property is an immutable `let` of a `Sendable` type: the
/// lines live inside a `Mutex`, which gives the class a plain `Sendable`
/// conformance that the compiler checks.
internal final class MarketplaceCLISession: Sendable {
    /// The line break that ends one line of the output.
    private static let lineBreak = "\n"

    /// The session of the run that is in progress, or `nil` outside a run.
    @TaskLocal static var current: MarketplaceCLISession?

    /// The session that a subcommand writes to: the session of the run,
    /// else a new session over the process environment that writes each line
    /// to standard output.
    static var active: MarketplaceCLISession {
        current ?? MarketplaceCLISession(context: MarketplaceCLIContext(), collectsLines: false)
    }

    /// Where the subcommands read their configuration and their cache.
    let context: MarketplaceCLIContext

    /// Whether ``write(_:)`` keeps a line for ``text()``, or writes it to
    /// standard output at once.
    private let collectsLines: Bool

    /// The lines that the subcommands wrote, in write order.
    private let lines = Mutex<[String]>([])

    /// Creates a session.
    ///
    /// - Parameters:
    ///   - context: Where the subcommands read their configuration and their
    ///     cache.
    ///   - collectsLines: Whether the session keeps the lines for ``text()``.
    ///     The default is `true`. With `false` each line goes to standard
    ///     output at once.
    init(context: MarketplaceCLIContext, collectsLines: Bool = true) {
        self.context = context
        self.collectsLines = collectsLines
    }

    // MARK: - Output

    /// Writes one line.
    ///
    /// - Parameter line: The line, with no line break at its end.
    func write(_ line: String) {
        guard collectsLines else {
            FileHandle.standardOutput.write(Data("\(line)\(Self.lineBreak)".utf8))
            return
        }
        lines.withLock { $0.append(line) }
    }

    /// Writes each line of a list.
    ///
    /// - Parameter newLines: The lines, each one with no line break at its
    ///   end.
    func write(lines newLines: [String]) {
        for line in newLines {
            write(line)
        }
    }

    /// The text of every line that the run wrote, each one with a line break
    /// after it.
    ///
    /// - Returns: The text, or the empty text when the run wrote no line or
    ///   when the session writes to standard output.
    func text() -> String {
        lines.withLock { $0 }.map { "\($0)\(Self.lineBreak)" }.joined()
    }

    // MARK: - The configuration

    /// The marketplace sources of the configuration (marketplace.md §6.3).
    ///
    /// - Parameter includeProject: Whether to read the `marketplaces.yaml` of
    ///   the project folder. A cloned repository can add a source there, thus
    ///   only an explicit flag turns this on.
    /// - Returns: The sources, in list order.
    /// - Throws: ``MarketplaceConfigError`` when a file cannot be read.
    func sources(includeProject: Bool) throws -> [MarketplaceSource] {
        try MarketplaceConfig.load(from: context.stack, includeProject: includeProject).marketplaces
    }

    /// Writes a source list to the `marketplaces.yaml` of the user layer.
    ///
    /// - Parameter sources: The sources to write, in list order.
    /// - Throws: ``MarketplaceCLIError/noUserLayer`` when the stack has no
    ///   user layer, else the error of the file write.
    func saveUserSources(_ sources: [MarketplaceSource]) throws {
        try MarketplaceConfig(marketplaces: sources).save(to: try userFile())
    }

    /// The `marketplaces.yaml` file of the user layer.
    ///
    /// - Returns: The file, which does not need to exist yet.
    /// - Throws: ``MarketplaceCLIError/noUserLayer``.
    private func userFile() throws -> URL {
        guard let layer = context.stack.layers.first(where: { $0.source == .user }) else {
            throw MarketplaceCLIError.noUserLayer
        }
        return layer.root.appendingPathComponent(MarketplaceConfig.fileName)
    }

    // MARK: - The marketplaces

    /// The rows of one source list.
    ///
    /// - Parameter sources: The sources, in list order.
    /// - Returns: One row for each source.
    func rows(of sources: [MarketplaceSource]) -> [MarketplaceRow] {
        MarketplaceRow.rows(of: sources, cacheDirectory: context.cacheDirectory)
    }

    /// The rows of the configuration.
    ///
    /// - Parameter includeProject: Whether to read the project file.
    /// - Returns: One row for each source, in list order.
    /// - Throws: ``MarketplaceConfigError`` when a file cannot be read.
    func rows(includeProject: Bool) throws -> [MarketplaceRow] {
        rows(of: try sources(includeProject: includeProject))
    }

    /// The marketplace that one id names.
    ///
    /// - Parameters:
    ///   - id: The pre-fetch key or the display id of the marketplace.
    ///   - includeProject: Whether to read the project file.
    /// - Returns: The row of that marketplace.
    /// - Throws: ``MarketplacePinError/unknownMarketplace(id:)`` when no
    ///   source has that id, else ``MarketplaceConfigError``.
    func marketplace(named id: String, includeProject: Bool) throws -> MarketplaceRow {
        guard let found = try rows(includeProject: includeProject).first(where: { $0.names(id) })
        else {
            throw MarketplacePinError.unknownMarketplace(id: id)
        }
        return found
    }

    /// Makes a store over the configuration and the cache folder.
    ///
    /// The call does no network work: the store fetches only when a command
    /// asks it to check or to update.
    ///
    /// - Parameter includeProject: Whether to read the project file.
    /// - Returns: The store.
    /// - Throws: ``MarketplaceConfigError`` when a file cannot be read.
    func makeStore(includeProject: Bool) throws -> MarketplaceStore {
        MarketplaceStore(
            sources: try sources(includeProject: includeProject),
            cacheDirectory: context.cacheDirectory,
            policy: MarketplacePolicy(environment: context.environment))
    }
}
