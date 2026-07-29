import Foundation

/// Debounced "something changed" signal over every host-supplied skill layer
/// root (plan.md §7, decision #29 as amended).
///
/// Watches each existing root's directory tree recursively -- every
/// directory and file currently under it, however deep -- and coalesces a
/// burst of filesystem activity (an editor save's several rapid writes, a
/// `mkdir` followed by writing several files into it, ...) into a single
/// `onChange` call fired after a quiet period. It carries no opinion about
/// *what* changed or what to do about it: the caller (a registry's reload
/// task) is expected to re-run its own discovery from scratch on every
/// `onChange` call rather than infer anything from watcher internals. A
/// root that does not exist when `start()` runs is armed rather than
/// skipped: its nearest existing ancestor directory is watched instead, so
/// the root's later creation (or a delete-then-recreate cycle) still fires
/// `onChange` -- the rebuild every `flush()` performs re-resolves each
/// root's existence from scratch, escalating from an ancestor-only watch to
/// the real recursive one the moment the root actually appears.
///
/// Implemented over one `DispatchSource.makeFileSystemObjectSource` per
/// watched directory and file rather than FSEvents, and rebuilt from
/// scratch after every quiet period so entries created or removed during a
/// burst are (or are no longer) watched by the time `onChange` fires.
public final class SkillWatcher: @unchecked Sendable {
    /// Marks `queue` so `runOnQueue(_:)` can detect a reentrant call from
    /// within one of this watcher's own `DispatchSource` event handlers.
    private static let queueSpecificKey = DispatchSpecificKey<Bool>()

    private let roots: [URL]
    private let debounceInterval: DispatchTimeInterval
    private let onChange: @Sendable () -> Void
    private let queue: DispatchQueue

    /// Every directory and file source currently open, keyed by absolute
    /// path.
    ///
    /// Read and mutated only while running on `queue`.
    private var watchedSources: [String: DispatchSourceFileSystemObject] = [:]

    /// The in-flight debounce timer, if a burst is currently being
    /// coalesced.
    ///
    /// Read and mutated only while running on `queue`.
    private var pendingFlush: DispatchWorkItem?

    /// Whether `start()` has run without a matching `stop()` since.
    ///
    /// Read and mutated only while running on `queue`.
    private var isWatching = false

    /// Creates a watcher over `roots`, not yet watching.
    ///
    /// - Parameters:
    ///   - roots: The layer roots to watch, in whatever order the host
    ///     supplied them -- this type names no directory convention of its
    ///     own. A root that does not exist on disk when `start()` runs has
    ///     its nearest existing ancestor directory armed instead, so the
    ///     root's later creation is still observed.
    ///   - debounceInterval: How long the tree must go quiet before a burst
    ///     of events collapses into one `onChange` call. Defaults to
    ///     200ms.
    ///   - onChange: Called at most once per quiet period, on an
    ///     unspecified queue, whenever something changed under any watched
    ///     root. Never called again once `stop()` returns.
    public init(
        roots: [URL],
        debounceInterval: DispatchTimeInterval = .milliseconds(200),
        onChange: @escaping @Sendable () -> Void
    ) {
        self.roots = roots
        self.debounceInterval = debounceInterval
        self.onChange = onChange
        queue = DispatchQueue(label: "FoundationModelsSkills.SkillWatcher")
        queue.setSpecific(key: Self.queueSpecificKey, value: true)
    }

    /// Starts watching every existing root, recursively.
    ///
    /// Safe to call more than once; a call while already watching is a
    /// no-op.
    public func start() {
        runOnQueue {
            guard !self.isWatching else { return }
            self.isWatching = true
            // Defensive: guards against ever rewatching on top of a
            // leftover source (there should never be one, since every path
            // that populates `watchedSources` is paired with a path that
            // clears it first, but this keeps `start()` correct even if
            // that pairing is ever violated elsewhere).
            self.cancelAllWatchedSources()
            self.armRoots()
        }
    }

    /// Stops watching and discards any in-flight debounce timer.
    ///
    /// No further `onChange` calls happen once `stop()` returns. Safe to
    /// call more than once, and safe to call without a prior `start()`.
    public func stop() {
        runOnQueue {
            guard self.isWatching else { return }
            self.isWatching = false
            self.pendingFlush?.cancel()
            self.pendingFlush = nil
            self.cancelAllWatchedSources()
        }
    }

    /// Cancels every open source and any in-flight debounce timer, the same
    /// as an explicit `stop()`, so a watcher that goes out of scope without
    /// one never leaks file descriptors or fires `onChange` again.
    deinit {
        stop()
    }

    /// The number of currently open watch sources.
    ///
    /// Internal, `@testable`-only: exists so a test can directly verify
    /// that a reentrant `stop()` call from within `onChange` leaves no
    /// sources open, rather than inferring it indirectly from callback
    /// timing.
    var watchedSourceCountForTesting: Int {
        queue.sync { watchedSources.count }
    }

    // MARK: - Queue reentrancy

