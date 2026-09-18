import Foundation
import Operations

/// The `marketplace` command group of the CLI (marketplace.md §9.2 and §9.3).
///
/// Marketplace control is a host function and a command-line function. It is
/// no model operation: the fused `skills` tool gets no operation from this
/// group.
///
/// The group holds `list`, `check`, `update`, `pin`, `unpin`, `add`, and
/// `remove`. Every command reads `marketplaces.yaml` of the user layer, and
/// the file of the project layer only with `--include-project`, which is the
/// trust gate of marketplace.md §6.3.
///
/// ```swift
/// let result = await MarketplaceCLI.run(arguments: ["list"])
/// ```
public struct MarketplaceCLI: AsyncParsableCommand {
    /// The name of the group, and the argument that names it.
    public static let commandName = "marketplace"

    /// The name, the description, and the subcommands of the group.
    public static let configuration = CommandConfiguration(
        commandName: commandName,
        abstract: "Reads and changes the marketplaces of this computer.",
        subcommands: [
            List.self, Check.self, Update.self, Pin.self, Unpin.self, Add.self, Remove.self,
        ])

    /// Creates the group. ArgumentParser needs this initializer.
    public init() {}

    /// Runs the group over one argument list.
    ///
    /// The call gives the text back instead of printing it, in the same shape
    /// as `OperationCLIDriver.run(arguments:)`. A host writes the output of a
    /// result with a non-zero exit code to standard error
    /// (``MarketplaceCLIResult``).
    ///
    /// - Parameters:
    ///   - arguments: The arguments after the name of the group, for example
    ///     `["list", "--include-project"]`.
    ///   - context: Where the group reads its configuration and its cache.
    ///     The default is the `skills` stack of the working folder of this
    ///     process.
    /// - Returns: The output of the subcommand and the exit code of the run.
    ///   A failure gives the text of the error and a non-zero exit code.
    public static func run(
        arguments: [String], context: MarketplaceCLIContext = MarketplaceCLIContext()
    ) async -> MarketplaceCLIResult {
        let session = MarketplaceCLISession(context: context)
        return await MarketplaceCLISession.$current.withValue(session) {
            do {
                try await runCommand(try await asyncParseAsRoot(arguments))
                return MarketplaceCLIResult(output: session.text(), exitCode: 0)
            } catch {
                return MarketplaceCLIResult(
                    output: fullMessage(for: error), exitCode: exitCode(for: error).rawValue)
            }
        }
    }

    /// Runs one parsed command, as `AsyncParsableCommand.main(_:)` does.
    ///
    /// - Parameter command: The command that the parser gave.
    /// - Throws: Whatever the command throws.
    private static func runCommand(_ command: ParsableCommand) async throws {
        var mutableCommand = command
        if var asyncCommand = mutableCommand as? AsyncParsableCommand {
            try await asyncCommand.run()
        } else {
            try mutableCommand.run()
        }
    }

    /// The trust gate of the project `marketplaces.yaml` (marketplace.md
    /// §6.3).
    ///
    /// A cloned repository can carry a file that names a remote source, thus
    /// a command reads that file only when the user asks for it.
    internal struct ProjectOption: ParsableArguments {
        /// Whether the command also reads the `marketplaces.yaml` of the
        /// project folder.
        @Flag(
            help: """
                Also read the marketplaces.yaml of the project folder. A cloned repository can add \
                a source there, thus give this flag only for a folder that you trust.
                """)
        var includeProject = false
    }

    // MARK: - list

    /// `marketplace list`: the marketplaces in order, with their id, URL,
    /// commit, catalog version, last check, and status.
    internal struct List: AsyncParsableCommand {
        /// The name and the description of the command.
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Shows every marketplace of the configuration. It reads only the disk.")

        /// The trust gate of the project file.
        @OptionGroup var project: ProjectOption

        /// Writes one line for each marketplace.
        ///
        /// - Throws: ``MarketplaceConfigError`` when a configuration file
        ///   cannot be read.
        func run() async throws {
            let session = MarketplaceCLISession.active
            let rows = try session.rows(includeProject: project.includeProject)
            session.write(
                lines: MarketplaceCLITable.lines(
                    headings: MarketplaceRow.headings, rows: rows.map(\.cells)))
        }
    }

    // MARK: - check

    /// `marketplace check`: what the remote head of each marketplace is. The
    /// command downloads no content (marketplace.md §8.1).
    internal struct Check: AsyncParsableCommand {
        /// The name and the description of the command.
        static let configuration = CommandConfiguration(
            commandName: "check",
            abstract: "Asks each remote for its head. The command downloads no content.")

        /// The heading of each column of the output.
        private static let headings = ["ID", "CURRENT", "LATEST", "UPDATE", "ERROR"]

        /// The text of the update column when the remote holds a commit that
        /// the snapshot does not.
        private static let updateAvailableText = "yes"

