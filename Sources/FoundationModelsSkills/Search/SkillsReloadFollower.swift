/// Forwards each registry reload publication into a search agent, and stops
/// as soon as it is released.
///
/// `SkillsRegistry.onReload` publishes the refreshed metadata list once for
/// every watcher-driven rebuild, and `SkillSearchAgent.update(items:)` is
/// what makes that list searchable. Neither type joins the two on its own.
/// Before this class, every host wrote that loop itself. A host that builds
/// its tool through one of the `SkillsTool` factories now gets this class
/// instead, held on the `SkillsToolContext` the factory builds, thus the
/// loop lives exactly as long as the tool does.
///
/// ### Subscribe before you seed
///
/// `reloads` must be taken from the registry *before* the caller reads the
/// seed catalog. `onReload` carries every publication from the point of
/// subscription forward, thus a caller that reads `metadata()` first and
/// subscribes second loses any reload that lands in that window.
///
/// ### The forwarding task captures no `self`
///
/// The task started in `init` captures the stream and the agent, and never
/// `self`. A task that captured `self` would hold a strong reference to its
/// own follower for as long as it runs: `deinit` would never run, the
/// `cancel()` call it carries would never happen, and the task would forward
/// for ever. `SkillsRegistry.detachedReader` records the same trap for the
/// registry's own reload consumers.
///
/// `final class ... Sendable`: the one stored property is an immutable `let`
/// of a `Sendable` type, thus this class holds no mutable state and needs no
/// lock of its own.
public final class SkillsReloadFollower: Sendable {
    /// The task that reads each publication from the reload stream and
    /// writes it into the agent.
    ///
    /// Held for its lifetime alone: nothing reads it back, and `deinit`
    /// cancels it.
    private let forwarding: Task<Void, Never>

    /// Creates a follower, and starts forwarding at once.
    ///
    /// - Parameters:
    ///   - reloads: The already-subscribed reload stream, typically
    ///     `SkillsRegistry.onReload`. Read "Subscribe before you seed"
    ///     above before you build one.
    ///   - agent: The search agent every publication goes to.
    public init(reloads: AsyncStream<[SkillMetadata]>, agent: SkillSearchAgent) {
        forwarding = Task {
            for await items in reloads {
                await agent.update(items: items)
            }
        }
    }

    /// Cancels the forwarding task, thus no forward outlives its follower.
    ///
    /// The loop needs no cancellation test of its own: an `AsyncStream`
    /// iterator answers `nil` once its task is cancelled, thus `for await`
    /// ends and the task returns.
    deinit {
        forwarding.cancel()
    }
}
