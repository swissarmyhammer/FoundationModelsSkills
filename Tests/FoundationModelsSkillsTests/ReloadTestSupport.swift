import Foundation
import FoundationModelsSkills
import Testing

/// Shared reload/watcher test-support helpers for `HotReloadTests` and
/// `SkillsRegistryReloadTests`: the count-only event tally, the forwarding
/// of one reload stream into a search agent, the generic deadline-polling
/// loop, the "exactly one event, then settles" assertion both files' own
/// recorders wait on, and the `SKILL.md` fixture-writing helpers -- each
/// previously reimplemented in parallel across the two files (review
/// findings, 2026-07-29 21:57).
///
/// `SkillWatcherTests` and `MarketplaceCatalogTests` also use the `SKILL.md`
/// helpers, so that the test target has one builder of `SKILL.md` text.
enum ReloadTestSupport {
    // MARK: - Event tally

    /// Counts how many events a subscription has observed, independent of
    /// their payload -- the shared shape `HotReloadTests.UpdateCallRecorder`
    /// and `SkillsRegistryReloadTests.EventTally` duplicated identically.
    actor EventTally {
        private(set) var count = 0

        /// Records one more observed event.
        func record() {
            count += 1
        }
    }

    /// Starts a background task that iterates `stream` (when non-`nil`)
    /// and records one event into `tally` per element.
    ///
    /// The caller evaluates `stream` on its own thread -- `registry.onReload`
    /// or `registry.commandUpdates` passed as the argument -- so the
    /// subscription is registered before the task is created. A subscription
    /// made inside the task registers only when the task first runs, and
    /// under a loaded cooperative pool that can be later than the watcher's
    /// first publication; the publication is then lost, and every wait on
    /// it times out (^n89yw8p).
    ///
    /// - Parameters:
    ///   - stream: The already-subscribed stream to iterate, or `nil` for a
    ///     `watch: false` registry.
    ///   - tally: The tally each element is recorded into.
    /// - Returns: The subscription task; the caller cancels it once done
    ///   observing.
    static func tally<Element: Sendable>(_ stream: AsyncStream<Element>?, into tally: EventTally) -> Task<Void, Never> {
        Task {
            guard let stream else { return }
            for await _ in stream { await tally.record() }
        }
    }

    /// Starts a background task that iterates `stream` (when non-`nil`),
    /// forwards each published metadata list into `agent.update(items:)`,
    /// and records one event into `tally` for each forward -- the plan.md
    /// §7.1 wiring a real host is responsible for.
    ///
    /// The caller evaluates `stream` on its own thread, for the reason
    /// ``tally(_:into:)`` gives.
    ///
    /// `HotReloadTests` and `MarketplaceEndToEndTests` both prove that one
    /// change gives the searcher exactly one `update(items:)` call, thus the
    /// helper is here and not in one of the two suites.
    ///
    /// - Parameters:
    ///   - stream: The already-subscribed reload stream to iterate, or `nil`
    ///     for a registry that never reloads.
    ///   - agent: The search agent each publication is forwarded to.
    ///   - tally: The tally each forward is recorded into.
    /// - Returns: The subscription task; the caller cancels it once done
    ///   observing.
    static func forward(
        _ stream: AsyncStream<[SkillMetadata]>?, to agent: SkillSearchAgent, recordingInto tally: EventTally
    ) -> Task<Void, Never> {
        Task {
            guard let stream else { return }
            for await metadata in stream {
                await agent.update(items: metadata)
                await tally.record()
            }
        }
    }

    // MARK: - Generic polling

