import Foundation
import FoundationModelsMetadataRegistry
import Synchronization

/// Shared fixture-directory helper for `HotReloadTests` and
/// `HotReloadLiveTests` -- both drive a real, watched temp `.skills` root and
/// need an identical way to create one.
enum HotReloadTestSupport {
    /// Creates a fresh, empty temporary directory for a test root, so one
    /// test's filesystem activity can never be observed by another.
    ///
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    /// - Returns: The new directory's URL.
    static func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// A deterministic `TextEmbedding` test double, mirroring
/// `FoundationModelsMetadataRegistryTests.FakeEmbedder`.
///
/// Every text embeds to an all-zero vector. A test that uses it asserts on
/// *counts* (how many texts were embedded) and on the `.embedCatchUp`
/// diagnostic, never on cosine ranking, thus no registered vector table is
/// needed. An optional ``EmbedGate`` lets a test observe an in-flight
/// (not-yet-complete) embed call.
///
/// `HotReloadTests` and `MarketplaceEndToEndTests` both build a real
/// `MetadataSearcher` with no GPU, thus the double is here and not in one of
/// the two suites.
final class FakeEmbedder: TextEmbedding {
    /// The length of every embedding vector this embedder gives.
    let dimension: Int

    /// The running total of texts that reached ``embed(_:)``.
    private let counter: EmbedCallCounter

    /// The gate that holds every ``embed(_:)`` call, or `nil` to never hold
    /// one.
    private let gate: EmbedGate?

    /// Creates a fake embedder that returns an all-zero vector for every
    /// text.
    ///
    /// - Parameters:
    ///   - dimension: The length of every embedding vector this
    ///     embedder produces.
    ///   - gate: Blocks every `embed(_:)` call until the gate is open,
    ///     or `nil` to never block. Defaults to `nil`.
    init(dimension: Int, gate: EmbedGate? = nil) {
        self.dimension = dimension
        self.counter = EmbedCallCounter()
        self.gate = gate
    }

    /// The total number of texts passed to `embed(_:)` across every call
    /// so far.
    var embeddedTextCount: Int { counter.count }

    /// Gives one all-zero vector for each text, and counts the texts.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: One all-zero vector of ``dimension`` values for each text.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        if let gate { await gate.waitUntilOpen() }
        counter.increment(by: texts.count)
        return texts.map { _ in [Float](repeating: 0, count: dimension) }
    }
}

/// A thread-safe call counter for ``FakeEmbedder``.
///
/// A `Mutex` holds the running total, thus the compiler itself checks the
/// plain `Sendable` conformance.
final class EmbedCallCounter: Sendable {
    /// The running total, which the mutex guards.
    private let total = Mutex(0)

    /// The running total, read under the mutex.
    var count: Int { total.withLock { $0 } }

    /// Adds `amount` to the running count.
    ///
    /// - Parameter amount: The amount to add.
    func increment(by amount: Int) {
        total.withLock { $0 += amount }
    }
}

/// A gate that ``FakeEmbedder/embed(_:)`` can be told to block on, so a test
/// can observe a deterministic window where the async embed catch-up is
/// confirmed in flight (blocked awaiting this gate) but not yet complete --
/// proving a concurrent keyword search still succeeds during that window,
/// per `MetadataSearcher.update(items:)`'s own reentrancy documentation (a
/// concurrent `search` interleaves while `update` is suspended awaiting the
/// embedder, since both are calls into the same actor and `update` is
/// suspended, not synchronously blocking it).
///
/// Starts open, so every construction-time embed never blocks; a test closes
/// it for one deliberate window, then reopens it.
actor EmbedGate {
    /// Whether a call passes straight through.
    private var isOpen = true

    /// What to resume when ``open()`` runs.
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    /// Whether some `embed(_:)` call is currently blocked on this gate.
    /// A test polls it, so no caller ever suspends on a continuation this
    /// gate might never resume.
    private(set) var isBlocked = false

    /// Closes the gate: every subsequent `embed(_:)` call blocks in
    /// ``waitUntilOpen()`` until ``open()`` runs.
    func close() {
        isOpen = false
        isBlocked = false
    }

    /// Opens the gate, resuming every call currently blocked in
    /// ``waitUntilOpen()`` and letting every future call through
    /// immediately.
    func open() {
        isOpen = true
        let waiting = openWaiters
        openWaiters = []
        for continuation in waiting { continuation.resume() }
    }

    /// Called by ``FakeEmbedder/embed(_:)``: returns immediately while the
    /// gate is open; otherwise marks the gate blocked (so a poll of
    /// ``isBlocked`` observes it) and suspends until ``open()`` runs.
    func waitUntilOpen() async {
        if isOpen {
            return
        }
        isBlocked = true
        await withCheckedContinuation { openWaiters.append($0) }
    }
}