    /// Runs `work` with exclusive access to this watcher's mutable state:
    /// inline if already running on `queue` (a nested call from within a
    /// `DispatchSource` event handler), via `queue.sync` otherwise.
    ///
    /// Avoids the deadlock a plain `queue.sync` would risk if `stop()` (or
    /// `deinit`) ever ran from within an `onChange` call that itself
    /// executes on `queue`.
    ///
    /// - Parameter work: The work to perform.
    private func runOnQueue(_ work: @escaping () -> Void) {
        guard DispatchQueue.getSpecific(key: Self.queueSpecificKey) == nil else {
            work()
            return
        }
        queue.sync(execute: work)
    }

    // MARK: - Watch tree construction

    /// Arms every root in `roots`: an existing one gets the real recursive
    /// watch; a missing one gets its nearest existing ancestor directory
    /// watched instead, so the root's later creation still fires
    /// `onChange` (the next `flush()` re-runs this and escalates to the
    /// real watch once the root exists).
    ///
    /// Always called on `queue`.
    private func armRoots() {
        for root in roots {
            if FileManager.default.fileExists(atPath: root.path) {
                watchTree(at: root)
            } else if let ancestor = Self.nearestExistingAncestor(of: root), watchedSources[ancestor.path] == nil {
                watchEntry(at: ancestor, eventMask: [.write, .delete, .rename])
            }
        }
    }

    /// The nearest existing ancestor directory of `url`, walking up
    /// `deletingLastPathComponent()` until one exists on disk.
    ///
    /// - Parameter url: The (possibly nonexistent) path to find an existing
    ///   ancestor for.
    /// - Returns: The nearest existing ancestor, or `nil` when even the
    ///   volume root doesn't exist (practically unreachable).
    private static func nearestExistingAncestor(of url: URL) -> URL? {
        var candidate = url.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
        return candidate
    }

    /// Recursively opens a `DispatchSource` for `directory` and every entry
    /// currently under it, adding each to `watchedSources`.
    ///
    /// Always called on `queue`.
    ///
    /// - Parameter directory: The directory to watch, along with its
    ///   descendants.
    private func watchTree(at directory: URL) {
        watchEntry(at: directory, eventMask: [.write, .delete, .rename])
        for child in Self.directoryContents(of: directory) {
            if child.isDirectory {
                watchTree(at: child.url)
            } else {
                watchEntry(at: child.url, eventMask: [.write, .delete, .rename, .extend, .attrib])
            }
        }
    }

    /// Opens one `DispatchSource` for `url`, observing `eventMask`, and
    /// stores it in `watchedSources`.
    ///
    /// A path that cannot be opened (e.g. a broken symlink, or a
    /// permission error) is simply skipped, not treated as an error. Always
    /// called on `queue`.
    ///
    /// - Parameters:
    ///   - url: The file or directory to watch.
    ///   - eventMask: The events to observe on `url`.
    private func watchEntry(at url: URL, eventMask: DispatchSource.FileSystemEvent) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: eventMask, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleRawEvent()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        watchedSources[url.path] = source
        source.resume()
    }

    /// Cancels and discards every currently open source.
    ///
    /// Always called on `queue`.
    private func cancelAllWatchedSources() {
        for source in watchedSources.values {
            source.cancel()
        }
        watchedSources.removeAll()
    }

    // MARK: - Event handling

    /// Restarts the shared debounce timer.
    ///
    /// Always called on `queue`, from a `DispatchSource` event handler.
    private func handleRawEvent() {
        guard isWatching else { return }
        pendingFlush?.cancel()
        let flush = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        pendingFlush = flush
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: flush)
    }

    /// Fires the coalesced `onChange` callback once, then rebuilds the
    /// watch tree from the roots' current on-disk state so entries created
    /// or removed during the burst are (or are no longer) watched going
    /// forward.
    ///
    /// Always called on `queue`, at the end of a quiet period. `onChange`
    /// is free to call `stop()` reentrantly (`runOnQueue(_:)` makes that
    /// safe); `isWatching` is re-checked afterward so a callback that
    /// stops the watcher is honored immediately, rather than having the
    /// rebuild below silently resurrect a fresh set of sources underneath
    /// it.
    private func flush() {
        guard isWatching else { return }
        pendingFlush = nil
        onChange()
        guard isWatching else { return }
        cancelAllWatchedSources()
        armRoots()
    }

    // MARK: - Directory listing

    /// One directory entry `directoryContents(of:)` returns: its URL and
    /// whether it is itself a directory.
    private struct DirectoryEntry {
        let url: URL
        let isDirectory: Bool
    }

    /// Lists `directory`'s immediate contents.
    ///
    /// An unreadable or nonexistent `directory` contributes no entries
    /// rather than throwing.
    ///
    /// - Parameter directory: The directory to list.
    /// - Returns: One `DirectoryEntry` per immediate child.
    private static func directoryContents(of directory: URL) -> [DirectoryEntry] {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        else {
            return []
        }
        return entries.map { entry in
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return DirectoryEntry(url: entry, isDirectory: isDirectory)
        }
    }
}
