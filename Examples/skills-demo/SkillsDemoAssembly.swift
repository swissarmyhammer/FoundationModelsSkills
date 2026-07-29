import FoundationModelsMetadataRegistry
import FoundationModelsSkills

/// Builds the registry and model-facing context every demo mode shares, over
/// the `FixtureStack` fixture library (plan.md §10's assembly sketch).
enum SkillsDemoAssembly {
    /// Builds a `SkillsRegistry` over `FixtureStack.make()`.
    ///
    /// - Parameter watch: Whether to watch the stack and reload on change.
    /// - Returns: The assembled registry.
    static func makeRegistry(watch: Bool) -> SkillsRegistry {
        SkillsRegistry(stack: FixtureStack.make(), watch: watch)
    }

    /// Builds the model-facing `SkillsToolContext` over `registry`: the
    /// default `isModelVisible` surface, with a search agent seeded from
    /// `registry`'s current metadata.
    ///
    /// - Parameter registry: The registry to build a context over.
    /// - Returns: The assembled context.
    static func makeContext(registry: SkillsRegistry) -> SkillsToolContext {
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        return SkillsToolContext(registry: registry, searchAgent: SkillSearchAgent(searcher: searcher))
    }
}
