import Foundation
import Testing

@testable import FoundationModelsSkills

/// The living contract test for `Examples/skills-demo`:
/// launches the built `skills-demo` executable as a subprocess and asserts
/// on its stdout/exit codes for each acceptance criterion of the demo.
///
/// Mirrors `FoundationModelsExtras`'s own `ExtrasDemoIntegrationTests`
/// subprocess-harness pattern. Deliberately spawns the real binary rather
/// than importing the demo's own types: the point is proving the example's
/// own construction path -- CLI, `--chat`, `--watch`, `--marketplace` --
/// round-trips end to end exactly as a user running it would see.
///
/// The suite is serialized: each case blocks its thread until a subprocess
/// ends, thus cases that ran in parallel would hold every thread of the
/// cooperative pool and starve the timers of the other suites.
@Suite(.serialized) struct SkillsDemoTests {

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

    /// The result of running `skills-demo` to completion: its standard
    /// output, its standard error and its exit code.
    ///
    /// The two streams are kept apart, because the answer of the CLI is on
    /// standard output alone, and a case can then examine standard error by
    /// itself. `skills-demo` bootstraps the logging handler that does
    /// nothing, thus no log record goes to standard error.
    private struct RunResult {
        /// The standard output of the run.
        let standardOutput: String

        /// The standard error of the run.
        let standardError: String

        /// The exit code of the run.
        let exitCode: Int32

        /// Both streams, standard output first. A case that looks for a
        /// message, on either stream, reads this.
        var output: String {
            standardOutput + standardError
        }
    }

    /// Launches the built `skills-demo` executable with `arguments`,
    /// collecting its two output streams and exit code once it exits.
    ///
    /// Standard error is read on a second thread while this thread reads
    /// standard output, thus a full pipe on one stream cannot stop the run.
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
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let errorData = Recorder<Data>()
        let errorDrained = DispatchGroup()
        DispatchQueue.global().async(group: errorDrained) {
            errorData.record(errorPipe.fileHandleForReading.readDataToEndOfFile())
        }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        errorDrained.wait()
        process.waitUntilExit()

        return RunResult(
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData.recorded.joined(), as: UTF8.self),
            exitCode: process.terminationStatus)
    }

    // MARK: - Default CLI mode

    /// The fixture skill that the list and search cases look for.
    private static let commitSkillID = "commit"

    @Test func cliListPrintsEveryFixtureSkill() throws {
        let result = try Self.run(arguments: ["skill", "list"])

        #expect(result.exitCode == 0)
        let answer = try Self.decodedAnswer(result.standardOutput)
        #expect(SkillLineReader.ids(in: answer).contains(Self.commitSkillID))
    }

    /// The arguments of a CLI skill search for the commit skill.
    private static let searchArguments = ["skill", "search", "--query", "commit my changes"]

    /// The arguments of a CLI skill use of the commit skill.
    private static let useArguments = ["skill", "use", "--id", commitSkillID, "--arguments", "fix parser"]

    @Test func cliSearchFindsTheCommitSkillByIntent() throws {
        let result = try Self.run(arguments: Self.searchArguments)

        #expect(result.exitCode == 0)
        let answer = try Self.decodedAnswer(result.standardOutput)
        #expect(SkillLineReader.ids(in: answer).first == Self.commitSkillID)
    }

    /// Decodes the plain answer that the CLI prints as one JSON string.
    ///
    /// The CLI writes each answer as one JSON string and then a line break.
    /// This helper removes that line break and decodes the string.
    ///
    /// - Parameter output: The standard output of the CLI run.
    /// - Returns: The plain text of the answer.
    /// - Throws: A decode error when the output is not one JSON string.
    private static func decodedAnswer(_ output: String) throws -> String {
        let trimmed = output.hasSuffix("\n") ? String(output.dropLast()) : output
        return try JSONDecoder().decode(String.self, from: Data(trimmed.utf8))
    }

    @Test func cliUseRendersTheCommitSkillBodyWithArguments() throws {
        let result = try Self.run(arguments: Self.useArguments)

        #expect(result.exitCode == 0)
        #expect(result.output.contains("fix parser"))
    }

    // MARK: - Telemetry: no "enter" record on standard error

    /// The name of each span that a CLI run can open. The message of the
    /// "enter" record of a span is `enter <span name>`, thus a line that holds
    /// a span name is an "enter" line.
    private static let spanNames = [
        SkillsTracing.SpanName.search, SkillsTracing.SpanName.catalogLoad, SkillsTracing.SpanName.skillLoad,
    ]

    /// `skills-demo` bootstraps the logging handler that does nothing. Thus a
    /// skill search and a skill use, which each open a span and write an
    /// "enter" record, write no "enter" line to standard error.
    ///
    /// - Parameter arguments: The CLI arguments of one run.
    @Test(arguments: [searchArguments, useArguments])
    func cliRunWritesNoEnterLineToStandardError(arguments: [String]) throws {
        let result = try Self.run(arguments: arguments)

        #expect(result.exitCode == 0)
        let enterLines = result.standardError.split(separator: "\n").filter { line in
            Self.spanNames.contains { line.contains($0) }
        }
        #expect(enterLines.isEmpty, "standard error: \(result.standardError)")
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

    /// The start of the line that `--watch` writes once it is watching.
    private static let watchStartedMarker = "Watching "

    @Test func watchModeStartsThenExitsCleanlyOnSIGTERM() throws {
        let process = Process()
        process.executableURL = try Self.skillsDemoBinary()
        process.arguments = ["--watch"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        // The start-up line is the signal that the mode is up; a fixed wait
        // would race the process start under a loaded parallel run.
        var output = Data()
        while !String(decoding: output, as: UTF8.self).contains(Self.watchStartedMarker) {
            let chunk = outputPipe.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            output.append(chunk)
        }
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
        environment[MarketplaceStore.cacheDirectoryVariable] = cacheDirectory.path
        return environment
    }
}
