import FoundationModels
import FoundationModelsSkills
import Testing

/// Proves that one `import FoundationModelsSkills` is sufficient for a host
/// that builds the skills tool.
///
/// This file imports no sibling package. It does not import
/// `FoundationModelsMetadataRegistry`, `FoundationModelsRanker`, or
/// `FoundationModelsExtras`. Each test below names a type that one of those
/// three packages declares. Thus this file compiles only while
/// `Sources/FoundationModelsSkills/SeamReexports.swift` re-exports the
/// search seam and the dotfolder stack. A change that removes a re-export
/// stops this file from compiling.
struct SingleImportTests {
    // MARK: - The search seam

    @Test func aSearchOverATwoItemCatalogGivesAMatchThroughTheSingleImport() async throws {
        let commit = SkillMetadata(
            id: "commit", description: "Writes a commit message.", isModelVisible: true)
        let deploy = SkillMetadata(
            id: "deploy", description: "Sends the build to production.", isModelVisible: true)
        let searcher = MetadataSearcher(items: [commit, deploy])
        let agent = SkillSearchAgent(searcher: searcher)

        let matches = try await agent.search(query: "commit", limit: 5)

        #expect(matches.first?.id == "commit")
    }

    // MARK: - The selection seam

    @Test func aSelectionConfigTakesASystemLanguageModelThroughTheSingleImport() {
        // The test makes a configuration only. It sends no prompt, thus the
        // test needs no on-device model.
        let config = SelectionConfig(model: SystemLanguageModel.default)

        #expect(config.model is SystemLanguageModel)
    }

    @Test func aPooledEmbedderIsAPooledEmbeddingThroughTheSingleImport() {
        // A `PooledEmbedder` made from a name loads nothing until its first
        // embed, thus the test needs no model.
        let embedder: any PooledEmbedding = PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")

        #expect(embedder is PooledEmbedder)
    }

    // MARK: - The dotfolder stack

    @Test func aDotfolderStackIsConstructibleThroughTheSingleImport() throws {
        try WatcherTestSupport.withTempDirectory { workingDirectory in
            // An empty environment keeps `SKILLS_DEFAULTS_DIR` and
            // `XDG_CONFIG_HOME` from moving a layer onto a real host
            // directory.
            let stack = DotfolderStack(
                name: "skills", workingDirectory: workingDirectory, environment: [:])

            #expect(stack.layers.map(\.source) == [.user, .project])
        }
    }
}
