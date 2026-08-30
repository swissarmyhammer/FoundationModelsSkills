import FoundationModelsSkills
import Operations

/// Builds the registry and the fused `skills` tool every demo mode shares,
/// over the `FixtureStack` fixture library (plan.md §10's assembly sketch).
enum SkillsDemoAssembly {
    /// Builds a `SkillsRegistry` over `FixtureStack.make()`.
    ///
    /// - Parameter watch: Whether to watch the stack and reload on change.
    /// - Returns: The assembled registry.
    static func makeRegistry(watch: Bool) -> SkillsRegistry {
        SkillsRegistry(stack: FixtureStack.make(), watch: watch)
    }

    /// Builds the fused `skills` tool over `registry`, through the one-call
    /// factory the README shows.
    ///
    /// The demo gives the factory no session, thus each search uses keyword
    /// retrieval and the demo needs no model to rank. The factory keeps the
    /// default `isModelVisible` surface, and it follows `registry.onReload`
    /// itself, thus no mode has to pump reloads by hand.
    ///
    /// - Parameter registry: The registry to build a tool over.
    /// - Returns: The assembled tool.
    /// - Throws: Whatever `SkillsTool.make(registry:)` throws.
    static func makeTool(registry: SkillsRegistry) async throws -> OperationTool<SkillsToolContext> {
        try await SkillsTool.make(registry: registry)
    }
}
