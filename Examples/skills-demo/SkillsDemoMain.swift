import Foundation
import FoundationModelsSkills
import Logging
import Operations
import OperationsCLI

/// The `skills-demo` executable's entry point: a worked example of the full
/// stack, in four modes.
///
/// - Default -- CLI: `skills-demo skill list`, `skills-demo skill
///   search "commit my changes"`, `skills-demo skill use --id commit
///   --arguments "fix parser"`, over the fixture library.
/// - `--chat` -- scripted live-model validation via `ChatMode`, gated on
///   `SystemLanguageModel` availability (or `SKILLS_DEMO_FORCE_UNAVAILABLE`).
/// - `--watch` -- live reload events via `WatchMode`.
/// - `--marketplace` -- the `marketplace` command group (marketplace.md §9.2)
///   over the fixture library, for example `skills-demo --marketplace list`.
@main
internal enum SkillsDemoMain {
    /// The `--chat` flag that switches into live-model validation mode.
    private static let chatFlag = "--chat"

    /// The `--watch` flag that switches into live-reload mode.
    private static let watchFlag = "--watch"

    /// The `--marketplace` flag that switches into marketplace control mode.
    private static let marketplaceFlag = "--marketplace"

    /// The exit code of a demo run that could not build its own stack.
    private static let assemblyFailureExitCode: Int32 = 1

    /// Dispatches to `--chat`/`--watch`/`--marketplace` mode or the default
    /// CLI mode, based on `CommandLine.arguments`.
    ///
    /// The first step bootstraps logging, before a mode makes a registry or a
    /// search agent. An executable must always bootstrap logging: with no
    /// bootstrap, swift-log writes each record to standard error, for example
    /// the "enter" record of each skill search and each skill load. The
    /// telemetry of the package goes to the OpenTelemetry backend that a host
    /// bootstraps, and this demo does not show the telemetry. Thus the demo
    /// bootstraps the handler that does nothing. The demo bootstraps no tracer
    /// and no metrics factory, thus the spans and the metrics stay on their
    /// no-op defaults.
    internal static func main() async {
        LoggingSystem.bootstrap(SwiftLogNoOpLogHandler.init)
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case chatFlag:
            await ChatMode.run()
        case watchFlag:
            await WatchMode.run()
        case marketplaceFlag:
            await runMarketplace(arguments: Array(arguments.dropFirst()))
        default:
            await runCLI(arguments: arguments)
        }
    }

    /// Drives `arguments` through `SkillsCLI.makeDriver(registry:)`, writing
    /// its output and exiting with its code.
    ///
    /// - Parameter arguments: The command's arguments, excluding the
    ///   executable name.
    private static func runCLI(arguments: [String]) async {
        do {
            let registry = SkillsDemoAssembly.makeRegistry(watch: false)
            let driver = try SkillsCLI.makeDriver(registry: registry)
            let result = await driver.run(arguments: arguments)
            report(output: result.output, exitCode: result.exitCode)
        } catch {
            StandardStream.error.write(line: "skills-demo: \(error)")
            exit(assemblyFailureExitCode)
        }
    }

    /// Drives `arguments` through `MarketplaceCLI.run(arguments:context:)`
    /// over the fixture stack, writing its output and exiting with its code.
    ///
    /// The fixture stack is the configuration stack, thus the group reads the
    /// `marketplaces.yaml` of the fixture library and never the file of this
    /// user. The cache folder comes from `SKILLS_MARKETPLACE_CACHE`, which the
    /// context reads out of the environment of this process.
    ///
    /// - Parameter arguments: The command's arguments, after the
    ///   `--marketplace` flag.
    private static func runMarketplace(arguments: [String]) async {
        let context = MarketplaceCLIContext(stack: FixtureStack.make())
        let result = await MarketplaceCLI.run(arguments: arguments, context: context)
        report(output: result.output, exitCode: result.exitCode)
    }

    /// Writes the output of one mode and ends the process on a failure.
    ///
    /// The call writes through `StandardStream`, the one line writer of this
    /// package, the same way the failure path of this file writes to standard
    /// error. That writer ends the text with one line break. Thus a text that
    /// already holds a line break for each of its lines gets no empty line
    /// after it.
    ///
    /// - Parameters:
    ///   - output: The text of the run. Empty text writes no line.
    ///   - exitCode: The exit code of the run. A value other than zero ends
    ///     the process with that code.
    private static func report(output: String, exitCode: Int32) {
        let lineBreak = StandardStream.lineBreak
        let text = output.hasSuffix(lineBreak) ? String(output.dropLast(lineBreak.count)) : output
        if !text.isEmpty {
            StandardStream.output.write(line: text)
        }
        if exitCode != 0 {
            exit(exitCode)
        }
    }
}
