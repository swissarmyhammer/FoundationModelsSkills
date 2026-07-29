import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the Layer-4 model surface (plan.md §7, §13; decisions
/// #15-superseded/#20/#21/#22): dispatching `search skill` / `list skill` /
/// `use skill` through the fused `skills` `OperationTool` against a
/// stub-searcher context, the full §7 corrective matrix, and the resolver's
/// forgiving spellings including the decision #21 verb aliases.
struct SkillOperationsTests {
    // MARK: - Fixture roots (mirrors SkillsRegistryTests)

    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    // MARK: - Stub-searcher context construction

    /// Builds a `SkillsToolContext` over the §11 fixture library's `commit` /
    /// `deploy` / `lint` / … skills, with a real, GPU-free `.retrieval`-mode
    /// `MetadataSearcher` (no embedder, no session) standing in for the
    /// stub-searcher context the acceptance criteria call for.
    private static func makeFixtureContext() -> SkillsToolContext {
        let registry = SkillsRegistry(roots: [projectSkillsRoot])
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        return SkillsToolContext(registry: registry, searchAgent: SkillSearchAgent(searcher: searcher))
    }

    /// Builds the fused `skills` tool over `makeFixtureContext()`.
    private static func makeFixtureTool() throws -> OperationTool<SkillsToolContext> {
        try SkillsTool.make(context: Self.makeFixtureContext())
    }

    // MARK: - Dispatch table: typed outputs (§7)

    @Test func searchSkillDispatchReturnsRankedRowsWithTotal() async throws {
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "search skill", "query": "commit"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"matches\""))
        #expect(json.contains("\"id\":\"commit\""))
        #expect(json.contains("\"total\":1"))
    }

    @Test func listSkillDispatchReturnsCatalogRowsWithTotal() async throws {
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "list skill"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"skills\""))
        #expect(json.contains("\"id\":\"commit\""))
        // `deploy` is model-hidden (`disable-model-invocation: true`) and
        // must never appear on the model-facing `list skill` surface.
        #expect(!json.contains("\"id\":\"deploy\""))
    }

    @Test func useSkillDispatchReturnsTheRenderedBody() async throws {
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "use skill", "id": "commit", "arguments": ["fix parser"]])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"id\":\"commit\""))
        #expect(json.contains("fix parser"))
    }

    // MARK: - Corrective matrix (§7)

    @Test func searchSkillWithBlankQueryReturnsACorrective() async throws {
        let output = try await SearchSkill(query: "   ", limit: nil).execute(in: Self.makeFixtureContext())

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("query"))
    }

    @Test func listSkillWithANoMatchFilterReturnsAnEmptyListNotACorrective() async throws {
        let output = try await ListSkill(filter: "no-such-skill-exists").execute(in: Self.makeFixtureContext())

        #expect(output.skills.isEmpty)
        #expect(output.total == 0)
    }

    @Test func listSkillFilterMatchesCaseInsensitively() async throws {
        let output = try await ListSkill(filter: "COMMIT").execute(in: Self.makeFixtureContext())

        #expect(output.skills.map(\.id) == ["commit"])
        #expect(output.total == 1)
    }

    @Test func useSkillWithAnUnknownIDReturnsACorrectiveCarryingTheCurrentIDs() async throws {
        let output = try await UseSkill(id: "totally-made-up", arguments: nil).execute(in: Self.makeFixtureContext())

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("totally-made-up"))
        #expect(message.contains("commit"))
        #expect(!message.contains("deploy"))
    }

    @Test func useSkillWithAModelHiddenIDReturnsACorrectiveCarryingTheCurrentIDs() async throws {
        // `deploy` carries `disable-model-invocation: true` -- present in the
        // catalog (the user `/` menu can still invoke it) but not usable via
        // the model-facing `use skill` operation.
        let output = try await UseSkill(id: "deploy", arguments: nil).execute(in: Self.makeFixtureContext())

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("deploy"))
        #expect(!message.contains("deploy,"))  // not listed among the usable ids
    }

    @Test func useSkillWithAnUppercasedIDIsCaseSensitiveAndReturnsACorrective() async throws {
        // Pins `UseSkill.id`'s deliberate case-sensitivity (see its doc
        // comment): unlike `ListSkill`'s fuzzy, case-insensitive `filter`
        // (see `listSkillFilterMatchesCaseInsensitively`), `id` names one
        // specific catalog entry and every real id is already
        // lowercase-only, so an uppercased id is simply unusable.
        let output = try await UseSkill(id: "COMMIT", arguments: nil).execute(in: Self.makeFixtureContext())

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("COMMIT"))
    }

    @Test func useSkillOnAModelVisibleButUserHiddenSkillStillSucceeds() async throws {
        // `lint` carries `user-invocable: false` but stays fully model-visible
        // -- confirms the model-hidden guard doesn't over-reject.
        let output = try await UseSkill(id: "lint", arguments: nil).execute(in: Self.makeFixtureContext())

        guard case .success(let result) = output else {
            Issue.record("expected a result outcome, got \(output)")
            return
        }
        #expect(result.id == "lint")
    }

    @Test func useSkillWithAMissingRequiredArgumentReturnsACorrectiveNamingIt() async throws {
        // `commit` declares `arguments: [message]` / `argument-hint: "<message>"`.
        let output = try await UseSkill(id: "commit", arguments: []).execute(in: Self.makeFixtureContext())

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("message"))
    }

    @Test func useSkillWithTheRequiredArgumentSuppliedSucceeds() async throws {
        let output = try await UseSkill(id: "commit", arguments: ["fix parser"]).execute(
            in: Self.makeFixtureContext())

        guard case .success(let result) = output else {
            Issue.record("expected a result outcome, got \(output)")
            return
        }
        #expect(result.body.contains("fix parser"))
    }

    // MARK: - Resolver: canonical + forgiving spellings

    @Test func resolverAcceptsTheCanonicalOpStrings() async throws {
        let tool = try Self.makeFixtureTool()

        for op in ["search skill", "list skill", "use skill"] {
            let payload: GeneratedContent
            switch op {
            case "use skill":
                payload = GeneratedContent(properties: ["op": op, "id": "commit", "arguments": ["fix parser"]])
            case "search skill":
                payload = GeneratedContent(properties: ["op": op, "query": "commit"])
            default:
                payload = GeneratedContent(properties: ["op": op])
            }
            let json = try await tool.call(arguments: payload)
            #expect(!json.contains("Unknown operation"), "\(op) should resolve, got: \(json)")
        }
    }

    @Test func resolverAcceptsTheReversedNounVerbSpellingSkillSearch() async throws {
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "skill search", "query": "commit"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"matches\""))
    }

    @Test func resolverAcceptsTheUnderscoreSpellingUseSkill() async throws {
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "use_skill", "id": "commit", "arguments": ["fix parser"]])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"body\""))
    }

    @Test func resolverAcceptsTheReversedSingularSpellingSkillList() async throws {
        // The real upstream `OperationResolver` tolerates reversed order and
        // `_`/`-` separators, but never noun pluralization (verified by
        // reading `OperationResolver.matchOpString`: it substitutes only the
        // verb-position token via `verbAliases`, and compares the noun
        // token literally). So the singular reversed spelling resolves...
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "skill list"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"skills\""))
    }

    @Test func resolverDoesNotAcceptThePluralReversedSpellingSkillsList() async throws {
        // ...but the plural spelling `skills list` plan.md decision #21
        // describes does not: there is no noun-normalization lever in the
        // shipped resolver to fold `skills` (plural) onto our declared
        // singular noun `skill`. Documented as a discrepancy on the kanban
        // task; pinned here so a future resolver change that adds plural
        // tolerance is noticed (this test would then need updating to
        // expect success).
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "skills list"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("Unknown operation"))
    }

    // MARK: - Resolver: decision #21 verb aliases

    @Test func findSkillAliasesToSearchSkill() async throws {
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "find skill", "query": "commit"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"matches\""))
    }

    @Test func findSkillAliasResolvesCaseInsensitively() async throws {
        // Verb-alias resolution shares `OperationResolver.spaceSeparatedTokens`'s
        // lowercasing with the canonical/reversed/underscore spellings above,
        // so an uppercase alias token resolves exactly like its lowercase form.
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "FIND SKILL", "query": "commit"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"matches\""))
    }

    @Test func discoverSkillAliasesToSearchSkill() async throws {
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "discover skill", "query": "commit"])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"matches\""))
    }

    @Test func runSkillAliasesToUseSkill() async throws {
        // Pinned per decision #21 / the task's acceptance criteria: before
        // M6 adds a `run script` operation to this same fused tool, "run
        // skill" must resolve to `use skill`. (M6 will need to revisit the
        // blanket "run" -> "use" verb alias in `SkillsTool.skillVerbAliases`,
        // since the shipped resolver applies an alias unconditionally --
        // see that table's doc comment.)
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "run skill", "id": "commit", "arguments": ["fix parser"]])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"body\""))
    }

    @Test func callSkillAliasesToUseSkill() async throws {
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(
            properties: ["op": "call skill", "id": "commit", "arguments": ["fix parser"]])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"body\""))
    }

    @Test func invokeSkillAliasesToUseSkill() async throws {
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(
            properties: ["op": "invoke skill", "id": "commit", "arguments": ["fix parser"]])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"body\""))
    }

    @Test func getSkillAliasesToUseSkill() async throws {
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(
            properties: ["op": "get skill", "id": "commit", "arguments": ["fix parser"]])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("\"body\""))
    }

    // MARK: - generatedContent / init(_:) round trips

    @Test func searchSkillRoundTripsThroughGeneratedContentWithLimitPresent() throws {
        let original = SearchSkill(query: "commit", limit: 3)

        let decoded = try SearchSkill(original.generatedContent)

        #expect(decoded.query == original.query)
        #expect(decoded.limit == original.limit)
    }

    @Test func searchSkillRoundTripsThroughGeneratedContentWithNoLimit() throws {
        let original = SearchSkill(query: "commit")

        let decoded = try SearchSkill(original.generatedContent)

        #expect(decoded.query == original.query)
        #expect(decoded.limit == nil)
    }

    @Test func listSkillRoundTripsThroughGeneratedContentWithFilterPresent() throws {
        let original = ListSkill(filter: "commit")

        let decoded = try ListSkill(original.generatedContent)

        #expect(decoded.filter == original.filter)
    }

    @Test func listSkillRoundTripsThroughGeneratedContentWithNoFilter() throws {
        let original = ListSkill()

        let decoded = try ListSkill(original.generatedContent)

        #expect(decoded.filter == nil)
    }

    @Test func useSkillRoundTripsThroughGeneratedContentWithArgumentsPresent() throws {
        let original = UseSkill(id: "commit", arguments: ["fix parser"])

        let decoded = try UseSkill(original.generatedContent)

        #expect(decoded.id == original.id)
        #expect(decoded.arguments == original.arguments)
    }

    @Test func useSkillRoundTripsThroughGeneratedContentWithNoArguments() throws {
        let original = UseSkill(id: "commit")

        let decoded = try UseSkill(original.generatedContent)

        #expect(decoded.id == original.id)
        #expect(decoded.arguments == nil)
    }

    // MARK: - The fused tool exposes exactly one core Tool with the flat-union schema

    @Test func fusedToolExposesExactlyTheFiveCanonicalOps() throws {
        let tool = try Self.makeFixtureTool()

        #expect(
            tool.operations.map(\.opString) == [
                "search skill", "list skill", "use skill", "list resource", "read resource",
            ])
        #expect(tool.name == "skills")
    }
}