        /// The text of the update column when the snapshot is up to date.
        private static let upToDateText = "no"

        /// The id of one marketplace, or nothing for every marketplace.
        @Argument(help: "The id of one marketplace, or nothing for every marketplace.")
        var id: String?

        /// The trust gate of the project file.
        @OptionGroup var project: ProjectOption

        /// Writes one line for each marketplace that the command checked.
        ///
        /// - Throws: ``MarketplacePinError/unknownMarketplace(id:)`` when no
        ///   source has the given id, else ``MarketplaceConfigError``.
        func run() async throws {
            let session = MarketplaceCLISession.active
            let wantedID = try id.map {
                try session.marketplace(named: $0, includeProject: project.includeProject).id
            }
            let store = try session.makeStore(includeProject: project.includeProject)
            let statuses = await store.check().filter { wantedID == nil || $0.id == wantedID }
            session.write(
                lines: MarketplaceCLITable.lines(
                    headings: Self.headings, rows: statuses.map(Self.cells(of:))))
        }

        /// The cells of one status, in the order of ``headings``.
        ///
        /// - Parameter status: What the check found.
        /// - Returns: The cells.
        private static func cells(of status: MarketplaceStatus) -> [String] {
            [
                status.id,
                status.current ?? MarketplaceRow.emptyValue,
                status.latest ?? MarketplaceRow.emptyValue,
                status.updateAvailable ? updateAvailableText : upToDateText,
                status.error ?? MarketplaceRow.emptyValue,
            ]
        }
    }

    // MARK: - update

    /// `marketplace update`: brings one marketplace, or every marketplace, to
    /// its remote head (marketplace.md §8.3).
    internal struct Update: AsyncParsableCommand {
        /// The name and the description of the command.
        static let configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Brings one marketplace, or every marketplace, to its remote head.")

        /// What the command writes when no marketplace changed.
        private static let noChangeText = "No marketplace changed."

        /// The id of one marketplace, or nothing for every marketplace.
        @Argument(help: "The id of one marketplace, or nothing for every marketplace.")
        var id: String?

        /// Whether to install the commit again with no remote change.
        @Flag(
            help: """
                Install the commit again, also when the snapshot on the disk is already that \
                commit.
                """)
        var force = false

        /// The trust gate of the project file.
        @OptionGroup var project: ProjectOption

        /// Writes one line for each marketplace that changed, that has an
        /// update, or that failed.
        ///
        /// A marketplace that failed gets a line and no error exit: the other
        /// marketplaces of the run are good, and the last good snapshot of
        /// that one stays in place.
        ///
        /// - Throws: ``MarketplacePinError/unknownMarketplace(id:)`` when no
        ///   source has the given id, else ``MarketplaceConfigError``.
        func run() async throws {
            let session = MarketplaceCLISession.active
            let wantedID = try id.map {
                try session.marketplace(named: $0, includeProject: project.includeProject).id
            }
            let store = try session.makeStore(includeProject: project.includeProject)
            let events = await store.update(wantedID, force: force)
            session.write(
                lines: events.isEmpty ? [Self.noChangeText] : events.map(Self.text(of:)))
        }

        /// The line of one event.
        ///
        /// No line holds a URL or a credential: an event names only the
        /// display id, a commit, and a message.
        ///
        /// - Parameter event: What the store did with one marketplace.
        /// - Returns: The line.
        private static func text(of event: MarketplaceEvent) -> String {
            switch event {
            case .checked(let id, _, let latest):
                "\(id): the remote head is the commit \(latest)."
            case .updateAvailable(let id, _, let to):
                "\(id): the commit \(to) is available, and the store did not install it."
            case .updated(let id, _, let to):
                "\(id): installed the commit \(to)."
            case .failed(let id, let error, let keptVersion):
                "\(id): the update failed: \(error) The snapshot that stays is "
                    + "\(keptVersion ?? MarketplaceRow.emptyValue)."
            }
        }
    }

    // MARK: - pin and unpin

    /// `marketplace pin`: holds one marketplace at one commit
    /// (marketplace.md §8.3).
    internal struct Pin: AsyncParsableCommand {
        /// The name and the description of the command.
        static let configuration = CommandConfiguration(
            commandName: "pin",
            abstract: "Holds one marketplace at one commit, thus it never moves to the head.")

        /// The id of the marketplace to pin.
        @Argument(help: "The id of the marketplace.")
        var id: String

        /// The commit to hold.
        @Argument(help: "The commit to hold, as a hexadecimal object name.")
        var sha: String

        /// The trust gate of the project file.
        @OptionGroup var project: ProjectOption

