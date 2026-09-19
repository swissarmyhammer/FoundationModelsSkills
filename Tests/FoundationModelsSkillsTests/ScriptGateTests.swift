import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsSkills

/// Tests that the gates of `run script` read the host `RenderPolicy` and the
/// `allowed-tools` grant of the skill, and no property of the layer that
/// gives the script (marketplace.md §6.6).
///
/// The grant of a marketplace is gone. A marketplace layer is untrusted like
/// a `user` layer or a `project` layer, thus `ScriptGate` takes no
/// marketplace input at all. Each test of this file runs one script two
/// times -- one time from a marketplace layer, one time from a local layer
/// -- and holds the two runs to the same rule.
struct ScriptGateTests {
    /// Which layer of the registry gives the skill of a test.
    ///
    /// A test takes one of these as its parameter, thus the type is as
    /// visible as the test itself: a parameter of a test function cannot
    /// carry a type that is less visible than the function.
    internal enum LayerKind: CaseIterable, CustomStringConvertible {
        /// A marketplace layer, which sits below every local layer.
        case marketplace

        /// A local `project` layer.
        case local

        /// The name of the layer, for the message of an expectation.
        var description: String {
            switch self {
            case .marketplace: return "a marketplace layer"
            case .local: return "a local layer"
            }
        }
    }

    /// The id of the skill each test of this file gives one layer.
    private static let skillID = "gated-script"

    /// The file name of the script of that skill.
    private static let scriptName = "run.sh"

    /// The skill-relative path of that script.
    private static let scriptPath = "scripts/\(scriptName)"

    /// The display id of the marketplace of the marketplace fixture.
    private static let marketplaceID = "a-marketplace"

    /// The commit of the snapshot of that marketplace.
    private static let marketplaceSHA = "sha-1"

    /// The host policy that stops every script.
    private static let scriptsDisabledPolicy = RenderPolicy(isScriptExecutionDisabled: true)

    /// A granted script runs, whichever layer gives it.
    @Test(arguments: LayerKind.allCases)
    func aGrantedScriptRuns(layer: LayerKind) async throws {
        let fixture = try Self.makeFixture(
            skillGivenBy: layer, allowedTools: ResourceTestSupport.everyScriptGrant, policy: RenderPolicy())
        defer { LayerFixtureSupport.removeDirectories(fixture.directories) }

        let output = try await RunScript(id: Self.skillID, path: Self.scriptPath).execute(in: fixture.context)

        let result = try #require(
            ResourceTestSupport.successResult(of: output), "expected a success outcome from \(layer), got \(output)")
        #expect(result.status == "completed")
        #expect(result.exitCode == 0)
    }

    /// A host policy that stops script execution stops the script, whichever
    /// layer gives it.
    @Test(arguments: LayerKind.allCases)
    func aDisabledHostPolicyStopsAGrantedScript(layer: LayerKind) async throws {
        let fixture = try Self.makeFixture(
            skillGivenBy: layer, allowedTools: ResourceTestSupport.everyScriptGrant,
            policy: Self.scriptsDisabledPolicy)
        defer { LayerFixtureSupport.removeDirectories(fixture.directories) }

        let output = try await RunScript(id: Self.skillID, path: Self.scriptPath).execute(in: fixture.context)

        let message = try #require(
            ResourceTestSupport.correctiveMessage(of: output),
            "expected a corrective outcome from \(layer), got \(output)")
        #expect(message == "Script execution is disabled for this registry.", "\(layer)")
    }

    /// A skill with no `allowed-tools` grant runs no script, whichever layer
    /// gives it.
    @Test(arguments: LayerKind.allCases)
    func aSkillWithNoGrantRunsNoScript(layer: LayerKind) async throws {
        let fixture = try Self.makeFixture(skillGivenBy: layer, allowedTools: nil, policy: RenderPolicy())
        defer { LayerFixtureSupport.removeDirectories(fixture.directories) }

        let output = try await RunScript(id: Self.skillID, path: Self.scriptPath).execute(in: fixture.context)

        let message = try #require(
            ResourceTestSupport.correctiveMessage(of: output),
            "expected a corrective outcome from \(layer), got \(output)")
        #expect(message.contains("not pre-approved"), "\(layer)")
    }

    /// One assembled fixture: the context to dispatch against, and every
    /// directory the fixture made.
    private struct Fixture {
        /// The context of the registry that holds the skill.
        let context: SkillsToolContext

        /// The directories of the fixture, for the cleanup of the test.
        let directories: [URL]
    }

    /// Writes the skill and its script in one layer root, and builds the
    /// context of a registry that gives that root as `layer`.
    ///
    /// The skill and the script are the same for each layer, thus a
    /// difference between two outcomes can only come from the layer.
    ///
    /// - Parameters:
    ///   - layer: Which layer of the registry gives the skill.
    ///   - allowedTools: The raw `allowed-tools:` value of the `SKILL.md`,
    ///     or `nil` for a skill with no grant.
    ///   - policy: The render policy of the registry.
    /// - Returns: The fixture.
    /// - Throws: Whatever the fixture writers of `ResourceTestSupport` and
    ///   `WatcherTestSupport` throw.
    private static func makeFixture(
        skillGivenBy layer: LayerKind, allowedTools: String?, policy: RenderPolicy
    ) throws -> Fixture {
        let skillRoot = try WatcherTestSupport.makeTempDirectory()
        try ResourceTestSupport.writeMinimalSkillFile(id: Self.skillID, in: skillRoot, allowedTools: allowedTools)
        try ResourceTestSupport.writeExecutableShebangScript(
            named: Self.scriptName, inSkillID: Self.skillID, under: skillRoot)

        switch layer {
        case .local:
            return Fixture(
                context: ResourceTestSupport.makeContext(roots: [skillRoot], policy: policy),
                directories: [skillRoot])
        case .marketplace:
            let localRoot = try WatcherTestSupport.makeTempDirectory()
            return Fixture(
                context: Self.makeMarketplaceContext(
                    marketplaceRoot: skillRoot, localRoot: localRoot, policy: policy),
                directories: [skillRoot, localRoot])
        }
    }

    /// Builds a `SkillsToolContext` over a registry whose one marketplace
    /// layer is `marketplaceRoot`, with `localRoot` as the local project
    /// layer above it.
    ///
    /// - Parameters:
    ///   - marketplaceRoot: The layer root of the marketplace.
    ///   - localRoot: The root of the local project layer.
    ///   - policy: The render policy of the registry.
    /// - Returns: The assembled context.
    private static func makeMarketplaceContext(
        marketplaceRoot: URL, localRoot: URL, policy: RenderPolicy
    ) -> SkillsToolContext {
        var stack = DotfolderStack(name: "skills", workingDirectory: localRoot, environment: [:])
        stack.layers = [DotfolderStack.Layer(source: .project, root: localRoot)]
        let provider = FakeMarketplaceProvider(layers: [
            MarketplaceTestSupport.makeMarketplaceLayer(
                root: marketplaceRoot, id: Self.marketplaceID, sha: Self.marketplaceSHA)
        ])
        return ResourceTestSupport.makeContext(
            registry: SkillsRegistry(marketplaces: provider, stack: stack, policy: policy))
    }
}
