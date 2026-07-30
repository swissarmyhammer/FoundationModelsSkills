import Foundation
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
        FixtureLibrary.makeSkillsToolContext(registry: SkillsRegistry(roots: [projectSkillsRoot]))
    }

    /// Builds the fused `skills` tool over `makeFixtureContext()`.
    private static func makeFixtureTool() throws -> OperationTool<SkillsToolContext> {
        try SkillsTool.make(context: Self.makeFixtureContext())
    }

    // MARK: - Known deviation: op-level correctives never hit upstream's retry cap

    /// Pins the README's documented deviation (`## Known deviations`):
    /// `OperationTool.call(arguments:)`'s retry cap only counts
    /// *resolver-level* failures (unknown op, missing required parameters) --
    /// an op-level `CorrectiveOutcome.corrective(_:)`, like `use skill`'s
    /// unknown-id message, always reaches `operation.run(...)` successfully
    /// and resets the counter, so it never counts as a failure no matter how
    /// many times it repeats in a row.
    ///
    /// Not a desired behavior -- a regression sentinel. If a future upstream
    /// `FoundationModelsOperationTool` change starts distinguishing
    /// op-level correctives from real successes, this test starts failing
    /// (the terminal message would appear), which is the signal to update
    /// this test and the README section together.
    @Test func repeatedUnknownIDUseSkillDispatchesAreNeverCappedByUpstreamsRetryLimit() async throws {
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "use skill", "id": "totally-made-up"])

        // Upstream's default retryCap is 2 -- five consecutive corrective
        // dispatches is comfortably past that, on the same `tool` instance
        // so its retry-state actor is shared across every call below.
        for _ in 1...5 {
            let json = try await tool.call(arguments: arguments)
            #expect(json.hasPrefix("\""))
            #expect(json.contains("not currently usable"))
            #expect(!json.contains("Too many invalid operation attempts"))
        }
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

    @Test func searchSkillNeverLeaksAModelHiddenSkillSeededDirectlyIntoTheSearcher() async throws {
        // Seeds the searcher directly (bypassing `SkillSearchAgent.update(
        // items:)`'s own filtering, ^49at4v3), so this exercises
        // `SearchSkill.execute`'s own `context.visibilityPredicate` filter
        // as the last line of defense.
        let hidden = SkillMetadata(id: "hidden-tool", description: "A hidden diagnostic tool.", isModelVisible: false)
        let visible = SkillMetadata(id: "visible-tool", description: "A visible diagnostic tool.", isModelVisible: true)
        let registry = SkillsRegistry(roots: [Self.projectSkillsRoot])
        let searcher = MetadataSearcher(items: [hidden, visible])
        let context = SkillsToolContext(registry: registry, searchAgent: SkillSearchAgent(searcher: searcher))

        let output = try await SearchSkill(query: "diagnostic tool", limit: nil).execute(in: context)

        guard case .success(let result) = output else {
            Issue.record("expected a result outcome, got \(output)")
            return
        }
        #expect(!result.matches.contains { $0.id == "hidden-tool" })
        #expect(result.matches.contains { $0.id == "visible-tool" })
    }

    @Test func searchSkillReportsTheRealTotalBeforeTheLimitCap() async throws {
        let items = (1...5).map { index in
            SkillMetadata(id: "widget-\(index)", description: "Handles widget tasks.", isModelVisible: true)
        }
        let registry = SkillsRegistry(roots: [Self.projectSkillsRoot])
        let searcher = MetadataSearcher(items: items)
        let context = SkillsToolContext(registry: registry, searchAgent: SkillSearchAgent(searcher: searcher))

        let output = try await SearchSkill(query: "widget", limit: 2).execute(in: context)

        guard case .success(let result) = output else {
            Issue.record("expected a result outcome, got \(output)")
            return
        }
        #expect(result.matches.count == 2)
        #expect(result.total == 5)
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

    // MARK: - Missing-argument check consults SkillParameter.required directly (^dw132bc)

    /// Writes a single skill (id `"widget"`) under a fresh private temp
    /// directory with the given frontmatter fragments, then builds a
    /// `SkillsToolContext` over just that root -- isolated from the shared
    /// `project/.skills` fixture library so each case here exercises exactly
    /// one parameter source (`arguments:`, `argument-hint:`, or body
    /// inference) without another source's default bleeding in.
    ///
    /// - Parameters:
    ///   - argumentsLine: The raw `arguments:` frontmatter line (including
    ///     the trailing newline), or `""` to omit it entirely.
    ///   - argumentHintLine: The raw `argument-hint:` frontmatter line
    ///     (including the trailing newline), or `""` to omit it entirely.
    ///   - body: The skill body text.
    /// - Returns: The context, plus a cleanup closure the caller must invoke
    ///   (via `defer`) once done.
    private static func makeTempContext(
        argumentsLine: String = "", argumentHintLine: String = "", body: String = "Body text.\n"
    ) throws -> (context: SkillsToolContext, cleanup: () -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let skillDirectory = root.appendingPathComponent("widget", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let frontmatter =
            "---\nname: widget\ndescription: Does a widget thing.\n\(argumentsLine)\(argumentHintLine)---\n\(body)"
        try frontmatter.write(
            to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let registry = SkillsRegistry(roots: [root])
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        let context = SkillsToolContext(registry: registry, searchAgent: SkillSearchAgent(searcher: searcher))
        return (context, { try? FileManager.default.removeItem(at: root) })
    }

    @Test func useSkillWithAnUnbracketedHintAndTheArgumentSuppliedSucceeds() async throws {
        // `argument-hint: env` (no brackets) still defaults to required --
        // the same default `arguments:`-only and body-inferred parameters
        // use -- but a satisfied required argument must never draw a
        // corrective regardless of which source classified it.
        let (context, cleanup) = try Self.makeTempContext(
            argumentHintLine: "argument-hint: env\n", body: "Value: $0\n")
        defer { cleanup() }

        let output = try await UseSkill(id: "widget", arguments: ["production"]).execute(in: context)

        guard case .success(let result) = output else {
            Issue.record("expected a result outcome, got \(output)")
            return
        }
        #expect(result.body.contains("production"))
    }

    @Test func useSkillWithAnUnbracketedHintAndTheArgumentMissingReturnsACorrective() async throws {
        // Bare `argument-hint: env` has no source marking it optional, so
        // `SkillParameter.required` defaults `true` -- the corrective must
        // still fire, sourced from the structured flag, not from parsing
        // the placeholder text back apart.
        let (context, cleanup) = try Self.makeTempContext(
            argumentHintLine: "argument-hint: env\n", body: "Value: $0\n")
        defer { cleanup() }

        let output = try await UseSkill(id: "widget", arguments: []).execute(in: context)

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("env"))
    }

    @Test func useSkillWithABracketedOptionalHintAndTheArgumentMissingSucceeds() async throws {
        // `[env]` explicitly marks the parameter optional -- omitting it
        // must dispatch successfully, proving the optional case still
        // reads correctly through the structured `required` flag.
        let (context, cleanup) = try Self.makeTempContext(
            argumentHintLine: "argument-hint: \"[env]\"\n", body: "Body text.\n")
        defer { cleanup() }

        let output = try await UseSkill(id: "widget", arguments: []).execute(in: context)

        guard case .success = output else {
            Issue.record("expected a result outcome, got \(output)")
            return
        }
    }

    @Test func useSkillWithArgumentsOnlyNoHintAndTheArgumentMissingReturnsACorrective() async throws {
        // `arguments:` alone (no `argument-hint:`) also defaults every
        // named parameter to required.
        let (context, cleanup) = try Self.makeTempContext(argumentsLine: "arguments: env\n")
        defer { cleanup() }

        let output = try await UseSkill(id: "widget", arguments: []).execute(in: context)

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("env"))
    }

    @Test func useSkillWithABodyInferredParameterAndTheArgumentMissingReturnsACorrective() async throws {
        // No `arguments:`/`argument-hint:` at all -- the sole parameter is
        // synthesized from the body's `$0` reference, always required.
        let (context, cleanup) = try Self.makeTempContext(body: "Value: $0\n")
        defer { cleanup() }

        let output = try await UseSkill(id: "widget", arguments: []).execute(in: context)

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("arg0"))
    }

    // MARK: - Surplus arguments ride the §5 ARGUMENTS: auto-append, never an error

    @Test func useSkillWithMoreArgumentsThanDeclaredSucceedsAndAutoAppendsTheSurplus() async throws {
        // `widget` declares exactly one named parameter (`env`) and its body
        // references only `$0`, never a bare `$ARGUMENTS` -- so a second,
        // undeclared argument has no named slot to land in. Per plan.md §7,
        // the extra must still ride the pass-1 `ARGUMENTS: <value>`
        // no-data-loss fallback rather than causing an error.
        let (context, cleanup) = try Self.makeTempContext(
            argumentsLine: "arguments: env\n", body: "Value: $0\n")
        defer { cleanup() }

        let output = try await UseSkill(id: "widget", arguments: ["production", "extra-flag"]).execute(in: context)

        guard case .success(let result) = output else {
            Issue.record("expected a result outcome, got \(output)")
            return
        }
        #expect(result.body.contains("Value: production"))
        #expect(result.body.contains("ARGUMENTS: production extra-flag"))
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
        // ...but the plural spelling `skills list` does not: there is no
        // noun-normalization lever in the shipped resolver to fold `skills`
        // (plural) onto our declared singular noun `skill`. This is the
        // RESOLVED contract -- plan.md decision #21 was amended to say so
        // explicitly, since the original text overstated what upstream's
        // resolver actually does (no singularization). Pinned here so a
        // future resolver change that adds plural tolerance is noticed
        // (this test would then need updating to expect success, alongside
        // another plan.md amendment).
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

    @Test func resolverDoesNotAcceptRunSkillNowThatRunIsClaimedByRunScript() async throws {
        // M6's `RunScript` claims the `"run"` verb outright (`run script`),
        // so the decision #21 `"run"` -> `use` alias was dropped from
        // `SkillsTool.verbAliasOverrides` (see that table's doc comment):
        // keeping it would have rewritten a literal `"run script"` query to
        // `"use script"`, which doesn't exist, before it ever reached
        // `RunScript`. `"run skill"` therefore no longer resolves to `use
        // skill` -- this is the RESOLVED contract (plan.md decision #21 was
        // amended to say `run` is deliberately not a `use` alias, reserved
        // for `run script`), not a workaround -- pinned here so a future
        // resolver/alias change that reintroduces the collision is caught
        // by a test.
        let tool = try Self.makeFixtureTool()
        let arguments = GeneratedContent(properties: ["op": "run skill", "id": "commit", "arguments": ["fix parser"]])

        let json = try await tool.call(arguments: arguments)

        #expect(json.contains("Unknown operation"))
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

    @Test func fusedToolExposesExactlyTheSixCanonicalOps() throws {
        let tool = try Self.makeFixtureTool()

        #expect(
            tool.operations.map(\.opString) == [
                "search skill", "list skill", "use skill", "list resource", "read resource", "run script",
            ])
        #expect(tool.name == "skills")
    }
}
