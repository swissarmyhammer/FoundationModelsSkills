import Foundation
import FoundationModelsExtras

/// Where the `marketplace` commands read their configuration and their cache
/// (marketplace.md §9.2 and §9.3).
///
/// The host gives the folders and the environment. Thus a test drives every
/// subcommand over a temporary stack and a temporary cache, and no test reads
/// the real home folder.
///
/// ```swift
/// let result = await MarketplaceCLI.run(arguments: ["list"], context: MarketplaceCLIContext())
/// ```
public struct MarketplaceCLIContext: Sendable {
    /// The dotfolder name of the configuration stack: `~/.config/skills` for
    /// the user layer, and `<working directory>/.skills` for the project
    /// layer.
    public static let dotfolderName = "skills"

    /// The stack that holds `marketplaces.yaml`. Only its user layer and its
    /// project layer are read (marketplace.md §6.3).
    public var stack: DotfolderStack

    /// The environment that names the cache folder, the read-only seed
    /// folder, and the automatic update.
    public var environment: [String: String]

    /// Creates a context over one stack.
    ///
    /// - Parameters:
    ///   - stack: The stack that holds `marketplaces.yaml`.
    ///   - environment: The environment to read. The default is the
    ///     environment of this process.
    public init(
        stack: DotfolderStack, environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.stack = stack
        self.environment = environment
    }

    /// Creates a context over the `skills` dotfolder stack of one working
    /// folder.
    ///
    /// - Parameters:
    ///   - workingDirectory: The folder that holds the project layer. The
    ///     default is the working folder of this process.
    ///   - environment: The environment to read. The default is the
    ///     environment of this process.
    public init(
        workingDirectory: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.init(
            stack: DotfolderStack(
                name: Self.dotfolderName, workingDirectory: workingDirectory,
                environment: environment),
            environment: environment)
    }

    /// The cache folder that holds `state.json` and every marketplace folder
    /// (marketplace.md §7.1).
    internal var cacheDirectory: URL {
        MarketplaceCache.cacheDirectory(environment: environment)
    }
}
