import Foundation
import Synchronization

@testable import FoundationModelsSkills

/// A `Clock` that moves only when a test advances it (marketplace.md §8.2 and
/// decision 13).
///
/// ``MarketplaceStore`` takes a clock, thus its periodic check never waits for
/// real time: a test advances this clock and the next pass runs at once. The
/// clock also counts every sleep that it served, thus a test can prove that a
/// store with no `checkInterval` and no `fetchTimeout` never sleeps at all.
///
/// Every stored property is an immutable `let` of a `Sendable` type: the
/// mutable state lives inside a `Mutex`, which gives the class a plain
/// `Sendable` conformance that the compiler checks.
final class ManualClock: Clock, Sendable {
    /// One point on the timeline of a ``ManualClock``.
    struct Instant: InstantProtocol {
        /// How far this point is from the start of the clock.
        let sinceStart: Duration

        /// The point that is `duration` later than this one.
        ///
        /// - Parameter duration: How much later the new point is.
        /// - Returns: The later point.
        func advanced(by duration: Duration) -> Instant {
            Instant(sinceStart: sinceStart + duration)
        }

        /// How far another point is from this one.
        ///
        /// - Parameter other: The other point.
        /// - Returns: The distance, which is negative when `other` is earlier.
        func duration(to other: Instant) -> Duration {
            other.sinceStart - sinceStart
        }

        /// Whether one point is earlier than another.
        ///
        /// - Parameters:
        ///   - lhs: The left point.
        ///   - rhs: The right point.
        /// - Returns: `true` when `lhs` is earlier.
        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.sinceStart < rhs.sinceStart
        }
    }

    /// One sleep that waits for the clock to reach its deadline.
    private struct Sleeper {
        /// The point at which the sleep ends.
        let deadline: Instant

        /// What to resume when the clock reaches the deadline.
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// What one call of ``sleep(until:tolerance:)`` does next.
    private enum SleepStart {
        /// The task was already cancelled.
        case cancelled

        /// The clock already passed the deadline.
        case due

        /// The sleep waits for the clock to advance.
        case waiting
    }

    /// Everything that a test or a sleeper changes.
    private struct State {
        /// Where the clock stands now.
        var now = Instant(sinceStart: .zero)

        /// Each sleep that waits, by id.
        var sleepers: [Int: Sleeper] = [:]

        /// The id of each sleep whose task was cancelled before the sleep
        /// registered itself.
        var cancelled: Set<Int> = []

        /// The id that the next sleep gets.
        var nextID = 0

        /// How many sleeps the clock served, waiting ones included.
        var sleepCount = 0

        /// What to resume when the set of sleepers changes.
        var observers: [CheckedContinuation<Void, Never>] = []
    }

    /// The state of the clock.
    private let state = Mutex(State())

    /// Where the clock stands now. It moves only in ``advance(by:)``.
    var now: Instant {
        state.withLock { $0.now }
    }

    /// The smallest step of the clock. A manual clock has no step of its own.
    var minimumResolution: Duration {
        .zero
    }

    /// How many sleeps the clock served since it was made.
    var sleepCount: Int {
        state.withLock { $0.sleepCount }
    }

    /// How many sleeps wait now.
    var sleeperCount: Int {
        state.withLock { $0.sleepers.count }
    }

    /// Waits until the clock reaches a deadline, or until the task is
    /// cancelled.
    ///
    /// - Parameters:
    ///   - deadline: The point at which the sleep ends.
    ///   - tolerance: How much later the sleep may end. A manual clock ends
    ///     each sleep exactly at its deadline, thus the value is not used.
    /// - Throws: `CancellationError` when the task of the sleep is cancelled.
    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = state.withLock { current -> Int in
            let id = current.nextID
            current.nextID += 1
            current.sleepCount += 1
            return id
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let start = state.withLock { current -> SleepStart in
                    if current.cancelled.remove(id) != nil {
                        return .cancelled
                    }
                    if deadline <= current.now {
                        return .due
                    }
                    current.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return .waiting
                }
                switch start {
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .due:
                    continuation.resume()
                case .waiting:
                    notifyObservers()
                }
            }
        } onCancel: {
            cancelSleep(id: id)
        }
    }

    /// Moves the clock forward, and ends every sleep that the new point
    /// reaches.
    ///
    /// - Parameter duration: How far forward the clock moves.
    func advance(by duration: Duration) {
        let due = state.withLock { current -> [Sleeper] in
            current.now = current.now.advanced(by: duration)
            let reached = current.sleepers.filter { $0.value.deadline <= current.now }
            for id in reached.keys {
                current.sleepers.removeValue(forKey: id)
            }
            return Array(reached.values)
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
        notifyObservers()
    }

    /// Waits until at least one sleep waits on the clock.
    func waitForSleeper() async {
        await waitUntil { $0 > 0 }
    }

    /// Waits until no sleep waits on the clock.
    func waitForNoSleeper() async {
        await waitUntil { $0 == 0 }
    }

    /// Waits until the number of waiting sleeps matches.
    ///
    /// - Parameter match: Takes the number of waiting sleeps and gives `true`
    ///   when the wait is over.
    private func waitUntil(_ match: @escaping @Sendable (Int) -> Bool) async {
        while true {
            let ready = state.withLock { match($0.sleepers.count) }
            if ready {
                return
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let done = state.withLock { current -> Bool in
                    if match(current.sleepers.count) {
                        return true
                    }
                    current.observers.append(continuation)
                    return false
                }
                if done {
                    continuation.resume()
                }
            }
        }
    }

    /// Ends one sleep with a cancellation, or records the cancellation when
    /// the sleep did not register itself yet.
    ///
    /// - Parameter id: The sleep to cancel.
    private func cancelSleep(id: Int) {
        let sleeper = state.withLock { current -> Sleeper? in
            if let found = current.sleepers.removeValue(forKey: id) {
                return found
            }
            current.cancelled.insert(id)
            return nil
        }
        sleeper?.continuation.resume(throwing: CancellationError())
        notifyObservers()
    }

    /// Resumes every waiter of ``waitUntil(_:)``, outside the lock.
    private func notifyObservers() {
        let observers = state.withLock { current -> [CheckedContinuation<Void, Never>] in
            defer { current.observers.removeAll() }
            return current.observers
        }
        for observer in observers {
            observer.resume()
        }
    }
}

