import Foundation
import FoundationModelsSkills
import Operations
import OperationsCLI

/// The `skills-demo` executable's entry point: plan.md §11's worked example
/// of the full stack, in three modes.
///
/// - Default -- CLI (§7.2): `skills-demo skill list`, `skills-demo skill
///   search "commit my changes"`, `skills-demo skill use commit --arguments
///   "fix parser"`, over the fixture library.
/// - `--chat` -- scripted live-model validation via `ChatMode`, gated on
///   `SystemLanguageModel` availability (or `SKILLS_DEMO_FORCE_UNAVAILABLE`).
/// - `--watch` -- live reload events via `WatchMode`.
@main
internal enum SkillsDemoMain {
    /// The `--chat` flag that switches into live-model validation mode.
    private static let chatFlag = "--chat"

    /// The `--watch` flag that switches into live-reload mode.
    private static let watchFlag = "--watch"

    /// Dispatches to `--chat`/`--watch` mode or the default CLI mode, based
    /// on `CommandLine.arguments`.
    internal static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case chatFlag:
            await ChatMode.run()
        case watchFlag:
            await WatchMode.run()
        default:
            await runCLI(arguments: arguments)
        }
    }

    /// Drives `arguments` through `SkillsCLI.makeDriver(registry:)`, printing
    /// its output and exiting with its code.
    ///
    /// - Parameter arguments: The command's arguments, excluding the
    ///   executable name.
    private static func runCLI(arguments: [String]) async {
        do {
            let registry = SkillsDemoAssembly.makeRegistry(watch: false)
            let driver = try SkillsCLI.makeDriver(registry: registry)
            let result = await driver.run(arguments: arguments)
            if !result.output.isEmpty {
                print(result.output)
            }
            if result.exitCode != 0 {
                exit(result.exitCode)
            }
        } catch {
            FileHandle.standardError.write(Data("skills-demo: \(error)\n".utf8))
            exit(1)
        }
    }
}
