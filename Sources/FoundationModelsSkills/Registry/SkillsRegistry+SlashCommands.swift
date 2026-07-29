import Foundation
import FoundationModelsExtras

/// `SkillsRegistry`'s conformance to Extras' harness delivery channel
/// (plan.md §6, §7.1; decision #29): the user `/` menu's rows, translated
/// into `SlashCommand` values a host feeds to its own session/UI layer.
///
/// **The §7.1 caveat, stated plainly.** Every command below carries a
/// `.prompt(template:)` body: the skill's raw, unrendered body text. A
/// host that runs this template through the harness engine gets only that
/// engine's own rendering (`SlashCommand.Body.prompt`'s doc comment calls
/// it "Pillar 3") -- none of this package's §5 passes 1-2 ever run
/// (`$`-argument substitution, shell injection), so `$0`/`$ARGUMENTS`
/// placeholders and `` !`command` `` shell-injection syntax pass through
/// completely inert. A host that wants full render fidelity -- every §5
/// pass, with the user's typed arguments actually substituted -- calls
/// `registry.call(id:arguments:)` directly instead of running the
/// `.prompt` template through the harness engine. An invocation-aware
/// prompt body the harness engine could itself render with full §5
/// fidelity is a recorded Extras coordination item, not something this
/// conformance can address on its own.
extension SkillsRegistry: SlashCommandProviding {
    /// This registry's user-invocable skills (plan.md §6.1), one
    /// `SlashCommand` per `commandListing()` row.
    ///
    /// Ignores `workingDirectory`: `commandListing()` already resolves
    /// against the roots this registry was constructed over, not a
    /// per-call working directory.
    ///
    /// - Parameter workingDirectory: The session's current working
    ///   directory. Unused; accepted only to satisfy
    ///   `SlashCommandProviding`.
    /// - Returns: One `SlashCommand` per user-invocable skill, in
    ///   `commandListing()`'s order.
    public func commands(workingDirectory: URL) async -> [SlashCommand] {
        slashCommands()
    }

    /// Republishes this registry's full command set after every
    /// watcher-driven catalog rebuild, bridged from `onReload` (plan.md
    /// §7).
    ///
    /// `nil` when this registry was constructed with `watch: false`, same
    /// as `onReload` itself. Accessing this property starts a fresh
    /// bridging subscription over the same underlying `onReload` stream
    /// each time -- mirroring `onReload`'s own single-subscriber contract,
    /// a caller should read `commandUpdates` once and retain the returned
    /// stream rather than accessing this property repeatedly.
    public var commandUpdates: AsyncStream<[SlashCommand]>? {
        guard let onReload else { return nil }
        let (stream, continuation) = AsyncStream<[SlashCommand]>.makeStream()
        let bridge = Task {
            for await _ in onReload {
                continuation.yield(slashCommands())
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in bridge.cancel() }
        return stream
    }

    /// This registry's current `commandListing()` rows, translated into
    /// `SlashCommand` values, in `commandListing()`'s order.
    ///
    /// - Returns: One `SlashCommand` per user-invocable skill.
    private func slashCommands() -> [SlashCommand] {
        commandListing().map(slashCommand(for:))
    }

    /// Builds one `SlashCommand` for `listing`.
    ///
    /// - Parameter listing: The `commandListing()` row to translate.
    /// - Returns: The `SlashCommand`: `name` is `listing.id`, `description`
    ///   is `listing.description` (empty when absent), `argumentHint` is
    ///   assembled from `listing.parameters` (`argumentHint(for:)`), and
    ///   the body is a `.prompt(template:)` carrying the skill's raw,
    ///   unrendered body text -- none of §5's three render passes have run
    ///   on it yet.
    private func slashCommand(for listing: SkillListing) -> SlashCommand {
        SlashCommand(
            name: listing.id,
            description: listing.description ?? "",
            argumentHint: Self.argumentHint(for: listing.parameters),
            body: .prompt(template: rawBody(id: listing.id) ?? ""))
    }

    /// The `SlashCommand.argumentHint` text for `parameters`: each
    /// parameter's placeholder summary (`parameterSummary(parameter:)`), in
    /// position order, space-joined.
    ///
    /// - Parameter parameters: The listing row's parsed parameters (plan.md
    ///   §6.1).
    /// - Returns: The joined hint text, or `nil` when `parameters` is
    ///   empty -- `SlashCommand.argumentHint`'s own documented "no hint
    ///   worth showing" value.
    private static func argumentHint(for parameters: [SkillParameter]) -> String? {
        guard !parameters.isEmpty else { return nil }
        return parameters
            .sorted { $0.position < $1.position }
            .map(SkillsRegistry.parameterSummary)
            .joined(separator: " ")
    }
}
