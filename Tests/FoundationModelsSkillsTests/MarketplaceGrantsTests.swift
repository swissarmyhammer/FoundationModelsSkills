import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Tests for the marketplace.md §6.6 per-marketplace grants: a marketplace
/// skill gets no shell injection and no `run script` unless the host grants
/// them for that marketplace, the host `RenderPolicy` always wins over a
/// grant, and a local skill keeps the behavior it had before.
struct MarketplaceGrantsTests {
    /// The id of the marketplace skill that holds a shell injection.
    private static let marketplaceShellSkillID = "marketplace-shell"

    /// The id of the local skill that holds the same shell injection.
    private static let localShellSkillID = "local-shell"

    /// The id of the marketplace skill that holds a script and an
    /// `allowed-tools:` grant for it.
    private static let marketplaceScriptSkillID = "marketplace-script"

    /// The id of the marketplace skill that holds a script and no
    /// `allowed-tools:` grant.
    private static let ungrantedScriptSkillID = "marketplace-script-no-tools"

    /// The id of the local skill that holds a script and an `allowed-tools:`
    /// grant for it.
    private static let localScriptSkillID = "local-script"

    /// The body every shell fixture skill carries: one shell injection.
    private static let shellBody = "Greeting: !`echo hi`"

    /// The text the shell injection writes when it runs.
    private static let shellOutput = "hi"

    /// The `allowed-tools:` value that grants every script of a skill.
    private static let scriptGrant = "Script(scripts/*)"

    /// The file name of every fixture script.
    private static let scriptName = "run.sh"

    /// The path of every fixture script, relative to its skill directory.
    private static let scriptPath = "scripts/\(scriptName)"

    /// The corrective message of the host-policy gate of `run script`.
    private static let scriptsDisabledMessage = "Script execution is disabled for this registry."

    /// The `status` of a script that ran to its end.
    private static let completedStatus = "completed"

    /// Part of the corrective message of the `allowed-tools:` gate.
    private static let noAllowedToolsGrantText = "not pre-approved"

    // MARK: - Shell injection (§6.6)

    @Test func aMarketplaceSkillGetsTheDisabledMarkerWithTheDefaultGrants() throws {
        let fixture = try Fixture()
        defer { fixture.removeRoots() }
        let registry = fixture.makeRegistry(grants: .none)

        let body = try registry.call(id: Self.marketplaceShellSkillID)

        #expect(body.contains(ShellInjection.disabledMarker))
        #expect(!body.contains(Self.shellOutput))
    }

    @Test func aShellInjectionGrantLetsAMarketplaceSkillRunItsCommand() throws {
        let fixture = try Fixture()
        defer { fixture.removeRoots() }
        let registry = fixture.makeRegistry(grants: MarketplaceGrants(shellInjection: true))

        let body = try registry.call(id: Self.marketplaceShellSkillID)

        #expect(body.contains(Self.shellOutput))
        #expect(!body.contains(ShellInjection.disabledMarker))
    }

    @Test func aHostPolicyThatDisablesShellWinsOverTheShellInjectionGrant() throws {
        let fixture = try Fixture()
        defer { fixture.removeRoots() }
        let registry = fixture.makeRegistry(
            grants: MarketplaceGrants(shellInjection: true),
            policy: RenderPolicy(isShellExecutionDisabled: true))

        let body = try registry.call(id: Self.marketplaceShellSkillID)

        #expect(body.contains(ShellInjection.disabledMarker))
    }

    @Test func aLocalSkillStillRunsItsShellInjectionWhileTheMarketplaceHasNoGrant() throws {
        let fixture = try Fixture()
        defer { fixture.removeRoots() }
        let registry = fixture.makeRegistry(grants: .none)

        let body = try registry.call(id: Self.localShellSkillID)

        #expect(body.contains(Self.shellOutput))
        #expect(!body.contains(ShellInjection.disabledMarker))
    }

    // MARK: - run script (§6.6)

    @Test func runScriptInAMarketplaceSkillIsRefusedWithTheDefaultGrants() async throws {
        let fixture = try Fixture()
        defer { fixture.removeRoots() }
        let context = fixture.makeContext(grants: .none)

        let output = try await RunScript(id: Self.marketplaceScriptSkillID, path: Self.scriptPath)
            .execute(in: context)

        #expect(Self.correctiveMessage(of: output) == Self.scriptsDisabledMessage)
    }

    @Test func aScriptsGrantAndAnAllowedToolsGrantLetAMarketplaceScriptRun() async throws {
        let fixture = try Fixture()
        defer { fixture.removeRoots() }
        let context = fixture.makeContext(grants: MarketplaceGrants(scripts: true))

        let output = try await RunScript(id: Self.marketplaceScriptSkillID, path: Self.scriptPath)
            .execute(in: context)

        let result = try #require(Self.successResult(of: output))
        #expect(result.status == Self.completedStatus)
        #expect(result.exitCode == 0)
    }

    @Test func aScriptsGrantWithoutAnAllowedToolsGrantIsStillRefused() async throws {
        let fixture = try Fixture()
        defer { fixture.removeRoots() }
        let context = fixture.makeContext(grants: MarketplaceGrants(scripts: true))

        let output = try await RunScript(id: Self.ungrantedScriptSkillID, path: Self.scriptPath)
            .execute(in: context)

        #expect(Self.correctiveMessage(of: output)?.contains(Self.noAllowedToolsGrantText) == true)
    }