    /// Polls `getter`'s result until `predicate` accepts it or `timeout`
    /// elapses.
    ///
    /// - Parameters:
    ///   - getter: Reads the current value to test.
    ///   - predicate: Whether the current value satisfies the wait.
    ///   - timeout: How long to keep polling before giving up.
    /// - Returns: The last observed value, whether or not it satisfied
    ///   `predicate`.
    static func poll<T>(_ getter: () async -> T, until predicate: (T) -> Bool, timeout: Duration) async -> T {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var current = await getter()
        while !predicate(current), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            current = await getter()
        }
        return current
    }

    /// Asserts that exactly one new event lands (per `countGetter`) after
    /// `baseline`: the count reaches `baseline + 1` within `signalTimeout`,
    /// and stays there through `settleWindow`.
    ///
    /// - Parameters:
    ///   - countGetter: Reads the current observed-event count.
    ///   - baseline: The count observed before the action under test.
    ///   - signalTimeout: How long to wait for the first new event.
    ///   - settleWindow: How long to keep watching afterward to confirm no
    ///     *second* event follows it.
    /// - Returns: The settled count, for chaining a further action's
    ///   `baseline` in the same test.
    @discardableResult
    static func expectExactlyOneEvent(
        countGetter: () async -> Int, since baseline: Int, signalTimeout: Duration, settleWindow: Duration
    ) async -> Int {
        let afterFirst = await Self.poll(countGetter, until: { $0 >= baseline + 1 }, timeout: signalTimeout)
        #expect(afterFirst == baseline + 1)

        let afterSettling = await Self.poll(countGetter, until: { $0 >= baseline + 2 }, timeout: settleWindow)
        #expect(afterSettling == baseline + 1)
        return afterSettling
    }

    /// How long a wait gives an expected publication before it treats the
    /// absence as a failure. The value is generous against the scheduler
    /// jitter of a loaded parallel run.
    static let expectedSignalTimeout: Duration = .seconds(10)

    /// How long a wait keeps watching, after an expected publication
    /// arrived, to confirm that no second publication follows it.
    static let noFurtherSignalWindow: Duration = .seconds(1)

    /// Asserts that exactly one new event lands on `tally` after `baseline`,
    /// with ``expectedSignalTimeout`` and ``noFurtherSignalWindow``.
    ///
    /// - Parameters:
    ///   - tally: The tally to assert against.
    ///   - baseline: The count observed before the action under test. The
    ///     default is `0`, for a tally that the action started empty.
    /// - Returns: The settled count, for chaining a further action's
    ///   `baseline` in the same test.
    @discardableResult
    static func expectExactlyOneEvent(_ tally: EventTally, since baseline: Int = 0) async -> Int {
        await expectExactlyOneEvent(
            countGetter: { await tally.count }, since: baseline,
            signalTimeout: expectedSignalTimeout, settleWindow: noFurtherSignalWindow)
    }

    // MARK: - Fixture file helpers

    /// Builds a minimal but structurally valid `SKILL.md` for `id`.
    ///
    /// - Parameters:
    ///   - id: The skill id the frontmatter's `name:` field carries.
    ///   - descriptionSuffix: Text appended to `description:`, so successive
    ///     calls with different suffixes produce distinguishable metadata.
    ///     Defaults to empty.
    ///   - extraFrontmatter: Additional raw frontmatter lines (each already
    ///     newline-terminated) inserted before the closing `---`, or empty
    ///     for none. Defaults to empty.
    ///   - body: The body text, or `nil` for the default `"Body text for
    ///     \(id)."`.
    /// - Returns: The `SKILL.md` file contents.
    static func skillFileContents(
        id: String, descriptionSuffix: String = "", extraFrontmatter: String = "", body: String? = nil
    ) -> String {
        "---\nname: \(id)\ndescription: reload fixture \(descriptionSuffix)\n\(extraFrontmatter)---\n"
            + "\(body ?? "Body text for \(id).")\n"
    }

    /// Writes `id/SKILL.md` directly under `directory`, creating the skill's
    /// own subdirectory first if it does not already exist.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and the
    ///     frontmatter's `name:` field.
    ///   - directory: The root to write under.
    ///   - descriptionSuffix: Forwarded to
    ///     `skillFileContents(id:descriptionSuffix:extraFrontmatter:body:)`.
    ///     Defaults to empty.
    ///   - extraFrontmatter: Forwarded to
    ///     `skillFileContents(id:descriptionSuffix:extraFrontmatter:body:)`.
    ///     Defaults to empty.
    ///   - body: Forwarded to
    ///     `skillFileContents(id:descriptionSuffix:extraFrontmatter:body:)`.
    ///     Defaults to `nil`.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    static func writeSkillFile(
        id: String, in directory: URL, descriptionSuffix: String = "", extraFrontmatter: String = "",
        body: String? = nil
    ) throws {
        let skillDirectory = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try Self.skillFileContents(
            id: id, descriptionSuffix: descriptionSuffix, extraFrontmatter: extraFrontmatter, body: body
        )
        .write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
