import FoundationModels
import FoundationModelsSkills
import Testing

/// The compile-and-run contract for the usage block in `README.md`.
///
/// `theReadmeUsageBlockBuildsTheFusedToolAndItsRootSession()` holds that
/// block word for word, over the `Examples/skill-library` fixture stack.
/// The block is code in this target, thus it must compile, and the README
/// cannot drift into code that does not build.
///
/// This file imports `FoundationModels`, `FoundationModelsSkills`, and
/// `Testing`, and nothing else. The README block names the same two library
/// modules, thus this import list is the proof that those two modules are
/// sufficient for a host: no `FoundationModelsMetadataRegistry`, and no
/// `FoundationModelsExtras`.
///
/// Every case is GPU-free. The block gives the factory a session closure,
/// but the selection tier calls that closure only when a search runs, and
/// this suite runs no search through that tool. The search case below uses
/// the no-session form of the same factory, which the README paragraph
/// names, thus it ranks with keyword retrieval and needs no model.
struct ReadmeExampleTests {
    // MARK: - Constants

    /// The name the fused tool carries, as `SkillsTool.make` sets it.
    private static let fusedToolName = "skills"

    /// The query the search case sends, and the fixture skill it must rank
    /// first.
    ///
    /// The same pair the `skills-demo` CLI case searches with, thus the
    /// README's retrieval claim and the demo's own behavior stay one claim.
    private static let searchQuery = "commit my changes"

    /// The fixture skill `searchQuery` must rank first.
    private static let bestMatchSkillID = "commit"

    // MARK: - The README usage block

    /// Runs the README usage block over the fixture stack, and asserts that
    /// both of the things it builds are real: the fused tool, and a root
    /// session that carries that tool.
    ///
    /// The session assertion is the one the README paragraph makes. A
    /// `LanguageModelSession` lists every tool it was given in the
    /// `.instructions` entry of its transcript, thus a tool name there shows
    /// that the fused tool went into a standard session with no adapter.
    @Test func theReadmeUsageBlockBuildsTheFusedToolAndItsRootSession() async throws {
        let projectDirectory = FixtureLibrary.url(relativePath: "project")
        let shippedSkillsURL = FixtureLibrary.url(relativePath: "defaults")
        let userConfigURL = FixtureLibrary.url(relativePath: "user")

        // The README usage block starts here.
        // The host selects the layer roots. The usual way is a "skills" dotfolder stack:
        let stack = DotfolderStack(
            name: "skills",
            workingDirectory: projectDirectory,
            defaultsDirectory: shippedSkillsURL,
            userDirectory: userConfigURL)
        let registry = SkillsRegistry(stack: stack, watch: true)

        // One fused tool for the full catalog: search, list, use, resources, scripts.
        // The session you supply runs the selection tier. Nothing is hardcoded.
        let skillsTool = try await SkillsTool.make(
            registry: registry,
            session: { prefix in LanguageModelSession(model: .default, instructions: prefix) })

        // A lean root session: one tool, preloaded bodies, no full catalog in context.
        let session = LanguageModelSession(
            tools: [skillsTool],
            instructions: Instructions {
                "You use the skills tool to search and run skills from the local library."
                registry.preloadedBodies()
            })
        // The README usage block ends here.

        #expect(skillsTool.name == Self.fusedToolName)
        #expect(Self.toolNames(in: session.transcript) == [Self.fusedToolName])
    }

    // MARK: - The no-session form the README paragraph names

    /// Shows the claim the README paragraph makes about the no-session form:
    /// a host that gives no session still gets ranked matches, with no model.
    ///
    /// `SkillsToolAssemblyTests` proves the same factory ranks. This case
    /// proves something that suite cannot: it dispatches an operation and
    /// reads the answer from a file whose imports are only the two modules
    /// the README names. `SkillsToolAssemblyTests` needs `import Operations`
    /// to name `OperationTool` in its own dispatch helper, thus it shows
    /// nothing about the import surface a host lives with.
    @Test func theNoSessionFormOfTheFactoryRanksTheFixtureCatalogWithNoModel() async throws {
        let registry = SkillsRegistry(stack: FixtureLibrary.stack())

        let skillsTool = try await SkillsTool.make(registry: registry)
        let json = try await skillsTool.call(
            arguments: GeneratedContent(properties: ["op": "search skill", "query": Self.searchQuery]))

        #expect(Self.rankedIDs(in: json).first == Self.bestMatchSkillID)
    }

    // MARK: - Reading the results back

    /// The names of every tool `transcript` was seeded with.
    ///
    /// - Parameter transcript: The session transcript to read.
    /// - Returns: The tool names, in the order the transcript lists them.
    private static func toolNames(in transcript: Transcript) -> [String] {
        var names: [String] = []
        for entry in transcript {
            guard case .instructions(let instructions) = entry else { continue }
            names.append(contentsOf: instructions.toolDefinitions.map(\.name))
        }
        return names
    }

    /// The skill ids in a `search skill` answer, best first.
    ///
    /// `search skill` answers with JSON, and this file imports no
    /// `Foundation`, thus it has no `JSONDecoder`. The ids come out of the
    /// text instead. Every row of the answer carries exactly one `"id"`
    /// field, and the rows stand in rank order, thus the order the ids
    /// appear in the text is the rank order.
    ///
    /// - Parameter json: One `search skill` answer.
    /// - Returns: The matching skill ids, best first.
    private static func rankedIDs(in json: String) -> [String] {
        let marker = "\"id\":\""
        var ids: [String] = []
        var remainder = Substring(json)
        while let markerRange = remainder.firstRange(of: marker) {
            let afterMarker = remainder[markerRange.upperBound...]
            ids.append(String(afterMarker.prefix { $0 != "\"" }))
            remainder = afterMarker
        }
        return ids
    }
}
