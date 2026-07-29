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
