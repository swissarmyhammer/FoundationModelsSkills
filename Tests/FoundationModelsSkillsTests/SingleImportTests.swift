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

    @Test func aSelectionConfigTakesASessionFactoryThroughTheSingleImport() {
        let config = SelectionConfig(model: { instructions in
            LanguageModelSession(model: .default, instructions: instructions)
        })

        var buildsSessionsFromAFactory = false
        if case .factory = config.sessionSource { buildsSessionsFromAFactory = true }
        #expect(buildsSessionsFromAFactory)
    }

    @Test func aLanguageModelSessionIsAnAgentSessionThroughTheSingleImport() async throws {
        // The test makes a session and forks it. Neither step sends a
        // prompt, thus the test needs no on-device model.
        let session: any AgentSession = LanguageModelSession(model: .default, instructions: "test")

        let forked = try await session.fork()

        #expect(forked is LanguageModelSession)
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
