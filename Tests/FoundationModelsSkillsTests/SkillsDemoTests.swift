import Foundation
import Testing

@testable import FoundationModelsSkills

/// The living contract test for `Examples/skills-demo` (plan.md §11):
/// launches the built `skills-demo` executable as a subprocess and asserts
/// on its stdout/exit codes for every `^spe0vvs` acceptance criterion.
///
/// Mirrors `FoundationModelsExtras`'s own `ExtrasDemoIntegrationTests`
/// subprocess-harness pattern. Deliberately spawns the real binary rather
/// than importing the demo's own types: the point is proving the example's
/// own construction path -- CLI, `--chat`, `--watch`, `--marketplace` --
/// round-trips end to end exactly as a user running it would see.
@Suite struct SkillsDemoTests {

    // MARK: - Locating the built binary

    /// The built `skills-demo` executable, located next to the running test
    /// bundle, or under `.build/debug/` as a fallback.
    ///
    /// Declared as a dependency of the test target (via the shared
    /// `skills-demo` executable target), so `swift test` builds it first.
    private static func skillsDemoBinary() throws -> URL {
        var candidates: [URL] = []
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            candidates.append(bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("skills-demo"))
        }
        candidates.append(FixtureLibrary.packageRoot().appendingPathComponent(".build/debug/skills-demo"))
        guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw BinaryNotFoundError(candidates: candidates)
        }
        return binary
    }

    /// Raised by the subprocess harness itself when no built binary is
    /// found.
    private struct BinaryNotFoundError: Error, CustomStringConvertible {
        let candidates: [URL]
        var description: String { "skills-demo binary not found among: \(candidates.map(\.path))" }
    }

    // MARK: - Subprocess harness

    /// The result of running `skills-demo` to completion: its combined
    /// output and exit code.
    private struct RunResult {
        let output: String
        let exitCode: Int32
    }

    /// Launches the built `skills-demo` executable with `arguments`,
    /// collecting its combined output and exit code once it exits.
    ///
    /// - Parameters:
    ///   - arguments: The command-line arguments to pass.
    ///   - environment: The subprocess environment. Defaults to this
    ///     process's own.
    private static func run(
        arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> RunResult {
        let process = Process()
        process.executableURL = try Self.skillsDemoBinary()
        process.arguments = arguments
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return RunResult(output: String(decoding: data, as: UTF8.self), exitCode: process.terminationStatus)
    }

    // MARK: - Default CLI mode

    /// The fixture skill that the list and search cases look for.
    private static let commitSkillID = "commit"

    @Test func cliListPrintsEveryFixtureSkill() throws {
        let result = try Self.run(arguments: ["skill", "list"])

        #expect(result.exitCode == 0)
        let answer = try Self.decodedAnswer(result.output)
        #expect(SkillLineReader.ids(in: answer).contains(Self.commitSkillID))
    }

    @Test func cliSearchFindsTheCommitSkillByIntent() throws {
        let result = try Self.run(arguments: ["skill", "search", "--query", "commit my changes"])

        #expect(result.exitCode == 0)
        let answer = try Self.decodedAnswer(result.output)
        #expect(SkillLineReader.ids(in: answer).first == Self.commitSkillID)
    }

    /// Decodes the plain answer that the CLI prints as one JSON string.
    ///
    /// The CLI writes each answer as one JSON string and then a line break.
    /// This helper removes that line break and decodes the string.
    ///
    /// - Parameter output: The output of the CLI run.
    /// - Returns: The plain text of the answer.
    /// - Throws: A decode error when the output is not one JSON string.
    private static func decodedAnswer(_ output: String) throws -> String {
        let trimmed = output.hasSuffix("\n") ? String(output.dropLast()) : output
        return try JSONDecoder().decode(String.self, from: Data(trimmed.utf8))
    }

    @Test func cliUseRendersTheCommitSkillBodyWithArguments() throws {
        let result = try Self.run(arguments: ["skill", "use", "--id", "commit", "--arguments", "fix parser"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("fix parser"))
    }

    // MARK: - `--chat` mode: the deterministic forced-unavailable seam

    @Test func chatModeDegradesCleanlyWhenForcedUnavailable() throws {
        var environment = ProcessInfo.processInfo.environment
        environment["SKILLS_DEMO_FORCE_UNAVAILABLE"] = "1"

        let result = try Self.run(arguments: ["--chat"], environment: environment)

        #expect(result.exitCode == 0)
        #expect(
            result.output.contains(
                "Foundation Models unavailable on this device (forced unavailable for testing); skipping live validation."
            ))
    }

    // MARK: - `--watch` mode: starts and exits cleanly on SIGTERM

    @Test func watchModeStartsThenExitsCleanlyOnSIGTERM() throws {
        let process = Process()
        process.executableURL = try Self.skillsDemoBinary()
        process.arguments = ["--watch"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        Thread.sleep(forTimeInterval: 1)
        #expect(process.isRunning)

        process.terminate()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
    }

    // MARK: - `--marketplace` mode: the marketplace command group

    /// The flag that switches the demo into marketplace control mode.
    private static let marketplaceFlag = "--marketplace"

    /// The alias of the one marketplace of the fixture `marketplaces.yaml`.
    private static let fixtureMarketplaceAlias = "demo-skills"

    /// A subcommand name that the `marketplace` command group does not hold.
    private static let unknownSubcommand = "no-such-subcommand"

    @Test func marketplaceModeListsTheConfiguredSources() throws {
        try WatcherTestSupport.withTempDirectory { cacheDirectory in
            let result = try Self.run(
                arguments: [Self.marketplaceFlag, "list"],
                environment: Self.environment(cacheDirectory: cacheDirectory))

            #expect(result.exitCode == 0)
            #expect(result.output.contains(Self.fixtureMarketplaceAlias))
        }
    }

    @Test func marketplaceModeFailsOnAnUnknownSubcommand() throws {
        try WatcherTestSupport.withTempDirectory { cacheDirectory in
            let result = try Self.run(
                arguments: [Self.marketplaceFlag, Self.unknownSubcommand],
                environment: Self.environment(cacheDirectory: cacheDirectory))

            #expect(result.exitCode != 0)
            #expect(result.output.contains(Self.unknownSubcommand))
        }
    }

    /// The subprocess environment that names one temporary cache folder, thus
    /// no marketplace case reads or writes the cache folder of this user.
    ///
    /// - Parameter cacheDirectory: The folder that holds the cache.
    /// - Returns: The environment of this process, with the cache variable set.
    private static func environment(cacheDirectory: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment[MarketplaceCache.cacheVariable] = cacheDirectory.path
        return environment
    }
}