    @Test func aHostPolicyThatDisablesScriptsWinsOverTheScriptsGrant() async throws {
        let fixture = try Fixture()
        defer { fixture.removeRoots() }
        let context = fixture.makeContext(
            grants: MarketplaceGrants(scripts: true),
            policy: RenderPolicy(isScriptExecutionDisabled: true))

        let output = try await RunScript(id: Self.marketplaceScriptSkillID, path: Self.scriptPath)
            .execute(in: context)

        #expect(Self.correctiveMessage(of: output) == Self.scriptsDisabledMessage)
    }

    @Test func aLocalScriptStillRunsWhileTheMarketplaceHasNoGrant() async throws {
        let fixture = try Fixture()
        defer { fixture.removeRoots() }
        let context = fixture.makeContext(grants: .none)

        let output = try await RunScript(id: Self.localScriptSkillID, path: Self.scriptPath).execute(in: context)

        let result = try #require(Self.successResult(of: output))
        #expect(result.status == Self.completedStatus)
        #expect(result.exitCode == 0)
    }

    // MARK: - Helpers

    /// The message of a corrective outcome, or `nil` for a success outcome.
    ///
    /// - Parameter output: The outcome of one `run script` call.
    /// - Returns: The corrective message, or `nil`.
    private static func correctiveMessage(of output: RunScriptOutput) -> String? {
        if case .corrective(let message) = output {
            return message
        }
        return nil
    }

    /// The result of a success outcome, or `nil` for a corrective outcome.
    ///
    /// - Parameter output: The outcome of one `run script` call.
    /// - Returns: The result, or `nil`.
    private static func successResult(of output: RunScriptOutput) -> RunScriptResult? {
        if case .success(let result) = output {
            return result
        }
        return nil
    }

    /// One marketplace root and one local project root, each holding a skill
    /// with a shell injection and a skill with a script.
    private struct Fixture {
        /// The root of the marketplace layer.
        let marketplaceRoot: URL

        /// The root of the local project layer.
        let localRoot: URL

        /// Writes both roots.
        ///
        /// - Throws: The error of a folder or file write.
        init() throws {
            marketplaceRoot = try MarketplaceTestSupport.makeTempDirectory()
            localRoot = try MarketplaceTestSupport.makeTempDirectory()

            try ReloadTestSupport.writeSkillFile(
                id: MarketplaceGrantsTests.marketplaceShellSkillID, in: marketplaceRoot,
                body: MarketplaceGrantsTests.shellBody)
            try ReloadTestSupport.writeSkillFile(
                id: MarketplaceGrantsTests.localShellSkillID, in: localRoot,
                body: MarketplaceGrantsTests.shellBody)

            try Fixture.writeScriptSkill(
                id: MarketplaceGrantsTests.marketplaceScriptSkillID, in: marketplaceRoot,
                allowedTools: MarketplaceGrantsTests.scriptGrant)
            try Fixture.writeScriptSkill(
                id: MarketplaceGrantsTests.ungrantedScriptSkillID, in: marketplaceRoot, allowedTools: nil)
            try Fixture.writeScriptSkill(
                id: MarketplaceGrantsTests.localScriptSkillID, in: localRoot,
                allowedTools: MarketplaceGrantsTests.scriptGrant)
        }

        /// Builds a registry over one marketplace layer carrying `grants`,
        /// with the local project root above it.
        ///
        /// - Parameters:
        ///   - grants: What the host lets the skills of that marketplace run.
        ///   - policy: The host render policy. The default is the permissive
        ///     `RenderPolicy()`.
        /// - Returns: The registry, with watching off.
        func makeRegistry(grants: MarketplaceGrants, policy: RenderPolicy = RenderPolicy()) -> SkillsRegistry {
            var stack = DotfolderStack(name: "skills", workingDirectory: localRoot, environment: [:])
            stack.layers = [DotfolderStack.Layer(source: .project, root: localRoot)]
            let provider = FakeMarketplaceProvider(layers: [
                MarketplaceTestSupport.makeMarketplaceLayer(
                    root: marketplaceRoot, id: "granting-marketplace", sha: "sha-1", grants: grants)
            ])
            return SkillsRegistry(marketplaces: provider, stack: stack, policy: policy)
        }

        /// Builds a `run script` context over the registry of `grants`.
        ///
        /// - Parameters:
        ///   - grants: What the host lets the skills of that marketplace run.
        ///   - policy: The host render policy. The default is the permissive
        ///     `RenderPolicy()`.
        /// - Returns: The assembled context.
        func makeContext(grants: MarketplaceGrants, policy: RenderPolicy = RenderPolicy()) -> SkillsToolContext {
            ResourceTestSupport.makeContext(registry: makeRegistry(grants: grants, policy: policy))
        }

        /// Removes both roots.
        func removeRoots() {
            try? FileManager.default.removeItem(at: marketplaceRoot)
            try? FileManager.default.removeItem(at: localRoot)
        }

        /// Writes one skill that holds an executable script under `scripts/`.
        ///
        /// - Parameters:
        ///   - id: The skill id.
        ///   - directory: The layer root to write under.
        ///   - allowedTools: The raw `allowed-tools:` value, or `nil` to omit
        ///     the field.
        /// - Throws: The error of a folder or file write.
        private static func writeScriptSkill(id: String, in directory: URL, allowedTools: String?) throws {
            try ResourceTestSupport.writeMinimalSkillFile(id: id, in: directory, allowedTools: allowedTools)
            try ResourceTestSupport.writeExecutableShebangScript(
                named: MarketplaceGrantsTests.scriptName, inSkillID: id, under: directory)
        }
    }
}
