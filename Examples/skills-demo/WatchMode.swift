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
/// Every line goes to standard output through `FileHandle`, the way
/// `SkillsDemoMain` writes the output of a mode.
@MainActor
enum WatchMode {
    /// Retains the `SIGTERM` handler for this process's lifetime; a local
    /// variable would be deallocated (and the handler silently dropped)
    /// before `run()`'s `for await` loop ever suspends on it.
    private static var terminationSource: (any DispatchSourceProtocol)?

    /// The line break that goes after each line this mode writes.
    private static let lineBreak = "\n"

    /// Watches the fixture stack and writes each reload's forwarded update,
    /// refreshed preload size, and refreshed `/` listing, until `SIGTERM`.
    static func run() async {
        let registry = SkillsDemoAssembly.makeRegistry(watch: true)
        guard let reloads = registry.onReload else {
            Self.write("Watch mode requires a watched registry.")
            return
        }

        do {
            // The tool follows the reloads itself, thus this loop only
            // writes. Holding the tool for the full loop is what keeps that
            // follower alive.
            let tool = try await SkillsDemoAssembly.makeTool(registry: registry)
            Self.write("Watching \(registry.roots.map(\.path).joined(separator: ", ")) for changes.")
            Self.installTerminationHandler()

            for await metadata in reloads {
                await Self.writeReloadEvent(metadata: metadata, registry: registry)
            }
            withExtendedLifetime(tool) {}
        } catch {
            Self.write("Watch mode failed to build the skills tool: \(error)")
        }
    }

    /// Writes one reload's forwarded metadata count, refreshed preload size,
    /// and refreshed `/` listing.
    ///
    /// - Parameters:
    ///   - metadata: The refreshed metadata `registry.onReload` published.
    ///   - registry: The registry to re-read `preloadedBodies()`/
    ///     `commandListing()` from.
    private static func writeReloadEvent(metadata: [SkillMetadata], registry: SkillsRegistry) async {
        let visibleCount = metadata.filter(\.isModelVisible).count
        let preloaded = await registry.preloadedBodies()
        Self.write("reload: \(metadata.count) skills, \(visibleCount) model-visible")
        Self.write("preload: \(preloaded.count) rendered characters")
        Self.write("listing: \(registry.commandListing().map(\.id).joined(separator: ", "))")
    }

    /// Writes one line to standard output, with a line break after it.
    ///
    /// The demo writes through `FileHandle` for every line it shows, thus no
    /// line of this executable reaches standard out through `print`.
    ///
    /// - Parameter line: The text of the line, without its line break.
    private static func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + lineBreak).utf8))
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