        /// Pins the marketplace and writes one line.
        ///
        /// - Throws: ``MarketplacePinError`` when no source has that id or
        ///   the marketplace is a folder on this computer,
        ///   ``MarketplaceCacheError`` when the commit is no object name,
        ///   else ``MarketplaceConfigError``.
        func run() async throws {
            let session = MarketplaceCLISession.active
            let marketplace = try session.marketplace(
                named: id, includeProject: project.includeProject)
            let store = try session.makeStore(includeProject: project.includeProject)
            try await store.pin(marketplace.id, sha: sha)
            session.write("\(marketplace.id): pinned to the commit \(sha).")
        }
    }

    /// `marketplace unpin`: lets one marketplace follow its ref again
    /// (marketplace.md §8.3).
    internal struct Unpin: AsyncParsableCommand {
        /// The name and the description of the command.
        static let configuration = CommandConfiguration(
            commandName: "unpin",
            abstract: "Drops the pin of one marketplace, thus it follows its ref again.")

        /// The id of the marketplace to unpin.
        @Argument(help: "The id of the marketplace.")
        var id: String

        /// The trust gate of the project file.
        @OptionGroup var project: ProjectOption

        /// Drops the pin and writes one line.
        ///
        /// - Throws: ``MarketplacePinError`` when no source has that id or
        ///   the marketplace is a folder on this computer, else
        ///   ``MarketplaceConfigError``.
        func run() async throws {
            let session = MarketplaceCLISession.active
            let marketplace = try session.marketplace(
                named: id, includeProject: project.includeProject)
            let store = try session.makeStore(includeProject: project.includeProject)
            try await store.unpin(marketplace.id)
            session.write("\(marketplace.id): the pin is gone.")
        }
    }

    // MARK: - add and remove

    /// `marketplace add`: puts one source at the end of the user
    /// `marketplaces.yaml`, thus it wins over the earlier sources
    /// (marketplace.md §6.2).
    internal struct Add: AsyncParsableCommand {
        /// The name and the description of the command.
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Adds one marketplace at the end of the user configuration.")

        /// The URL of the new marketplace.
        @Argument(
            help: """
                The URL of the marketplace: https://host/owner/repo.git, github:owner/repo, or \
                file:///path. SSH URLs are not supported. Do not put a credential in the URL.
                """)
        var url: String

        /// The branch or the tag to follow.
        @Option(help: "The branch or the tag to follow.")
        var ref: String?

        /// A local name for the marketplace.
        @Option(help: "A local name for the marketplace. It becomes the id of the other commands.")
        var alias: String?

        /// Writes the new source and one line.
        ///
        /// The call parses the URL first. Thus a URL that carries a
        /// credential never reaches the file, and no message shows it.
        ///
        /// - Throws: ``MarketplaceSourceError`` when the URL is no §5.1 form,
        ///   ``MarketplaceCLIError/duplicateMarketplace(key:)`` when the user
        ///   configuration already has that id, else the error of the file
        ///   write.
        func run() async throws {
            let session = MarketplaceCLISession.active
            let source = MarketplaceSource(url, ref: ref, alias: alias)
            let key = try MarketplaceIdentity.preFetchKey(for: source)
            var sources = try session.sources(includeProject: false)
            guard !sources.contains(where: { Self.key(of: $0) == key }) else {
                throw MarketplaceCLIError.duplicateMarketplace(key: key)
            }
            sources.append(source)
            try session.saveUserSources(sources)
            session.write("Added the marketplace \(key).")
        }

        /// The pre-fetch key of one source that is already in the file.
        ///
        /// - Parameter source: The source.
        /// - Returns: The key, or `nil` when the source gives none. Such a
        ///   source blocks no new id.
        private static func key(of source: MarketplaceSource) -> String? {
            try? MarketplaceIdentity.preFetchKey(for: source)
        }
    }

    /// `marketplace remove`: takes one source out of the user
    /// `marketplaces.yaml`.
    internal struct Remove: AsyncParsableCommand {
        /// The name and the description of the command.
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Takes one marketplace out of the user configuration.")

        /// The id of the marketplace to remove.
        @Argument(help: "The id of the marketplace.")
        var id: String

        /// Writes the shorter source list and one line.
        ///
        /// The command reads and writes the user layer alone: a source of the
        /// project layer belongs to the repository, not to this user.
        ///
        /// - Throws: ``MarketplacePinError/unknownMarketplace(id:)`` when the
        ///   user configuration has no source with that id, else the error of
        ///   the file write.
        func run() async throws {
            let session = MarketplaceCLISession.active
            let sources = try session.sources(includeProject: false)
            let rows = session.rows(of: sources)
            guard let index = rows.firstIndex(where: { $0.names(id) }) else {
                throw MarketplacePinError.unknownMarketplace(id: id)
            }
            var remaining = sources
            remaining.remove(at: index)
            try session.saveUserSources(remaining)
            session.write("Removed the marketplace \(rows[index].id).")
        }
    }
}
