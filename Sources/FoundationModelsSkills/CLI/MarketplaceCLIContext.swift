import Foundation
import FoundationModelsExtras
import Marketplace

/// Where the `marketplace` commands read their configuration and their cache.
///
/// The host gives the folders and the environment. Thus a test drives every
/// subcommand over a temporary stack and a temporary cache, and no test reads
/// the real home folder.
///
/// ```swift
/// let result = await MarketplaceCLI.run(
///     arguments: ["list"], context: .currentProcess)
/// ```
public struct MarketplaceCLIContext: Sendable {
    /// The dotfolder name of the configuration stack: `~/.config/skills` for
    /// the user layer, and `<working directory>/.skills` for the project
    /// layer.
    public static let dotfolderName = "skills"

    /// The context over the working folder of this process, which a command
    /// takes when its caller names no folder.
    ///
    /// `URL.currentDirectory()` gives the folder. This is the one place of
    /// the package that reads where the process stands, thus a test that
    /// gives its own folder never reaches the real home folder.
    public static var currentProcess: MarketplaceCLIContext {
        MarketplaceCLIContext(workingDirectory: URL.currentDirectory())
    }

    /// The stack that holds `marketplaces.yaml`. Only its user layer and its
    /// project layer are read.
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
    /// The folder has no default: the caller names it. The loading boundary
    /// of this package keeps the file system out, thus no type
    /// here asks the file system where this process stands. The three command
    /// entry points give ``currentProcess`` for that, and a test gives its own
    /// temporary folder.
    ///
    /// - Parameters:
    ///   - workingDirectory: The folder that holds the project layer.
    ///   - environment: The environment to read. The default is the
    ///     environment of this process.
    public init(
        workingDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.init(
            stack: DotfolderStack(
                name: Self.dotfolderName, workingDirectory: workingDirectory,
                environment: environment),
            environment: environment)
    }

    /// The cache folder that holds `state.json` and every marketplace folder.
    internal var cacheDirectory: URL {
        MarketplaceStore.cacheDirectory(environment: environment)
    }
}
