import Foundation
import Testing

@testable import FoundationModelsSkills

/// Tests for `SkillWatcher`, the M2 debounced "something changed" signal
/// over every host-supplied layer root (plan.md §7, decision #29 as
/// amended): create/edit/delete under a watched root each coalesce to
/// exactly one callback, a burst of writes coalesces the same way, changes
/// nested two levels deep (mirroring `name/SKILL.md` and
/// `name/_partials/*`) are still detected, events under an unfiltered `.git/`
/// directory neither crash nor get suppressed, a nonexistent root is
/// skipped silently, and `stop()` ends delivery.
struct SkillWatcherTests {
    /// How long a watcher under test waits for a quiet period before firing
    /// its coalesced callback. Short relative to the wait timeouts below so
    /// tests run quickly without being so short that real filesystem event
    /// latency splits a single burst into two callbacks.
    private static let testDebounceInterval: DispatchTimeInterval = .milliseconds(150)

    /// How long a test waits for an expected callback to arrive before
    /// treating its absence as a failure. Generous relative to
    /// `testDebounceInterval` to absorb scheduler and filesystem-event
    /// jitter in a sandboxed test environment.
    private static let expectedSignalTimeout: Duration = .seconds(10)

    /// How long a test waits, after an expected callback already arrived,
    /// to confirm no *second* callback follows it. Comfortably longer than
    /// `testDebounceInterval` so a slow-to-arrive coalesced flush isn't
    /// mistaken for a genuine second burst.
    private static let noFurtherSignalWindow: Duration = .seconds(1)

    // MARK: - Create / edit / delete each coalesce to exactly one callback

    @Test func creatingASkillFileProducesExactlyOneCoalescedCallback() async throws {
        try await Self.withWatchedTempRoot { root, recorder in
            try Self.writeSkillFile(id: "new-skill", in: root)
            _ = await Self.expectExactlyOneSignal(recorder, since: 0)
        }
    }

    @Test func editingASkillFileProducesExactlyOneCoalescedCallback() async throws {
        try await Self.withWatchedTempRoot { root, recorder in
            try Self.writeSkillFile(id: "existing-skill", in: root)
            let baseline = await Self.expectExactlyOneSignal(recorder, since: 0)

            try Self.writeSkillFile(id: "existing-skill", in: root, bodySuffix: "edited")
            _ = await Self.expectExactlyOneSignal(recorder, since: baseline)
        }
    }

    @Test func deletingASkillFileProducesExactlyOneCoalescedCallback() async throws {
        try await Self.withWatchedTempRoot { root, recorder in
            try Self.writeSkillFile(id: "doomed-skill", in: root)
            let baseline = await Self.expectExactlyOneSignal(recorder, since: 0)

            try FileManager.default.removeItem(
                at: root.appendingPathComponent("doomed-skill", isDirectory: true))
            _ = await Self.expectExactlyOneSignal(recorder, since: baseline)
        }
    }

    // MARK: - Burst coalescing

    @Test func burstOfWritesWithinTheDebounceWindowProducesExactlyOneCallback() async throws {
        try await Self.withWatchedTempRoot { root, recorder in
            let skillFile = root
                .appendingPathComponent("burst-skill", isDirectory: true)
                .appendingPathComponent("SKILL.md")
            try FileManager.default.createDirectory(
                at: skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)

            for iteration in 0..<5 {
                try Self.skillFileContents(id: "burst-skill", bodySuffix: "rev\(iteration)")
                    .write(to: skillFile, atomically: true, encoding: .utf8)
            }

            _ = await Self.expectExactlyOneSignal(recorder, since: 0)
        }
    }

    // MARK: - Recursion: nested SKILL.md and _partials/ both count

    @Test func skillFileNestedTwoLevelsDeepIsDetected() async throws {
        try await Self.withWatchedTempRoot { root, recorder in
            try Self.writeSkillFile(id: "nested-skill", in: root)
            _ = await Self.expectExactlyOneSignal(recorder, since: 0)
        }
    }