/// A ``GitTransport`` that holds a call until the test releases it, or until
/// the task of the call is cancelled (marketplace.md §13).
///
/// The gate wraps another transport, thus it adds no counting of its own: a
/// test puts it over ``RecordingGitTransport`` and reads the counts there.
/// A held call lets a test act while a check or a fetch is in progress, which
/// is what the coalescing, the `stop()`, and the `fetchTimeout` tests need.
actor GatedGitTransport: GitTransport {
    /// What the gate does with one call.
    enum Behavior: Sendable {
        /// The call goes straight to the wrapped transport.
        case pass

        /// The call waits for ``release()``, then goes to the wrapped
        /// transport.
        case holdThenPass

        /// The call waits until its task is cancelled. It never reaches the
        /// wrapped transport.
        case holdUntilCancelled
    }

    /// One call of the transport.
    enum Call: Sendable, Hashable {
        /// ``GitTransport/remoteHead(url:ref:credentials:)``.
        case remoteHead

        /// ``GitTransport/fetch(url:revision:intoBareRepository:credentials:)``.
        case fetch
    }

    /// The transport that does the work of a call that the gate lets through.
    private let base: any GitTransport

    /// What the gate does with a remote-head call.
    private var remoteHeadBehavior: Behavior

    /// What the gate does with a fetch call.
    private var fetchBehavior: Behavior

    /// How many times each call entered the gate.
    private var entries: [Call: Int] = [:]

    /// Whether ``release()`` already ran.
    private var released = false

    /// What to resume when ``release()`` runs, by id.
    private var held: [Int: CheckedContinuation<Void, any Error>] = [:]

    /// The id of each held call whose task was cancelled before the call
    /// registered itself.
    private var cancelled: Set<Int> = []

    /// The id that the next held call gets.
    private var nextID = 0

    /// What to resume when a call enters the gate.
    private var observers: [CheckedContinuation<Void, Never>] = []

    /// Makes a gate over another transport.
    ///
    /// - Parameters:
    ///   - base: The transport that does the work.
    ///   - remoteHead: What the gate does with a remote-head call. The default
    ///     is ``Behavior/pass``.
    ///   - fetch: What the gate does with a fetch call. The default is
    ///     ``Behavior/pass``.
    init(wrapping base: any GitTransport, remoteHead: Behavior = .pass, fetch: Behavior = .pass) {
        self.base = base
        remoteHeadBehavior = remoteHead
        fetchBehavior = fetch
    }

    /// Lets every held call, and every later call, through to the wrapped
    /// transport.
    ///
    /// A call with ``Behavior/holdUntilCancelled`` is not released: only a
    /// cancellation ends it.
    func release() {
        released = true
        let waiting = held.values
        held.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }

    /// Replaces what the gate does with one call, for every later call.
    ///
    /// - Parameters:
    ///   - behavior: What the gate does from now on.
    ///   - call: The call that the new behavior belongs to.
    func setBehavior(_ behavior: Behavior, of call: Call) {
        switch call {
        case .remoteHead:
            remoteHeadBehavior = behavior
        case .fetch:
            fetchBehavior = behavior
        }
    }

    /// How many times one call entered the gate.
    ///
    /// - Parameter call: The call to count.
    /// - Returns: The number of entries.
    func entryCount(of call: Call) -> Int {
        entries[call] ?? 0
    }

    /// Waits until one call entered the gate at least `count` times.
    ///
    /// - Parameters:
    ///   - call: The call to wait for.
    ///   - count: How many entries the wait needs.
    func waitForEntry(of call: Call, count: Int = 1) async {
        while (entries[call] ?? 0) < count {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                observers.append(continuation)
            }
        }
    }

    func remoteHead(
        url: String, ref: String, credentials: (@Sendable (URL) async -> MarketplaceCredential?)?
    ) async throws -> String {
        try await gate(call: .remoteHead, behavior: remoteHeadBehavior)
        return try await base.remoteHead(url: url, ref: ref, credentials: credentials)
    }

    func fetch(
        url: String, revision: String, intoBareRepository repositoryURL: URL,
        credentials: (@Sendable (URL) async -> MarketplaceCredential?)?
    ) async throws -> String {
        try await gate(call: .fetch, behavior: fetchBehavior)
        return try await base.fetch(
            url: url, revision: revision, intoBareRepository: repositoryURL, credentials: credentials)
    }

    /// Records one entry and holds the call when its behavior says so.
    ///
    /// - Parameters:
    ///   - call: The call that entered.
    ///   - behavior: What the gate does with it.
    /// - Throws: ``GitTransportError/cancelled`` when the task of the call is
    ///   cancelled while the gate holds it.
    private func gate(call: Call, behavior: Behavior) async throws {
        entries[call, default: 0] += 1
        notifyObservers()
        switch behavior {
        case .pass:
            return
        case .holdThenPass:
            if released {
                return
            }
            try await hold(untilRelease: true)
        case .holdUntilCancelled:
            try await hold(untilRelease: false)
        }
    }

    /// Waits until ``release()`` runs, or until the task is cancelled.
    ///
    /// - Parameter untilRelease: Whether ``release()`` ends the wait. When it
    ///   is `false`, only a cancellation ends it.
    /// - Throws: ``GitTransportError/cancelled`` when the task is cancelled.
    private func hold(untilRelease: Bool) async throws {
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if cancelled.remove(id) != nil {
                    continuation.resume(throwing: GitTransportError.cancelled)
                    return
                }
                if untilRelease, released {
                    continuation.resume()
                    return
                }
                held[id] = continuation
            }
        } onCancel: {
            Task { await self.cancelHold(id: id) }
        }
    }

    /// Ends one held call with a cancellation, or records the cancellation
    /// when the call did not register itself yet.
    ///
    /// - Parameter id: The held call to cancel.
    private func cancelHold(id: Int) {
        guard let continuation = held.removeValue(forKey: id) else {
            cancelled.insert(id)
            return
        }
        continuation.resume(throwing: GitTransportError.cancelled)
    }

    /// Resumes every waiter of ``waitForEntry(of:count:)``.
    private func notifyObservers() {
        let waiting = observers
        observers.removeAll()
        for observer in waiting {
            observer.resume()
        }
    }
}

