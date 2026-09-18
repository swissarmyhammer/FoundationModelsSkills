import Foundation
import Synchronization
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
    /// The debounce interval of each watcher under test.
    ///
    /// A test that asserts "exactly one callback" gives the watcher a
    /// `ManualDebounceTimer`, and the watcher then never counts this
    /// interval: the test ends the quiet period itself. The file work of a
    /// test and the quiet period of the watcher thus do not race on the
    /// real clock, and a slow host cannot divide one burst into two
    /// callbacks. Only the tests of `stop()` and of the descriptor count
    /// use the real timer with this interval, and they assert no count
    /// that the speed of the host can change.
    private static let testDebounceInterval: DispatchTimeInterval = .milliseconds(150)

    /// How long a test waits for an expected event or callback to arrive
    /// before treating its absence as a failure. Generous, to absorb
    /// scheduler and filesystem-event jitter in a sandboxed test
    /// environment. A longer wait can only make a test slower; it cannot
    /// change a result.
    private static let expectedSignalTimeout: Duration = .seconds(10)

    /// How long a test waits to confirm that something does NOT occur: no
    /// second callback after the expected one, and no timer start for
    /// activity the watcher must ignore.
    private static let noFurtherSignalWindow: Duration = .seconds(1)

    /// How many times the burst test writes `SKILL.md`.
    private static let burstWriteCount = 5

    /// The smallest number of debounce timer starts the burst test waits
    /// for before it ends the quiet period. The skill folder and
    /// `SKILL.md` each have a source of their own, and the burst changes
    /// the two, so the watcher starts a timer two times or more. Fewer
    /// than two starts cannot show that a later start replaces an earlier
    /// one.
    private static let burstTimerStartFloor = 2

    // MARK: - Create / edit / delete each coalesce to exactly one callback

    @Test func creatingASkillFileProducesExactlyOneCoalescedCallback() async throws {
        try await Self.withWatchedTempRoot { root, signals in
            try ReloadTestSupport.writeSkillFile(id: "new-skill", in: root)
            _ = await Self.expectExactlyOneSignal(signals, since: 0)
        }
    }

    @Test func editingASkillFileProducesExactlyOneCoalescedCallback() async throws {
        try await Self.withWatchedTempRoot { root, signals in
            try ReloadTestSupport.writeSkillFile(id: "existing-skill", in: root)
            let baseline = await Self.expectExactlyOneSignal(signals, since: 0)

            try ReloadTestSupport.writeSkillFile(id: "existing-skill", in: root, descriptionSuffix: "edited")
            _ = await Self.expectExactlyOneSignal(signals, since: baseline)
        }
    }

    @Test func deletingASkillFileProducesExactlyOneCoalescedCallback() async throws {
        try await Self.withWatchedTempRoot { root, signals in
            try ReloadTestSupport.writeSkillFile(id: "doomed-skill", in: root)
            let baseline = await Self.expectExactlyOneSignal(signals, since: 0)

            try FileManager.default.removeItem(
                at: root.appendingPathComponent("doomed-skill", isDirectory: true))
            _ = await Self.expectExactlyOneSignal(signals, since: baseline)
        }
    }

    // MARK: - Burst coalescing

    @Test func burstOfWritesWithinTheDebounceWindowProducesExactlyOneCallback() async throws {
        try await Self.withWatchedTempRoot { root, signals in
            // The first flush makes the watch tree again, so the skill
            // folder and `SKILL.md` each have a source of their own before
            // the burst starts.
            try ReloadTestSupport.writeSkillFile(id: "burst-skill", in: root)
            let baseline = await Self.expectExactlyOneSignal(signals, since: 0)

            let skillFile = root
                .appendingPathComponent("burst-skill", isDirectory: true)
                .appendingPathComponent("SKILL.md")
            for iteration in 0..<Self.burstWriteCount {
                try ReloadTestSupport.skillFileContents(id: "burst-skill", descriptionSuffix: "rev\(iteration)")
                    .write(to: skillFile, atomically: true, encoding: .utf8)
            }

            // The quiet period ends only when the test says so, thus the
            // full burst is in one debounce window on a host of any speed.
            // A watcher that did not replace the earlier timer fires one
            // callback for each timer start, and this expectation fails.
            _ = await Self.expectExactlyOneSignal(
                signals, since: baseline, afterTimerStarts: Self.burstTimerStartFloor)
        }
    }

    // MARK: - Recursion: nested SKILL.md and _partials/ both count

    @Test func skillFileNestedTwoLevelsDeepIsDetected() async throws {
        try await Self.withWatchedTempRoot { root, signals in
            try ReloadTestSupport.writeSkillFile(id: "nested-skill", in: root)
            _ = await Self.expectExactlyOneSignal(signals, since: 0)
        }
    }

    @Test func editingAFileUnderPartialsIsDetected() async throws {
        try await Self.withWatchedTempRoot { root, signals in
            let partialsDirectory = root.appendingPathComponent("_partials", isDirectory: true)
            try FileManager.default.createDirectory(at: partialsDirectory, withIntermediateDirectories: true)
            let baseline = await Self.expectExactlyOneSignal(signals, since: 0)

            try "header text".write(
                to: partialsDirectory.appendingPathComponent("header.md"), atomically: true, encoding: .utf8)
            _ = await Self.expectExactlyOneSignal(signals, since: baseline)
        }
    }

    // MARK: - Unfiltered directories still coalesce safely

    @Test func eventsUnderAGitDirectoryStillCoalesceWithoutCrashing() async throws {
        try await Self.withWatchedTempRoot { root, signals in
            let gitDirectory = root.appendingPathComponent(".git", isDirectory: true)
            try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
            let baseline = await Self.expectExactlyOneSignal(signals, since: 0)

            try "ref: refs/heads/main\n".write(
                to: gitDirectory.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
            _ = await Self.expectExactlyOneSignal(signals, since: baseline)
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
        try await Self.withTempDirectory { privateDirectory in
            let bogusRoot = privateDirectory.appendingPathComponent("does-not-exist", isDirectory: true)
            try await Self.withTempDirectory { realRoot in
                try await Self.withWatcher(over: [bogusRoot, realRoot]) { signals in
                    try ReloadTestSupport.writeSkillFile(id: "still-works", in: realRoot)
                    _ = await Self.expectExactlyOneSignal(signals, since: 0)
                }
            }
        }
    }

    // MARK: - Late root creation (^80kravf): armed via nearest existing ancestor

    @Test func creatingARootThatDidNotExistAtStartIsDetected() async throws {
        try await Self.withTempDirectory { privateDirectory in
            let lateRoot = privateDirectory.appendingPathComponent("skills-arrive-later", isDirectory: true)
            try await Self.withWatcher(over: [lateRoot]) { signals in
                try ReloadTestSupport.writeSkillFile(id: "arrived-skill", in: lateRoot)
                _ = await Self.expectExactlyOneSignal(signals, since: 0)
            }
        }
    }

    @Test func deletingAndRecreatingARootKeepsEventsFlowing() async throws {
        try await Self.withTempDirectory { privateDirectory in
            let root = privateDirectory.appendingPathComponent("comes-and-goes", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try await Self.withWatcher(over: [root]) { signals in
                try ReloadTestSupport.writeSkillFile(id: "before-delete", in: root)
                let afterFirstCreate = await Self.expectExactlyOneSignal(signals, since: 0)

                try FileManager.default.removeItem(at: root)
                let afterDelete = await Self.expectExactlyOneSignal(signals, since: afterFirstCreate)

                // The root is gone -- `flush()`'s rebuild must have fallen
                // back to arming `privateDirectory` (the now-nearest existing
                // ancestor), not silently stopped watching anything at all.
                try ReloadTestSupport.writeSkillFile(id: "after-recreate", in: root)
                _ = await Self.expectExactlyOneSignal(signals, since: afterDelete)
            }
        }
    }

    @Test func editingAFileUnderALateCreatedRootFiresAfterEscalation() async throws {
        try await Self.withTempDirectory { privateDirectory in
            let lateRoot = privateDirectory.appendingPathComponent("skills-arrive-later", isDirectory: true)
            try await Self.withWatcher(over: [lateRoot]) { signals in
                try ReloadTestSupport.writeSkillFile(id: "arrived-skill", in: lateRoot)
                let afterCreate = await Self.expectExactlyOneSignal(signals, since: 0)

                // The flush above rebuilt the watch tree, so `lateRoot` is
                // now watched recursively. An edit two levels under it never
                // touches `privateDirectory`, so only the recursive watch
                // can see it -- the ancestor watch alone cannot.
                try ReloadTestSupport.writeSkillFile(id: "arrived-skill", in: lateRoot, descriptionSuffix: "edited")
                _ = await Self.expectExactlyOneSignal(signals, since: afterCreate)
            }
        }
    }

    @Test func unrelatedActivityUnderAnArmedAncestorProducesNoCallback() async throws {
        try await Self.withTempDirectory { privateDirectory in
            let lateRoot = privateDirectory.appendingPathComponent("skills-arrive-later", isDirectory: true)
            try await Self.withWatcher(over: [lateRoot]) { signals in
                // `privateDirectory` is the armed ancestor. Activity directly
                // under it that does not create `lateRoot` must not reach
                // `onChange`.
                let unrelated = privateDirectory.appendingPathComponent("unrelated", isDirectory: true)
                try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
                try "noise".write(to: unrelated.appendingPathComponent("noise.txt"), atomically: true, encoding: .utf8)
                try FileManager.default.removeItem(at: unrelated)
                // The ancestor filter must drop the noise before it starts a
                // debounce timer. With the manual timer, a callback count of
                // zero proves nothing by itself, so the timer starts are the
                // evidence.
                await Self.waitUntil(timeout: Self.noFurtherSignalWindow) { signals.timer.pendingCount > 0 }
                #expect(signals.timer.pendingCount == 0)
                #expect(await signals.recorder.count == 0)

                // Creating the awaited root itself still fires.
                try ReloadTestSupport.writeSkillFile(id: "arrived-skill", in: lateRoot)
                _ = await Self.expectExactlyOneSignal(signals, since: 0)
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
            try await Self.withWatcher(over: [deepRoot]) { signals in
                // Creating the whole chain at once makes `a` appear directly
                // under the armed ancestor, which is the awaited child.
                try ReloadTestSupport.writeSkillFile(id: "deep-skill", in: deepRoot)
                let afterCreate = await Self.expectExactlyOneSignal(signals, since: 0)

                // The flush above escalated to a real recursive watch of
                // `deepRoot`; an edit four levels below `privateDirectory`
                // is only visible through that watch.
                try ReloadTestSupport.writeSkillFile(id: "deep-skill", in: deepRoot, descriptionSuffix: "edited")
                _ = await Self.expectExactlyOneSignal(signals, since: afterCreate)
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
            try await Self.withWatcher(over: [root]) { signals in
                try ReloadTestSupport.writeSkillFile(id: "readable-skill", in: root)
                _ = await Self.expectExactlyOneSignal(signals, since: 0)
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

    // MARK: - A change made while onChange runs is not lost (^sz7fz7n)

    /// A host that sees a reload can change a file immediately, while the
    /// watcher is still in the flush that made the reload. The edit here is
    /// made inside `onChange`, thus it is in that flush on a host of any
    /// speed. A watcher that opens its new sources only after `onChange`
    /// drops the event: the old sources are cancelled with the event
    /// pending, and the new sources open after the edit.
    @Test func aChangeMadeWhileOnChangeRunsIsReportedAfterTheFlush() async throws {
        try await Self.withTempDirectory { root in
            try ReloadTestSupport.writeSkillFile(id: "edited-in-flush", in: root)
            let edit = OneTimeEdit(skillID: "edited-in-flush", root: root)

            try await Self.withWatcher(over: [root], duringOnChange: edit.run) { signals in
                try ReloadTestSupport.writeSkillFile(id: "edited-in-flush", in: root, descriptionSuffix: "first edit")
                await Self.waitUntil(timeout: Self.expectedSignalTimeout) { signals.timer.pendingCount >= 1 }
                signals.timer.endQuietPeriod()

                // The edit inside `onChange` must start a new timer.
                // `endQuietPeriod()` fires that timer itself when the event
                // arrives before its loop ends, and the second callback is
                // then the evidence.
                await Self.waitUntil(timeout: Self.expectedSignalTimeout) {
                    await Self.reportedTheEditInsideOnChange(signals)
                }
                #expect(edit.failure == nil)
                #expect(await Self.reportedTheEditInsideOnChange(signals))
            }
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

        try ReloadTestSupport.writeSkillFile(id: "after-stop", in: root)
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

        try ReloadTestSupport.writeSkillFile(id: "self-stopping", in: root)
        let afterFirstFlush = await Self.waitForCount(recorder, atLeast: 1, timeout: Self.expectedSignalTimeout)
        #expect(afterFirstFlush == 1)

        // The reentrant `stop()` must have actually torn every source
        // down, not just flipped a flag: the sources that `flush()` opened
        // before `onChange` must not stay open underneath a watcher that
        // was just told to stop.
        #expect(box.watcher?.watchedSourceCountForTesting == 0)

        // The reentrant `stop()` above ran synchronously inside `onChange`
        // (proving `runOnQueue(_:)`'s reentrancy guard doesn't deadlock),
        // so a further change on the same root must not produce a second
        // signal: the watcher must already be genuinely stopped, not just
        // about to be.
        try ReloadTestSupport.writeSkillFile(id: "should-not-be-seen", in: root)
        let afterIgnoredChange = await Self.waitForCount(recorder, atLeast: 2, timeout: Self.noFurtherSignalWindow)
        #expect(afterIgnoredChange == 1)

        // Restarting the same instance afterward must work normally -- the
        // reentrant stop must not leave it permanently unable to watch
        // again.
        box.watcher?.start()
        defer { box.watcher?.stop() }
        try ReloadTestSupport.writeSkillFile(id: "after-restart", in: root)
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

    /// A debounce timer that a test ends by hand.
    ///
    /// `start` records each timer the watcher starts and never fires one by
    /// itself. `endQuietPeriod()` fires them. The length of the quiet period
    /// is thus a decision of the test, not a race between the file work of
    /// the test and the real clock.
    ///
    /// A `Mutex` guards the list, thus the compiler checks the plain
    /// `Sendable` conformance.
    private final class ManualDebounceTimer: Sendable {
        /// One timer the watcher started: the queue to fire on, and the
        /// closure to fire.
        private struct StartedTimer: Sendable {
            let queue: DispatchQueue
            let fire: @Sendable () -> Void
        }

        /// The timers the watcher started that `endQuietPeriod()` did not
        /// fire yet, in start order.
        private let startedTimers = Mutex<[StartedTimer]>([])

        /// The closure to give to `SkillWatcher` as its debounce timer.
        var start: SkillWatcher.DebounceTimer {
            { [self] _, queue, fire in
                startedTimers.withLock { $0.append(StartedTimer(queue: queue, fire: fire)) }
            }
        }

        /// The number of timers the watcher started that are not fired yet.
        var pendingCount: Int {
            startedTimers.withLock { $0.count }
        }

        /// Fires each started timer on its queue, in start order, until none
        /// is left.
        ///
        /// An event that arrived immediately before this call can start one
        /// more timer while the earlier ones fire. That start makes the
        /// earlier ones stale, thus one pass is not sufficient. `sync` also
        /// makes sure that the flush, and the new watch tree that the flush
        /// makes, are complete when this method returns.
        func endQuietPeriod() {
            var due = takeStartedTimers()
            while !due.isEmpty {
                for timer in due {
                    timer.queue.sync(execute: timer.fire)
                }
                due = takeStartedTimers()
            }
        }

        /// Removes and returns each timer that is not fired yet.
        ///
        /// - Returns: The timers, in start order.
        private func takeStartedTimers() -> [StartedTimer] {
            startedTimers.withLock { timers in
                defer { timers.removeAll() }
                return timers
            }
        }
    }

    /// What a test of a watcher with a manual debounce timer observes and
    /// controls: the callbacks that arrived, and the end of the quiet
    /// period.
    private struct WatchedSignals {
        /// The tally of `onChange` calls.
        let recorder: SignalRecorder

        /// The debounce timer of the watcher.
        let timer: ManualDebounceTimer
    }

    /// Starts a `SkillWatcher` over a fresh temporary root, hands the root
    /// and its signals to `body`, then tears the watcher and the temporary
    /// directory down unconditionally.
    ///
    /// - Parameter body: The test body, given the watched root and the
    ///   signals of the watcher.
    /// - Throws: Whatever `body` or the temp-directory setup throws.
    private static func withWatchedTempRoot(
        _ body: (URL, WatchedSignals) async throws -> Void
    ) async throws {
        try await Self.withTempDirectory { root in
            try await Self.withWatcher(over: [root]) { signals in
                try await body(root, signals)
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

    /// Starts a `SkillWatcher` with a manual debounce timer over `roots`,
    /// hands its signals to `body`, then stops the watcher unconditionally.
    ///
    /// - Parameters:
    ///   - roots: The roots to watch, in the order the watcher receives them.
    ///   - work: More work that `onChange` does after it records the
    ///     callback, on the queue of the watcher. The default does nothing.
    ///   - body: The test body, given the signals of the watcher.
    /// - Throws: Whatever `body` throws.
    private static func withWatcher(
        over roots: [URL], duringOnChange work: @escaping @Sendable () -> Void = {},
        _ body: (WatchedSignals) async throws -> Void
    ) async throws {
        let (recordSignal, recorder) = Self.makeSignalRecorder()
        let timer = ManualDebounceTimer()
        let watcher = SkillWatcher(
            roots: roots, debounceInterval: Self.testDebounceInterval, startDebounceTimer: timer.start
        ) {
            recordSignal()
            work()
        }
        watcher.start()
        defer { watcher.stop() }
        try await body(WatchedSignals(recorder: recorder, timer: timer))
    }

    /// Edits one `SKILL.md` the first time `run()` is called, and does
    /// nothing on each later call.
    ///
    /// A test gives `run` to a watcher as work inside `onChange`. The edit
    /// is then in the flush that made the callback, and only the first
    /// flush makes an edit, thus the test has an end.
    ///
    /// A `Mutex` guards each mutable value, thus the compiler checks the
    /// plain `Sendable` conformance.
    private final class OneTimeEdit: Sendable {
        private let skillID: String
        private let root: URL
        private let hasRun = Mutex(false)
        private let failureText = Mutex<String?>(nil)

        /// The error text of an edit that failed, or `nil`.
        var failure: String? {
            failureText.withLock { $0 }
        }

        /// - Parameters:
        ///   - skillID: The id of the skill whose `SKILL.md` the edit writes.
        ///   - root: The watched root that holds the skill.
        init(skillID: String, root: URL) {
            self.skillID = skillID
            self.root = root
        }

        /// Writes the file on the first call only. A write error goes to
        /// `failure`, because `onChange` cannot throw.
        @Sendable func run() {
            let isFirstCall = hasRun.withLock { hasRun in
                defer { hasRun = true }
                return !hasRun
            }
            guard isFirstCall else { return }
            do {
                try ReloadTestSupport.writeSkillFile(id: skillID, in: root, descriptionSuffix: "edit inside onChange")
            } catch {
                failureText.withLock { $0 = String(describing: error) }
            }
        }
    }

    /// The number of callbacks that shows that the watcher reported the
    /// edit of a `OneTimeEdit`: one for the flush that holds the edit, and
    /// one for the edit.
    private static let callbacksWithTheEditInsideOnChange = 2

    /// Whether the watcher reported the edit that a `OneTimeEdit` made
    /// inside `onChange`: a debounce timer is pending, or the callback for
    /// the edit arrived already.
    ///
    /// - Parameter signals: The signals of the watcher under test.
    /// - Returns: `true` when the watcher reported the edit.
    private static func reportedTheEditInsideOnChange(_ signals: WatchedSignals) async -> Bool {
        if signals.timer.pendingCount >= 1 {
            return true
        }
        return await signals.recorder.count >= Self.callbacksWithTheEditInsideOnChange
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

    /// Asserts that the file work the test did immediately before makes
    /// exactly one new signal after `baseline`.
    ///
    /// The steps: wait until the watcher started `minimumTimerStarts`
    /// debounce timers, confirm that the events made no callback by
    /// themselves, end the quiet period, then confirm that the count
    /// reaches `baseline + 1` and stays there through
    /// `noFurtherSignalWindow`.
    ///
    /// - Parameters:
    ///   - signals: The signals of the watcher under test.
    ///   - baseline: The count observed before the action under test.
    ///   - minimumTimerStarts: How many timer starts to wait for before the
    ///     quiet period ends.
    /// - Returns: The settled count, for chaining a further action's
    ///   `baseline` in the same test.
    @discardableResult
    private static func expectExactlyOneSignal(
        _ signals: WatchedSignals, since baseline: Int, afterTimerStarts minimumTimerStarts: Int = 1
    ) async -> Int {
        await Self.waitUntil(timeout: Self.expectedSignalTimeout) {
            signals.timer.pendingCount >= minimumTimerStarts
        }
        #expect(signals.timer.pendingCount >= minimumTimerStarts)
        #expect(await signals.recorder.count == baseline)

        signals.timer.endQuietPeriod()
        let afterFirst = await Self.waitForCount(
            signals.recorder, atLeast: baseline + 1, timeout: Self.expectedSignalTimeout)
        #expect(afterFirst == baseline + 1)

        let afterSettling = await Self.waitForCount(
            signals.recorder, atLeast: baseline + 2, timeout: Self.noFurtherSignalWindow)
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
}
