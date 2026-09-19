import Dispatch
import Foundation
import FoundationModelsSkills

/// Drives `skills-demo --watch`: the human-driven twin of `HotReloadTests`,
/// writing each reload event as it lands (plan.md §10, §11).
///
/// The tool `SkillsDemoAssembly.makeTool(registry:)` assembles follows
/// `registry.onReload` itself, exactly as plan.md §10 shows, thus this mode
/// forwards nothing by hand. It takes a second subscription of its own --
/// `onReload` is a multicast stream, thus neither subscriber steals the
/// other's events -- and writes what each reload carries.
///
/// The package owns both halves of that writing: `ReloadReport` reads what
/// the reload changed, and `StandardStream` writes each line. Thus this mode
/// holds no reading and no writing of its own.
@MainActor
enum WatchMode {
    /// Retains the `SIGTERM` handler for this process's lifetime; a local
    /// variable would be deallocated (and the handler silently dropped)
    /// before `run()`'s `for await` loop ever suspends on it.
    private static var terminationSource: (any DispatchSourceProtocol)?

    /// Watches the fixture stack and writes each reload's forwarded update,
    /// refreshed preload size, and refreshed `/` listing, until `SIGTERM`.
    static func run() async {
        let registry = SkillsDemoAssembly.makeRegistry(watch: true)
        guard let reloads = registry.onReload else {
            StandardStream.output.write(line: "Watch mode requires a watched registry.")
            return
        }

        do {
            // The tool follows the reloads itself, thus this loop only
            // writes. Holding the tool for the full loop is what keeps that
            // follower alive.
            let tool = try await SkillsDemoAssembly.makeTool(registry: registry)
            StandardStream.output.write(
                line: "Watching \(registry.roots.map(\.path).joined(separator: ", ")) for changes.")
            Self.installTerminationHandler()

            for await metadata in reloads {
                let report = await ReloadReport.make(metadata: metadata, registry: registry)
                StandardStream.output.write(lines: report.lines)
            }
            withExtendedLifetime(tool) {}
        } catch {
            StandardStream.output.write(line: "Watch mode failed to build the skills tool: \(error)")
        }
    }

    /// Installs a `SIGTERM` handler that exits cleanly, ignoring the
    /// default terminate-immediately disposition so the handler runs first.
    private static func installTerminationHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { exit(0) }
        source.resume()
        Self.terminationSource = source
    }
}