    @Test func editingAFileUnderPartialsIsDetected() async throws {
        try await Self.withWatchedTempRoot { root, recorder in
            let partialsDirectory = root.appendingPathComponent("_partials", isDirectory: true)
            try FileManager.default.createDirectory(at: partialsDirectory, withIntermediateDirectories: true)
            let baseline = await Self.expectExactlyOneSignal(recorder, since: 0)

            try "header text".write(
                to: partialsDirectory.appendingPathComponent("header.md"), atomically: true, encoding: .utf8)
            _ = await Self.expectExactlyOneSignal(recorder, since: baseline)
        }
    }

    // MARK: - Unfiltered directories still coalesce safely

    @Test func eventsUnderAGitDirectoryStillCoalesceWithoutCrashing() async throws {
        try await Self.withWatchedTempRoot { root, recorder in
            let gitDirectory = root.appendingPathComponent(".git", isDirectory: true)
            try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
            let baseline = await Self.expectExactlyOneSignal(recorder, since: 0)

            try "ref: refs/heads/main\n".write(
                to: gitDirectory.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
            _ = await Self.expectExactlyOneSignal(recorder, since: baseline)
        }
    }

    // MARK: - Nonexistent root

    @Test func nonexistentRootInTheListIsSkippedWithoutError() async throws {
        // `bogusRoot`'s parent must be a private directory this test owns,
        // not the shared system temp root directly -- arming (^80kravf)
        // watches the nonexistent root's nearest EXISTING ancestor, and the
        // shared temp root sees constant, unrelated activity from every
        // other test's own `makeTempDirectory()` call, which would make the
        // "exactly one signal" assertion below flaky.
        let privateDirectory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory) }
        let bogusRoot = privateDirectory.appendingPathComponent("does-not-exist", isDirectory: true)
        let realRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: realRoot) }

        let (onChange, recorder) = Self.makeSignalRecorder()
        let watcher = SkillWatcher(
            roots: [bogusRoot, realRoot], debounceInterval: Self.testDebounceInterval, onChange: onChange)
        watcher.start()
        defer { watcher.stop() }

        try Self.writeSkillFile(id: "still-works", in: realRoot)
        _ = await Self.expectExactlyOneSignal(recorder, since: 0)
    }

    // MARK: - Late root creation (^80kravf): armed via nearest existing ancestor

    @Test func creatingARootThatDidNotExistAtStartIsDetected() async throws {
        let privateDirectory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory) }
        let lateRoot = privateDirectory.appendingPathComponent("skills-arrive-later", isDirectory: true)

        let (onChange, recorder) = Self.makeSignalRecorder()
        let watcher = SkillWatcher(roots: [lateRoot], debounceInterval: Self.testDebounceInterval, onChange: onChange)
        watcher.start()
        defer { watcher.stop() }

        try Self.writeSkillFile(id: "arrived-skill", in: lateRoot)
        _ = await Self.expectExactlyOneSignal(recorder, since: 0)
    }

    @Test func deletingAndRecreatingARootKeepsEventsFlowing() async throws {
        let privateDirectory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory) }
        let root = privateDirectory.appendingPathComponent("comes-and-goes", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let (onChange, recorder) = Self.makeSignalRecorder()
        let watcher = SkillWatcher(roots: [root], debounceInterval: Self.testDebounceInterval, onChange: onChange)
        watcher.start()
        defer { watcher.stop() }

        try Self.writeSkillFile(id: "before-delete", in: root)
        let afterFirstCreate = await Self.expectExactlyOneSignal(recorder, since: 0)

        try FileManager.default.removeItem(at: root)
        let afterDelete = await Self.expectExactlyOneSignal(recorder, since: afterFirstCreate)

        // The root is gone -- `flush()`'s rebuild must have fallen back to
        // arming `privateDirectory` (the now-nearest existing ancestor), not
        // silently stopped watching anything at all.
        try Self.writeSkillFile(id: "after-recreate", in: root)
        _ = await Self.expectExactlyOneSignal(recorder, since: afterDelete)
    }

    // MARK: - Stop prevents further callbacks

    @Test func stopPreventsFurtherCallbacksAfterAChange() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let (onChange, recorder) = Self.makeSignalRecorder()
        let watcher = SkillWatcher(roots: [root], debounceInterval: Self.testDebounceInterval, onChange: onChange)
        watcher.start()
        watcher.stop()

        try Self.writeSkillFile(id: "after-stop", in: root)
        let countAfterWait = await Self.waitForCount(recorder, atLeast: 1, timeout: Self.noFurtherSignalWindow)
        #expect(countAfterWait == 0)
    }

    // MARK: - Reentrant stop from within onChange

    @Test func stoppingFromWithinOnChangeLeavesTheWatcherGenuinelyStoppedAndRestartable() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = SignalRecorder()
        let box = WatcherBox()
        box.watcher = SkillWatcher(roots: [root], debounceInterval: Self.testDebounceInterval) {
            Task { await recorder.record() }
            box.watcher?.stop()
        }
        box.watcher?.start()

        try Self.writeSkillFile(id: "self-stopping", in: root)
        let afterFirstFlush = await Self.waitForCount(recorder, atLeast: 1, timeout: Self.expectedSignalTimeout)
        #expect(afterFirstFlush == 1)

        // The reentrant `stop()` must have actually torn every source
        // down, not just flipped a flag: `flush()`'s post-`onChange`
        // rebuild must not silently reopen sources underneath a watcher
        // that was just told to stop.
        #expect(box.watcher?.watchedSourceCountForTesting == 0)

        // The reentrant `stop()` above ran synchronously inside `onChange`
        // (proving `runOnQueue(_:)`'s reentrancy guard doesn't deadlock),
        // so a further change on the same root must not produce a second
        // signal: the watcher must already be genuinely stopped, not just
        // about to be.
        try Self.writeSkillFile(id: "should-not-be-seen", in: root)
        let afterIgnoredChange = await Self.waitForCount(recorder, atLeast: 2, timeout: Self.noFurtherSignalWindow)
        #expect(afterIgnoredChange == 1)

        // Restarting the same instance afterward must work normally -- the
        // reentrant stop must not leave it permanently unable to watch
        // again.
        box.watcher?.start()
        defer { box.watcher?.stop() }
        try Self.writeSkillFile(id: "after-restart", in: root)
        let afterRestart = await Self.waitForCount(recorder, atLeast: 2, timeout: Self.expectedSignalTimeout)
        #expect(afterRestart == 2)
    }

    // MARK: - Test helpers

    /// A mutable reference cell holding the `SkillWatcher` under test, so
    /// its own `onChange` closure can call back into it.
    ///
    /// `@unchecked Sendable`: `watcher` is written exactly once,
    /// synchronously, right after construction and before `start()` is
    /// ever called; every read happens from inside the `onChange` closure,
    /// which can only run after a real filesystem event and the debounce
    /// delay elapse -- strictly after that write. The two never race in
    /// practice, even though the compiler cannot see that ordering.
    private final class WatcherBox: @unchecked Sendable {
        var watcher: SkillWatcher?
    }

    /// Tallies every `SkillWatcher` callback delivered during a test.
    ///
    /// An actor rather than an `AsyncStream`: `AsyncStream` (from
    /// `.makeStream()`) only supports one long-lived consumer -- abandoning
    /// an iterator mid-stream (an early `return`, or cancellation from a
    /// timeout race) silently finishes it for good, so a second,
    /// independent wait against the same stream would observe it as
    /// already-finished rather than continuing to deliver later signals.
    /// Polling this counter sidesteps that entirely.
    private actor SignalRecorder {
        private(set) var count = 0

        func record() {
            count += 1
        }
    }

    /// Starts a `SkillWatcher` over a fresh temporary root, hands the root
    /// and its signal recorder to `body`, then tears the watcher and the
    /// temporary directory down unconditionally.
    ///
    /// - Parameter body: The test body, given the watched root and the
    ///   recorder of coalesced signals it produces.
    /// - Throws: Whatever `body` or the temp-directory setup throws.
    private static func withWatchedTempRoot(
        _ body: (URL, SignalRecorder) async throws -> Void
    ) async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let (onChange, recorder) = Self.makeSignalRecorder()
        let watcher = SkillWatcher(roots: [root], debounceInterval: Self.testDebounceInterval, onChange: onChange)
        watcher.start()
        defer { watcher.stop() }

        try await body(root, recorder)
    }

    /// Builds a `SkillWatcher.onChange` closure paired with the
    /// `SignalRecorder` it feeds.
    ///
    /// - Returns: The callback to pass as `onChange`, and the recorder it
    ///   feeds.
    private static func makeSignalRecorder() -> (onChange: @Sendable () -> Void, recorder: SignalRecorder) {
        let recorder = SignalRecorder()
        let onChange: @Sendable () -> Void = {
            Task { await recorder.record() }
        }
        return (onChange, recorder)
    }

    /// Asserts that exactly one new signal lands on `recorder` after
    /// `baseline`: the count reaches `baseline + 1` within
    /// `expectedSignalTimeout`, and stays there through
    /// `noFurtherSignalWindow`.
    ///
    /// - Parameters:
    ///   - recorder: The recorder to assert against.
    ///   - baseline: The count observed before the action under test.
    /// - Returns: The settled count, for chaining a further action's
    ///   `baseline` in the same test.
    @discardableResult
    private static func expectExactlyOneSignal(_ recorder: SignalRecorder, since baseline: Int) async -> Int {
        let afterFirst = await Self.waitForCount(recorder, atLeast: baseline + 1, timeout: Self.expectedSignalTimeout)
        #expect(afterFirst == baseline + 1)

        let afterSettling = await Self.waitForCount(
            recorder, atLeast: baseline + 2, timeout: Self.noFurtherSignalWindow)
        #expect(afterSettling == baseline + 1)
        return afterSettling
    }

    /// Polls `recorder.count` until it reaches `target` or `timeout`
    /// elapses.
    ///
    /// - Parameters:
    ///   - recorder: The recorder to poll.
    ///   - target: The count to wait for.
    ///   - timeout: How long to keep polling before giving up.
    /// - Returns: `recorder.count` at the moment polling stopped, whether
    ///   or not it reached `target`.
    private static func waitForCount(_ recorder: SignalRecorder, atLeast target: Int, timeout: Duration) async -> Int {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var current = await recorder.count
        while current < target, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            current = await recorder.count
        }
        return current
    }

    /// Creates a fresh, empty temporary directory for a test root, so one
    /// test's filesystem activity can never be observed by another.
    ///
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    /// - Returns: The new directory's URL.
    private static func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Builds a minimal but structurally valid `SKILL.md` body for `id`.
    ///
    /// - Parameters:
    ///   - id: The skill id the frontmatter's `name:` field carries.
    ///   - bodySuffix: Extra text appended to the body, so a second call
    ///     with a different suffix produces genuinely different file
    ///     content for edit tests.
    /// - Returns: The `SKILL.md` file contents.
    private static func skillFileContents(id: String, bodySuffix: String = "") -> String {
        "---\nname: \(id)\ndescription: test fixture.\n---\nBody. \(bodySuffix)\n"
    }

    /// Writes `id/SKILL.md` directly under `directory`, creating the
    /// skill's own subdirectory first if it does not already exist.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and the
    ///     frontmatter's `name:` field.
    ///   - directory: The root to write under.
    ///   - bodySuffix: Forwarded to `skillFileContents(id:bodySuffix:)`.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    private static func writeSkillFile(id: String, in directory: URL, bodySuffix: String = "") throws {
        let skillDirectory = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try Self.skillFileContents(id: id, bodySuffix: bodySuffix)
            .write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
