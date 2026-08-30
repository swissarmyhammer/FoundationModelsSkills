import Dispatch
import Foundation
import FoundationModelsSkills

/// Drives `skills-demo --watch`: the human-driven twin of `HotReloadTests`,
/// printing each reload event as it lands (plan.md §10, §11).
///
/// The tool `SkillsDemoAssembly.makeTool(registry:)` assembles follows
/// `registry.onReload` itself, exactly as plan.md §10 shows, thus this mode
/// forwards nothing by hand. It takes a second subscription of its own --
/// `onReload` is a multicast stream, thus neither subscriber steals the
/// other's events -- and prints what each reload carries.
@MainActor
enum WatchMode {
    /// Retains the `SIGTERM` handler for this process's lifetime; a local
    /// variable would be deallocated (and the handler silently dropped)
    /// before `run()`'s `for await` loop ever suspends on it.
    private static var terminationSource: (any DispatchSourceProtocol)?

    /// Watches the fixture stack and prints each reload's forwarded update,
    /// refreshed preload size, and refreshed `/` listing, until `SIGTERM`.
    static func run() async {
        let registry = SkillsDemoAssembly.makeRegistry(watch: true)
        guard let reloads = registry.onReload else {
            print("Watch mode requires a watched registry.")
            return
        }

        do {
            // The tool follows the reloads itself, thus this loop only
            // prints. Holding the tool for the full loop is what keeps that
            // follower alive.
            let tool = try await SkillsDemoAssembly.makeTool(registry: registry)
            print("Watching \(registry.roots.map(\.path).joined(separator: ", ")) for changes.")
            Self.installTerminationHandler()

            for await metadata in reloads {
                Self.printReloadEvent(metadata: metadata, registry: registry)
            }
            withExtendedLifetime(tool) {}
        } catch {
            print("Watch mode failed to build the skills tool: \(error)")
        }
    }

    /// Prints one reload's forwarded metadata count, refreshed preload size,
    /// and refreshed `/` listing.
    ///
    /// - Parameters:
    ///   - metadata: The refreshed metadata `registry.onReload` published.
    ///   - registry: The registry to re-read `preloadedBodies()`/
    ///     `commandListing()` from.
    private static func printReloadEvent(metadata: [SkillMetadata], registry: SkillsRegistry) {
        let visibleCount = metadata.filter(\.isModelVisible).count
        print("reload: \(metadata.count) skills, \(visibleCount) model-visible")
        print("preload: \(registry.preloadedBodies().count) rendered characters")
        print("listing: \(registry.commandListing().map(\.id).joined(separator: ", "))")
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
