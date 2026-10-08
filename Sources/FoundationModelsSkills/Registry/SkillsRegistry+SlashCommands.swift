import Foundation
import FoundationModelsExtras

/// `SkillsRegistry`'s conformance to Extras' harness delivery channel: the user `/` menu's rows, translated
/// into `SlashCommand` values a host feeds to its own session/UI layer.
///
/// Each command carries a `.rendered` body. When the user runs `/name
/// text`, the body gives `text` to `call(id:arguments:)` as one argument,
/// thus the render pipeline runs in full: `$ARGUMENTS` gets the text as typed,
/// `$N` and `$name` get its shell-style tokens, shell injection runs, and
/// Stencil runs. The harness feeds the result to the model as the prompt
/// of the turn, the same as a `.prompt` template it rendered itself.
extension SkillsRegistry: SlashCommandProviding {
    /// This registry's user-invocable skills, one
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
    /// watcher-driven catalog rebuild, bridged from `onReload`.
    ///
    /// `nil` when this registry was constructed with `watch: false`, same
    /// as `onReload` itself. Accessing this property registers a fresh
    /// subscription over `onReload` -- itself now a multicast-safe fresh
    /// subscription per access (`ReloadBroadcaster`) -- so this property can
    /// be accessed any number of times, or alongside `onReload` itself,
    /// with every subscriber observing every publication in full; none
    /// steals another's elements.
    public var commandUpdates: AsyncStream<[SlashCommand]>? {
        guard let onReload else { return nil }
        let (stream, continuation) = AsyncStream<[SlashCommand]>.makeStream()
        // Captures `detachedReader`, never `self`/`self.slashCommands`:
        // `self` is a value-type copy that would carry its own strong
        // reference to `reloadCoordinator`, keeping this registry's watcher
        // (and `onReload` itself) alive for as long as this task runs --
        // undermining "the watcher's lifecycle is owned by the registry."
        let reader = detachedReader
        let bridge = Task {
            for await _ in onReload {
                continuation.yield(reader.slashCommands())
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
    /// The body captures `detachedReader`, never `self`, for the reason
    /// `commandUpdates` gives: a command list a host keeps must not keep
    /// the watcher of this registry alive.
    ///
    /// - Parameter listing: The `commandListing()` row to translate.
    /// - Returns: The `SlashCommand`: `name` is `listing.id`, `description`
    ///   is `listing.description` (empty when absent), `argumentHint` is
    ///   assembled from `listing.parameters` (`argumentHint(for:)`), and
    ///   the body renders the skill through `call(id:arguments:)` with the
    ///   typed text as its one argument.
    private func slashCommand(for listing: SkillListing) -> SlashCommand {
        let reader = detachedReader
        let id = listing.id
        return SlashCommand(
            name: id,
            description: listing.description ?? "",
            argumentHint: Self.argumentHint(for: listing.parameters),
            body: .rendered { invocation in
                try await reader.call(id: id, arguments: Self.arguments(typed: invocation.arguments))
            })
    }

    /// The arguments of one `/command` invocation.
    ///
    /// The typed text is ONE argument: `$ARGUMENTS` gets it as typed, and
    /// pass 1 splits it into positions with shell-style quoting. Text that
    /// is empty or whitespace only is no argument at all, thus `/name` with
    /// nothing after it renders with no `ARGUMENTS:` fallback.
    ///
    /// - Parameter text: The raw text after `/name `.
    /// - Returns: `[text]`, or `[]` when `text` holds no non-whitespace
    ///   character.
    private static func arguments(typed text: String) -> [String] {
        text.allSatisfy(\.isWhitespace) ? [] : [text]
    }

    /// The `SlashCommand.argumentHint` text for `parameters`: each
    /// parameter's placeholder summary (`parameterSummary(parameter:)`), in
    /// position order, space-joined.
    ///
    /// - Parameter parameters: The listing row's parsed parameters.
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
