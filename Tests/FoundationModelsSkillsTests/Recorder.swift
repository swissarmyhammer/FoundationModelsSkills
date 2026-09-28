import Synchronization

/// Records each value that a test double receives, in the order it receives
/// them, for the test to read after.
///
/// A double often records in a task that is not the task of the test, thus a
/// `Mutex` holds the values, and the class is `Sendable` with no unchecked
/// claim. The test and the double share one instance, thus this is a class
/// and not a value type.
final class Recorder<Element: Sendable>: Sendable {
    /// The values so far, which the mutex guards.
    private let values = Mutex<[Element]>([])

    /// Every value recorded so far, in the order the calls to
    /// ``record(_:)`` came.
    var recorded: [Element] {
        values.withLock { $0 }
    }

    /// Records `value` after every value that came before it.
    ///
    /// - Parameter value: The value the double received.
    func record(_ value: Element) {
        values.withLock { $0.append(value) }
    }
}