/// Records the events of a ``MarketplaceStore`` and lets a test wait for one
/// (marketplace.md §6.2).
///
/// A test takes the stream before it calls `start()`, thus the log holds every
/// event of the run. The wait follows the events themselves, thus no test
/// waits for a fixed time.
actor MarketplaceEventLog {
    /// Every event so far, in order.
    private(set) var recorded: [MarketplaceEvent] = []

    /// What to resume when a new event arrives.
    private var observers: [CheckedContinuation<Void, Never>] = []

    /// Starts a task that records every event of one stream.
    ///
    /// - Parameter stream: The stream to follow. A caller takes it from
    ///   ``MarketplaceStore/events``.
    /// - Returns: The task, which the test cancels when it is done.
    nonisolated func follow(_ stream: AsyncStream<MarketplaceEvent>) -> Task<Void, Never> {
        Task {
            for await event in stream {
                await self.append(event)
            }
        }
    }

    /// Waits until one recorded event matches.
    ///
    /// - Parameter match: Gives `true` for the event that the test waits for.
    /// - Returns: The first matching event.
    func waitForEvent(where match: @Sendable (MarketplaceEvent) -> Bool) async -> MarketplaceEvent {
        while true {
            if let found = recorded.first(where: match) {
                return found
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                observers.append(continuation)
            }
        }
    }

    /// Records one event and wakes every waiter.
    ///
    /// - Parameter event: The event that the store published.
    private func append(_ event: MarketplaceEvent) {
        recorded.append(event)
        let waiting = observers
        observers.removeAll()
        for observer in waiting {
            observer.resume()
        }
    }
}

/// A one-shot signal that lets a test wait until another task reached a point
/// in its work.
///
/// The coalescing test uses it to know that the second caller is running and
/// that its next step is the call into the store. Thus the test needs no sleep
/// to order the two callers.
actor TestSignal {
    /// Whether ``signal()`` already ran.
    private var signalled = false

    /// What to resume when ``signal()`` runs.
    private var observers: [CheckedContinuation<Void, Never>] = []

    /// Marks the point as reached and wakes every waiter.
    func signal() {
        signalled = true
        let waiting = observers
        observers.removeAll()
        for observer in waiting {
            observer.resume()
        }
    }

    /// Waits until ``signal()`` runs.
    func wait() async {
        if signalled {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            observers.append(continuation)
        }
    }
}
