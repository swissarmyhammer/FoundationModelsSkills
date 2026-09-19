import Foundation
import FoundationModels
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
        #expect(try Self.listedIDs(result.output).contains("commit"))
    }

    @Test func searchVerbSearchesTheUserVisibleCatalog() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "search", "--query", "commit"])

        #expect(result.exitCode == 0)
        #expect(try Self.listedIDs(result.output).contains("commit"))
    }

    @Test func useVerbRendersCommitSubstitutingArguments() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "use", "--id", "commit", "--arguments", "fix parser"])

        #expect(result.exitCode == 0)
        #expect(
            try Self.decodedText(result.output)
                == Self.makeFixtureRegistry().call(id: "commit", arguments: ["fix parser"]))
    }

    // MARK: - CLI syntax: positional id vs --id flag (§7.2, resolved contract)

    @Test func useVerbWithABarePositionalIDIsSilentlyDroppedNotDispatched() async throws {
        // §7.2's originally-drafted example (`use deploy --arguments
        // production`) never actually worked: the macro-less fallback CLI
        // leaf (`FallbackOperationCommand`/`FallbackPayloadBuilder` in
        // `../FoundationModelsOperationTool`) recognizes only `--name
        // value`/`-short` flags -- a bare positional token right after the
        // verb is silently dropped, never populating `id`. This is the
        // RESOLVED contract (plan.md §7.2 was amended to require `--id`),
        // pinned here so a future upstream positional-parameter change is
        // noticed.
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "use", "deploy", "--arguments", "production"])

        #expect(result.exitCode == 0)
        // No `id` was ever resolved -- the resolver's own missing-required-
        // parameter corrective fires, naming `id`, not a rendered body.
        #expect(!result.output.contains("\"id\":\"deploy\""))
        #expect(result.output.contains("id"))
    }

    @Test func useVerbWithTheIDFlagDispatchesCorrectly() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "use", "--id", "deploy", "--arguments", "production"])

        #expect(result.exitCode == 0)
        #expect(
            try Self.decodedText(result.output)
                == Self.makeFixtureRegistry().call(id: "deploy", arguments: ["production"]))
    }

    @Test func useVerbHonorsShellExecutionDisabledPolicy() async throws {
        // §25 coverage gap (^zbv0t4j): the disable flag was previously never
        // proven on the CLI path -- `skill use` dispatches through the exact
        // same `call(id:arguments:)` render call the model surface uses.
        let registry = SkillsRegistry(
            roots: [Self.projectSkillsRoot], policy: RenderPolicy(isShellExecutionDisabled: true))
        let driver = try SkillsCLI.makeDriver(registry: registry)

        let result = await driver.run(arguments: ["skill", "use", "--id", "git-context"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains(ShellInjection.disabledMarker))
        #expect(!result.output.contains("on branch main, working tree clean"))
    }

    // MARK: - Visibility matrix (plan.md §6)

    @Test func listVerbIncludesDeployWhichIsHiddenFromTheModelSurface() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "list"])

        // `deploy` (`disable-model-invocation: true`) is model-hidden but
        // user-visible -- the opposite polarity from `SkillOperationsTests`'
        // `listSkillDispatchReturnsTheLineOfEachVisibleSkill`, which asserts
        // the model surface never lists it.
        #expect(try Self.listedIDs(result.output).contains("deploy"))
    }

    @Test func listVerbExcludesLintWhichIsModelOnly() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "list"])

        // `lint` (`user-invocable: false`) is model-only background work --
        // never listed on this user-facing CLI surface.
        let ids = try Self.listedIDs(result.output)
        #expect(!ids.isEmpty, "the list must give skill lines, or this case proves nothing")
        #expect(!ids.contains("lint"))
    }

    @Test func useVerbRendersDeployWhichIsHiddenFromTheModelSurface() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "use", "--id", "deploy"])

        #expect(result.exitCode == 0)
        #expect(try Self.decodedText(result.output) == Self.makeFixtureRegistry().call(id: "deploy"))
    }

    @Test func useVerbRefusesLintWhichIsModelOnly() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "use", "--id", "lint"])

        #expect(result.exitCode == 0)
        #expect(result.output.hasPrefix("\""))
        #expect(result.output.contains("is not currently usable"))
        #expect(!result.output.contains("\"id\":\"lint\""))
    }

    @Test func useVerbsUnusableIDMessageListsOnlyUserVisibleIDs() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["skill", "use", "--id", "lint"])
        #expect(result.output.hasPrefix("\""))
        let usableIDsList = try #require(result.output.components(separatedBy: "Currently usable ids: ").last)

        // The corrective's "currently usable ids" list is this surface's own
        // (§6 user-facing) visible set, not the model-facing one: it must
        // name `deploy` (user-visible, model-hidden) but never the
        // model-only `lint` that was just refused.
        #expect(usableIDsList.contains("deploy"))
        #expect(!usableIDsList.contains("lint"))
    }

    // MARK: - Resource op invocations (§7.2/§7.3, ^kb2t82c)

    @Test func resourceListVerbListsReleaseNotesResources() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["resource", "list", "--id", "release-notes"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("\"total\":3"))
    }

    @Test func resourceReadVerbReadsTheBuildScript() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(
            arguments: ["resource", "read", "--id", "release-notes", "--path", "scripts/build.sh"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("building release notes"))
    }

    @Test func scriptRunVerbExecutesTheBuildScript() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(
            arguments: ["script", "run", "--id", "release-notes", "--path", "scripts/build.sh"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("building release notes"))
    }

    @Test func resourceListVerbRefusesLintWhichIsModelOnly() async throws {
        // `release-notes` is visible on both surfaces (no visibility
        // flags); `lint` is model-only -- the CLI's user surface must
        // refuse it the same way `skill use --id lint` already does.
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["resource", "list", "--id", "lint"])

        #expect(result.exitCode == 0)
        #expect(result.output.hasPrefix("\""))
        #expect(result.output.contains("is not currently usable"))
    }

    @Test func resourceListVerbReachesDeployWhichIsHiddenFromTheModelSurface() async throws {
        let driver = try Self.makeFixtureDriver()

        let result = await driver.run(arguments: ["resource", "list", "--id", "deploy"])

        #expect(result.exitCode == 0)
        // A corrective outcome serializes as a bare JSON string (plan.md
        // §7); a successful `ListResourceResult` serializes as a `{...}`
        // object, so a non-corrective result never starts with `"`.
        #expect(!result.output.hasPrefix("\""))
    }

    // MARK: - Round trip: CLI payload == model payload (§7.2)

    @Test func searchVerbRoundTripsToTheIdenticalModelDispatchOutput() async throws {
        let registry = Self.makeFixtureRegistry()
        let driver = try SkillsCLI.makeDriver(registry: registry)
        let modelTool = try Self.makeModelTool(registry: registry)

        let cliResult = await driver.run(arguments: ["skill", "search", "--query", "commit"])
        let modelOutput = try await modelTool.call(arguments: GeneratedContent(properties: ["op": "search skill", "query": "commit"]))

        // The CLI prints the JSON string of the answer; the model gets the
        // same answer as plain text.
        #expect(cliResult.exitCode == 0)
        #expect(try Self.decodedText(cliResult.output) == modelOutput)
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
        #expect(try Self.decodedText(cliResult.output) == modelOutput)
    }

    @Test func useVerbRoundTripsToTheIdenticalModelDispatchOutputForCommit() async throws {
        let registry = Self.makeFixtureRegistry()
        let driver = try SkillsCLI.makeDriver(registry: registry)
        let modelTool = try Self.makeModelTool(registry: registry)

        let cliResult = await driver.run(arguments: ["skill", "use", "--id", "commit", "--arguments", "fix parser"])
        let modelOutput = try await modelTool.call(
            arguments: GeneratedContent(properties: ["op": "use skill", "id": "commit", "arguments": ["fix parser"]]))

        // The CLI prints the JSON string of the body; the model gets the
        // same body as plain text.
        #expect(cliResult.exitCode == 0)
        #expect(try Self.decodedText(cliResult.output) == modelOutput)
    }

    @Test func resourceListVerbRoundTripsToTheIdenticalModelDispatchOutput() async throws {
        let registry = Self.makeFixtureRegistry()
        let driver = try SkillsCLI.makeDriver(registry: registry)
        let modelTool = try Self.makeModelTool(registry: registry)

        let cliResult = await driver.run(arguments: ["resource", "list", "--id", "release-notes"])
        let modelOutput = try await modelTool.call(
            arguments: GeneratedContent(properties: ["op": "list resource", "id": "release-notes"]))

        #expect(cliResult.exitCode == 0)
        #expect(cliResult.output == modelOutput)
    }

    @Test func resourceReadVerbRoundTripsToTheIdenticalModelDispatchOutput() async throws {
        let registry = Self.makeFixtureRegistry()
        let driver = try SkillsCLI.makeDriver(registry: registry)
        let modelTool = try Self.makeModelTool(registry: registry)

        let cliResult = await driver.run(
            arguments: ["resource", "read", "--id", "release-notes", "--path", "scripts/build.sh"])
        let modelOutput = try await modelTool.call(
            arguments: GeneratedContent(
                properties: ["op": "read resource", "id": "release-notes", "path": "scripts/build.sh"]))

        #expect(cliResult.exitCode == 0)
        #expect(cliResult.output == modelOutput)
    }

    @Test func scriptRunVerbRoundTripsToTheIdenticalModelDispatchOutput() async throws {
        let registry = Self.makeFixtureRegistry()
        let driver = try SkillsCLI.makeDriver(registry: registry)
        let modelTool = try Self.makeModelTool(registry: registry)

        let cliResult = await driver.run(
            arguments: ["script", "run", "--id", "release-notes", "--path", "scripts/build.sh"])
        let modelOutput = try await modelTool.call(
            arguments: GeneratedContent(
                properties: ["op": "run script", "id": "release-notes", "path": "scripts/build.sh"]))

        #expect(cliResult.exitCode == 0)
        // `run script` dispatches through a real subprocess -- the CLI path
        // and the model path above are two genuinely independent process
        // executions, so their real (post-`durationMs`-truncation-fix)
        // wall-clock durations never reliably match. Every other field,
        // deterministic for this fixture, still must round-trip
        // byte-for-byte.
        #expect(Self.strippingDurationMs(from: cliResult.output) == Self.strippingDurationMs(from: modelOutput))
        #expect(cliResult.output.contains("\"durationMs\":"))
        #expect(modelOutput.contains("\"durationMs\":"))
    }

    /// Strips the genuinely time-variant `"durationMs":<n>` field out of a
    /// `run script` result payload, replacing it with a fixed placeholder --
    /// `scriptRunVerbRoundTripsToTheIdenticalModelDispatchOutput()`'s two
    /// dispatches are independent subprocess executions, so their real
    /// wall-clock durations are never expected to match; every other field
    /// still round-trips byte-for-byte.
    ///
    /// - Parameter json: A `run script` result payload's raw JSON text.
    /// - Returns: `json` with its `durationMs` value normalized to `0`.
    private static func strippingDurationMs(from json: String) -> String {
        json.replacingOccurrences(of: #""durationMs":\d+"#, with: "\"durationMs\":0", options: .regularExpression)
    }

    /// Decodes the CLI output of `skill search`, `skill list`, or
    /// `skill use`: one JSON string, the plain text of the answer or a
    /// corrective sentence.
    ///
    /// The CLI prints the JSON of each operation. The model surface gives
    /// the same string as plain text.
    ///
    /// - Parameter output: The printed output of the CLI.
    /// - Returns: The string value.
    /// - Throws: A decode error when `output` is not one JSON string.
    private static func decodedText(_ output: String) throws -> String {
        try JSONDecoder().decode(String.self, from: Data(output.utf8))
    }

    /// The skill ids of the CLI output of `skill search` or `skill list`, in
    /// the order of the answer.
    ///
    /// - Parameter output: The printed output of the CLI.
    /// - Returns: The id of each skill line.
    /// - Throws: A decode error when `output` is not one JSON string.
    private static func listedIDs(_ output: String) throws -> [String] {
        SkillLineReader.ids(in: try decodedText(output))
    }

    /// Builds the model-facing fused tool over `registry`, via the same
    /// `FixtureLibrary.makeSkillsToolContext(registry:)` helper
    /// `SkillOperationsTests.makeFixtureContext()` uses.
    private static func makeModelTool(registry: SkillsRegistry) throws -> SkillsCatalogTool {
        try SkillsTool.make(context: FixtureLibrary.makeSkillsToolContext(registry: registry))
    }
}
