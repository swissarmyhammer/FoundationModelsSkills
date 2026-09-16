import FoundationModelsMetadataRegistry
import Operations
import OperationsCLI

/// Assembles the dual-use CLI over the fused `skills` tool's user-facing
/// surface (plan.md §7.2).
///
/// The model surface (`SkillsTool.make(context:)` over a
/// `SkillMetadata.isModelVisible`-gated context) and this CLI surface share
/// the exact same three operations, the exact same `OperationTool.call(
/// arguments:)` dispatch path, and the exact same registry -- only which
/// entries are visible differs, matching plan.md §6's visibility table:
/// `disable-model-invocation: true` skills (model-hidden) are usable here;
/// `user-invocable: false` skills (model-only) are not.
public enum SkillsCLI {
    /// The name shown in this CLI's usage/help/error text.
    public static let executableName = "skills"

    /// Builds an `OperationCLIDriver` over `registry`'s user-facing subset.
    ///
    /// Rebuilds a fresh, session-free `.retrieval`-mode `MetadataSearcher`
    /// from `registry`'s current catalog on every call, matching a one-shot
    /// CLI invocation's lifetime -- a long-lived host that wants hot-reload
    /// or `.selection` search should build a `SkillsToolContext` directly
    /// instead of going through this type.
    ///
    /// - Parameter registry: The registry to drive the CLI's user-facing
    ///   surface from.
    /// - Returns: The assembled driver.
    /// - Throws: Whatever `SkillsTool.make(context:)` or
    ///   `OperationCLIDriver.init(tool:executableName:)` throws.
    public static func makeDriver(registry: SkillsRegistry) throws -> OperationCLIDriver {
        let tool = try SkillsTool.make(context: Self.makeContext(registry: registry))
        return try OperationCLIDriver(tool: tool, executableName: Self.executableName)
    }

    /// The first argument that names the `marketplace` command group.
    public static let marketplaceCommandName = MarketplaceCLI.commandName

    /// Runs the `marketplace` command group when `arguments` names it
    /// (marketplace.md §9.2).
    ///
    /// This is how a host puts the group next to the `OperationCLIDriver`
    /// tree that ``makeDriver(registry:)`` builds: the host offers the
    /// arguments here first, and it gives them to the driver when the call
    /// gives `nil`. Marketplace control is a host function and a
    /// command-line function, thus the fused `skills` tool gets no operation
    /// from it and ``makeDriver(registry:)`` does not change.
    ///
    /// ```swift
    /// let arguments = Array(CommandLine.arguments.dropFirst())
    /// let result = await SkillsCLI.runMarketplace(arguments: arguments)
    ///     ?? SkillsCLI.makeDriver(registry: registry).run(arguments: arguments)
    /// ```
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the command, with no executable name.
    ///   - context: Where the group reads its configuration and its cache.
    ///     The default is the `skills` stack of the working folder of this
    ///     process.
    /// - Returns: What the group gave, or `nil` when the first argument names
    ///   another command. A host writes the output of a result with a
    ///   non-zero exit code to standard error.
    public static func runMarketplace(
        arguments: [String], context: MarketplaceCLIContext = MarketplaceCLIContext()
    ) async -> MarketplaceCLIResult? {
        guard arguments.first == Self.marketplaceCommandName else {
            return nil
        }
        return await MarketplaceCLI.run(arguments: Array(arguments.dropFirst()), context: context)
    }

    /// Builds the CLI-facing `SkillsToolContext`: `registry` unchanged, a
    /// `visibilityPredicate` matching `registry.commandListing()`'s ids, and
    /// a search agent seeded from that same subset.
    ///
    /// - Parameter registry: The registry to derive the context from.
    /// - Returns: The CLI-facing context.
    private static func makeContext(registry: SkillsRegistry) -> SkillsToolContext {
        let userVisibleIDs = Set(registry.commandListing().map(\.id))
        let isUserVisible: @Sendable (SkillMetadata) -> Bool = { userVisibleIDs.contains($0.id) }
        let searcher = MetadataSearcher(items: registry.metadata().filter(isUserVisible))
        return SkillsToolContext(
            registry: registry,
            searchAgent: SkillSearchAgent(searcher: searcher, visibilityPredicate: isUserVisible),
            visibilityPredicate: isUserVisible
        )
    }
}
