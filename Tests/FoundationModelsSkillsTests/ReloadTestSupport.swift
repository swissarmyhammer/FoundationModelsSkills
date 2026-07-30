import Foundation
import Testing

/// Shared reload/watcher test-support helpers for `HotReloadTests` and
/// `SkillsRegistryReloadTests`: the count-only event tally, the generic
/// deadline-polling loop, the "exactly one event, then settles" assertion
/// both files' own recorders wait on, and the `SKILL.md` fixture-writing
/// helpers -- each previously reimplemented in parallel across the two
/// files (review findings, 2026-07-29 21:57).
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
