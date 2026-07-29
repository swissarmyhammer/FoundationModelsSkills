import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Operations
import OperationsCLI
import Testing

/// Tests for the dual-use CLI (plan.md §7.2): driving the fused `skills`
/// tool's `search`/`list`/`use` verbs through `OperationCLIDriver` against
/// the §11 fixture registry, its user-facing (`commandListing()`) visibility
/// matrix, and its round trip back to the model-facing dispatch path.
struct SkillsCLITests {
    // MARK: - Fixture root (mirrors SkillOperationsTests)

    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    /// Builds a fresh registry over the §11 fixture library's `commit` /
    /// `deploy` / `lint` / … skills.
    private static func makeFixtureRegistry() -> SkillsRegistry {
        SkillsRegistry(roots: [Self.projectSkillsRoot])
    }

    /// Builds the CLI driver over a fresh fixture registry.
    private static func makeFixtureDriver() throws -> OperationCLIDriver {
        try SkillsCLI.makeDriver(registry: Self.makeFixtureRegistry())
    }

    // MARK: - Invocation table (§7.2)

    @Test func listVerbListsTheUserVisibleCatalog() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "list"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("\"id\":\"commit\""))
    }

    @Test func searchVerbSearchesTheUserVisibleCatalog() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "search", "--query", "commit"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("\"id\":\"commit\""))
    }

    @Test func useVerbRendersCommitSubstitutingArguments() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "use", "--id", "commit", "--arguments", "fix parser"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("\"id\":\"commit\""))
        #expect(result.output.contains("fix parser"))
    }

    // MARK: - Visibility matrix (plan.md §6)

    @Test func listVerbIncludesDeployWhichIsHiddenFromTheModelSurface() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "list"])

        // `deploy` (`disable-model-invocation: true`) is model-hidden but
        // user-visible -- the opposite polarity from `SkillOperationsTests`'
        // `listSkillDispatchReturnsCatalogRowsWithTotal`, which asserts the
        // model surface never lists it.
        #expect(result.output.contains("\"id\":\"deploy\""))
    }

    @Test func listVerbExcludesLintWhichIsModelOnly() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "list"])

        // `lint` (`user-invocable: false`) is model-only background work --
        // never listed on this user-facing CLI surface.
        #expect(!result.output.contains("\"id\":\"lint\""))
    }

    @Test func useVerbRendersDeployWhichIsHiddenFromTheModelSurface() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "use", "--id", "deploy"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("\"id\":\"deploy\""))
    }

    @Test func useVerbRefusesLintWhichIsModelOnly() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "use", "--id", "lint"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("is not currently usable"))
        #expect(!result.output.contains("\"id\":\"lint\""))
    }

    @Test func useVerbsUnusableIDMessageListsOnlyUserVisibleIDs() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "use", "--id", "lint"])
        let usableIDsList = try #require(result.output.components(separatedBy: "Currently usable ids: ").last)

        // The corrective's "currently usable ids" list is this surface's own
        // (§6 user-facing) visible set, not the model-facing one: it must
        // name `deploy` (user-visible, model-hidden) but never the
        // model-only `lint` that was just refused.
        #expect(usableIDsList.contains("deploy"))
        #expect(!usableIDsList.contains("lint"))
    }

    // MARK: - Round trip: CLI payload == model payload (§7.2)

    @Test func searchVerbRoundTripsToTheIdenticalModelDispatchOutput() async throws {
        let registry = Self.makeFixtureRegistry()
        let driver = try SkillsCLI.makeDriver(registry: registry)
        let modelTool = try Self.makeModelTool(registry: registry)

        let cliResult = await driver.run(arguments: ["skill", "search", "--query", "commit"])
        let modelOutput = try await modelTool.call(arguments: GeneratedContent(properties: ["op": "search skill", "query": "commit"]))

        #expect(cliResult.exitCode == 0)
        #expect(cliResult.output == modelOutput)
    }

    @Test func listVerbRoundTripsToTheIdenticalModelDispatchOutputForAModelVisibleFilter() async throws {
        let registry = Self.makeFixtureRegistry()
        let driver = try SkillsCLI.makeDriver(registry: registry)
        let modelTool = try Self.makeModelTool(registry: registry)

        // `filter: "commit"` matches only `commit`, which both surfaces
        // agree is visible -- the two dispatch paths must therefore agree on
        // the whole payload, not merely overlap.
        let cliResult = await driver.run(arguments: ["skill", "list", "--filter", "commit"])
        let modelOutput = try await modelTool.call(arguments: GeneratedContent(properties: ["op": "list skill", "filter": "commit"]))

        #expect(cliResult.exitCode == 0)
        #expect(cliResult.output == modelOutput)
    }

    @Test func useVerbRoundTripsToTheIdenticalModelDispatchOutputForCommit() async throws {
        let registry = Self.makeFixtureRegistry()
        let driver = try SkillsCLI.makeDriver(registry: registry)
        let modelTool = try Self.makeModelTool(registry: registry)

        let cliResult = await driver.run(arguments: ["skill", "use", "--id", "commit", "--arguments", "fix parser"])
        let modelOutput = try await modelTool.call(
            arguments: GeneratedContent(properties: ["op": "use skill", "id": "commit", "arguments": ["fix parser"]]))

        #expect(cliResult.exitCode == 0)
        #expect(cliResult.output == modelOutput)
    }

    /// Builds the model-facing fused tool over `registry`, mirroring
    /// `SkillOperationsTests.makeFixtureContext()`'s stub-searcher
    /// construction.
    private static func makeModelTool(registry: SkillsRegistry) throws -> OperationTool<SkillsToolContext> {
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        let context = SkillsToolContext(registry: registry, searchAgent: SkillSearchAgent(searcher: searcher))
        return try SkillsTool.make(context: context)
    }
}
