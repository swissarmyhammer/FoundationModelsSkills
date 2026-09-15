import Synchronization

/// Gives every registered subscriber each published value (plan.md §7.1 "one
/// registry, four simultaneous consumers", and marketplace.md §7.4).
///
/// A single shared `AsyncStream` cannot serve this: two concurrent `for await`
/// loops over the same stream *split* its elements between them rather than
/// each observing every one, because they compete for the same buffer. This
/// type sidesteps that entirely: each ``subscribe()`` call registers its own
/// continuation, and ``publish(_:)`` yields to every one of them, thus a
/// fresh subscription never steals the elements of another.
///
/// `SkillsRegistry` broadcasts each rebuild's metadata list this way, and
/// ``MarketplaceStore`` broadcasts its events and its layer updates the same
/// way.
///
/// Every stored property is an immutable `let` of a `Sendable` type: the
/// mutable subscriber table lives inside a `Mutex`, which gives the class a
/// plain `Sendable` conformance that the compiler checks.
internal final class EventBroadcaster<Element: Sendable>: Sendable {
    /// The subscribers, and the id that the next one gets.
    private struct Subscribers {
        /// The continuation of each current subscriber, by id.
        var continuations: [Int: AsyncStream<Element>.Continuation] = [:]

        /// The id of the next subscriber.
        var nextID = 0
    }

    /// The subscribers of this broadcaster.
    private let subscribers = Mutex(Subscribers())

    /// Registers a fresh subscriber stream, which sees every publication from
    /// this point forward.
    ///
    /// - Returns: The stream of the subscriber. It finishes on its own
    ///   `onTermination`, that is, when the caller cancels or drops it, or
    ///   when ``finishAll()`` runs.
    func subscribe() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream<Element>.makeStream()
        let id = subscribers.withLock { state in
            let id = state.nextID
            state.nextID += 1
            state.continuations[id] = continuation
            return id
        }
        continuation.onTermination = { [weak self] _ in self?.unsubscribe(id: id) }
        return stream
    }

    /// Publishes one value to every current subscriber.
    ///
    /// - Parameter element: The value to publish.
    func publish(_ element: Element) {
        for continuation in subscribers.withLock({ Array($0.continuations.values) }) {
            continuation.yield(element)
        }
    }

    /// Finishes every current subscriber and stops accepting new
    /// publications.
    func finishAll() {
        let current = subscribers.withLock { state in
            defer { state.continuations.removeAll() }
            return Array(state.continuations.values)
        }
        for continuation in current {
            continuation.finish()
        }
    }

    /// Removes the continuation of one subscriber once its stream terminates,
    /// so that a cancelled or dropped subscriber keeps no slot.
    ///
    /// - Parameter id: The id of the subscriber to remove.
    private func unsubscribe(id: Int) {
        subscribers.withLock { _ = $0.continuations.removeValue(forKey: id) }
    }
}
