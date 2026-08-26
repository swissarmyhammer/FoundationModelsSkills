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
/// skipped silently, a root that appears after `start()` escalates from an
/// ancestor watch to a real recursive one, a root nested several levels
/// below its nearest existing ancestor is still armed at that ancestor, an
/// armed ancestor's unrelated activity stays quiet, an unreadable directory
/// inside a root neither throws nor silences its readable siblings, a root
/// listed before its own parent leaks no descriptor, and `stop()` ends
/// delivery.
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
        let privateDirectory = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory) }
        let bogusRoot = privateDirectory.appendingPathComponent("does-not-exist", isDirectory: true)
        let realRoot = try WatcherTestSupport.makeTempDirectory()
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
        let privateDirectory = try WatcherTestSupport.makeTempDirectory()
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
        let privateDirectory = try WatcherTestSupport.makeTempDirectory()
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

    @Test func editingAFileUnderALateCreatedRootFiresAfterEscalation() async throws {
        try await Self.withTempDirectory { privateDirectory in
            let lateRoot = privateDirectory.appendingPathComponent("skills-arrive-later", isDirectory: true)
            try await Self.withWatcher(over: [lateRoot]) { recorder in
                try Self.writeSkillFile(id: "arrived-skill", in: lateRoot)
                let afterCreate = await Self.expectExactlyOneSignal(recorder, since: 0)

                // The flush above rebuilt the watch tree, so `lateRoot` is
                // now watched recursively. An edit two levels under it never
                // touches `privateDirectory`, so only the recursive watch
                // can see it -- the ancestor watch alone cannot.
                try Self.writeSkillFile(id: "arrived-skill", in: lateRoot, bodySuffix: "edited")
                _ = await Self.expectExactlyOneSignal(recorder, since: afterCreate)
            }
        }
    }

    @Test func unrelatedActivityUnderAnArmedAncestorProducesNoCallback() async throws {
        try await Self.withTempDirectory { privateDirectory in
            let lateRoot = privateDirectory.appendingPathComponent("skills-arrive-later", isDirectory: true)
            try await Self.withWatcher(over: [lateRoot]) { recorder in
                // `privateDirectory` is the armed ancestor. Activity directly
                // under it that does not create `lateRoot` must not reach
                // `onChange`.
                let unrelated = privateDirectory.appendingPathComponent("unrelated", isDirectory: true)
                try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
                try "noise".write(to: unrelated.appendingPathComponent("noise.txt"), atomically: true, encoding: .utf8)
                try FileManager.default.removeItem(at: unrelated)
                let afterNoise = await Self.waitForCount(recorder, atLeast: 1, timeout: Self.noFurtherSignalWindow)
                #expect(afterNoise == 0)

                // Creating the awaited root itself still fires.
                try Self.writeSkillFile(id: "arrived-skill", in: lateRoot)
                _ = await Self.expectExactlyOneSignal(recorder, since: 0)
            }
        }
    }

    @Test func rootNestedSeveralLevelsBelowItsNearestExistingAncestorIsArmedThere() async throws {
        try await Self.withTempDirectory { privateDirectory in
            // Only `privateDirectory` exists. `ancestorArming(for:)` must walk
            // up past `a/b/c` -- three missing components -- to find it, not
            // stop at the root's (equally missing) direct parent.
            let deepRoot = privateDirectory
                .appendingPathComponent("a", isDirectory: true)
                .appendingPathComponent("b", isDirectory: true)
                .appendingPathComponent("c", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
            try await Self.withWatcher(over: [deepRoot]) { recorder in
                // Creating the whole chain at once makes `a` appear directly
                // under the armed ancestor, which is the awaited child.
                try Self.writeSkillFile(id: "deep-skill", in: deepRoot)
                let afterCreate = await Self.expectExactlyOneSignal(recorder, since: 0)

                // The flush above escalated to a real recursive watch of
                // `deepRoot`; an edit four levels below `privateDirectory`
                // is only visible through that watch.
                try Self.writeSkillFile(id: "deep-skill", in: deepRoot, bodySuffix: "edited")
                _ = await Self.expectExactlyOneSignal(recorder, since: afterCreate)
            }
        }
    }

    // MARK: - Unreadable directory inside a root

    @Test(.disabled(if: isRoot, "root reads a mode-0o000 directory, so the unreadable branch is unreachable"))
    func unreadableDirectoryInsideARootIsSkippedAndReadableSiblingsStillReport() async throws {
        try await Self.withTempDirectory { root in
            let lockedDirectory = root.appendingPathComponent("locked", isDirectory: true)
            try FileManager.default.createDirectory(at: lockedDirectory, withIntermediateDirectories: true)
            try Self.setPosixPermissions(Self.unreadableMode, of: lockedDirectory)
            defer { try? Self.setPosixPermissions(Self.ownerAccessMode, of: lockedDirectory) }

            // `start()` lists `root`, reaches `locked`, and must treat its
            // failed listing as "no entries" rather than throwing or
            // abandoning the rest of the tree.
            try await Self.withWatcher(over: [root]) { recorder in
                try Self.writeSkillFile(id: "readable-skill", in: root)
                _ = await Self.expectExactlyOneSignal(recorder, since: 0)
            }
        }
    }

    // MARK: - Overwritten source is cancelled, not leaked

    @Test func rootListedBeforeItsOwnParentLeaksNoDescriptor() async throws {
        try await Self.withTempDirectory { parent in
            let missingChild = parent.appendingPathComponent("missing-child", isDirectory: true)
            let (onChange, _) = Self.makeSignalRecorder()
            let watcher = SkillWatcher(
                roots: [missingChild, parent], debounceInterval: Self.testDebounceInterval, onChange: onChange)
            watcher.start()

            // Arming `missingChild` opens a source on `parent` first; the
            // recursive watch of `parent` then replaces it. The replaced
            // source must be cancelled so its cancel handler closes the
            // descriptor -- one open descriptor per stored source, no more.
            await Self.waitUntil(timeout: Self.expectedSignalTimeout) {
                watcher.openDescriptorCountForTesting == watcher.watchedSourceCountForTesting
            }
            #expect(watcher.openDescriptorCountForTesting == watcher.watchedSourceCountForTesting)

            watcher.stop()
            await Self.waitUntil(timeout: Self.expectedSignalTimeout) {
                watcher.openDescriptorCountForTesting == 0
            }
            #expect(watcher.openDescriptorCountForTesting == 0)
        }
    }

    // MARK: - Stop prevents further callbacks

    @Test func stopPreventsFurtherCallbacksAfterAChange() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
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
        let root = try WatcherTestSupport.makeTempDirectory()
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

    /// The file mode that refuses every read, so a directory listing fails.
    private static let unreadableMode = 0o000

    /// The file mode restored on teardown so the temp directory can be
    /// removed.
    private static let ownerAccessMode = 0o700

    /// Whether the test process is root. Root reads a mode-`0o000`
    /// directory, so the unreadable-directory test cannot reach the branch
    /// it exists to cover and is skipped there.
    private static var isRoot: Bool { geteuid() == 0 }

    /// Sets the POSIX permission bits of `item`.
    ///
    /// - Parameters:
    ///   - mode: The permission bits to apply.
    ///   - item: The file or directory to change.
    /// - Throws: Whatever `FileManager.setAttributes` throws.
    private static func setPosixPermissions(_ mode: Int, of item: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: item.path)
    }

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
        try await Self.withTempDirectory { root in
            try await Self.withWatcher(over: [root]) { recorder in
                try await body(root, recorder)
            }
        }
    }

    /// Makes a fresh temporary directory, hands it to `body`, then removes
    /// it unconditionally.
    ///
    /// - Parameter body: The test body, given the directory.
    /// - Throws: Whatever `body` or the temp-directory setup throws.
    private static func withTempDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    /// Starts a `SkillWatcher` over `roots`, hands its signal recorder to
    /// `body`, then stops the watcher unconditionally.
    ///
    /// - Parameters:
    ///   - roots: The roots to watch, in the order the watcher receives them.
    ///   - body: The test body, given the recorder of coalesced signals.
    /// - Throws: Whatever `body` throws.
    private static func withWatcher(over roots: [URL], _ body: (SignalRecorder) async throws -> Void) async throws {
        let (onChange, recorder) = Self.makeSignalRecorder()
        let watcher = SkillWatcher(roots: roots, debounceInterval: Self.testDebounceInterval, onChange: onChange)
        watcher.start()
        defer { watcher.stop() }
        try await body(recorder)
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
        await Self.waitUntil(timeout: timeout) { await recorder.count >= target }
        return await recorder.count
    }

    /// How long `waitUntil(timeout:_:)` sleeps between two evaluations of
    /// its condition.
    private static let pollInterval: Duration = .milliseconds(10)

    /// Polls `condition` until it holds or `timeout` elapses.
    ///
    /// - Parameters:
    ///   - timeout: How long to keep polling before giving up.
    ///   - condition: The predicate to wait for.
    private static func waitUntil(timeout: Duration, _ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while await !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.pollInterval)
        }
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
