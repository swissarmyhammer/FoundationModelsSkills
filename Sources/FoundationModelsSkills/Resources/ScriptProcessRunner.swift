import Darwin
import Foundation

/// Exec's a script file directly (no shell) in its own process group,
/// merging its stdout+stderr, and enforces a timeout by `SIGKILL`ing the
/// whole group (plan.md §7.3.1).
///
/// Spawns via raw `posix_spawn` rather than `Foundation.Process`:
/// `Process` exposes no way to atomically place the spawned child (and
/// therefore every grandchild it forks before exec completes) into a new
/// process group -- only `POSIX_SPAWN_SETPGROUP`, applied as part of the
/// spawn syscall itself, closes that race. Without it, a script that
/// backgrounds its own child (`sleep 100 &`) could still be running after a
/// timeout `SIGKILL`s only the direct child.
internal enum ScriptProcessRunner {
    /// One run's terminal state -- mirrors `RunScriptResult.status`'s three
    /// literal values, but as an enum internally so a typo'd status string
    /// can never compile, matching plan.md §7.3's spelling exactly via
    /// `rawValue`.
    internal enum Status: String, Sendable {
        /// The process exited on its own, before the timeout.
        case completed

        /// The timeout fired; the process's whole group was `SIGKILL`ed.
        case timedOut = "timed_out"

        /// `posix_spawn` itself never reached exec.
        case failed
    }

    /// One run's outcome.
    internal struct Outcome: Sendable {
        /// This run's terminal state.
        internal let status: Status

        /// The process's exit code, or `nil` when it never exited normally
        /// (timed out, killed, or failed to spawn).
        internal let exitCode: Int32?

        /// Wall-clock duration of the run, in milliseconds.
        internal let durationMs: Int

        /// The total number of merged stdout+stderr lines captured, even
        /// when `output` was truncated to its tail.
        internal let lines: Int

        /// The last `tailLineCount` captured lines, each formatted
        /// `"{n}: {text}"` with `n` the line's 1-based arrival order.
        internal let output: [String]
    }

    /// `.failed` outcomes carry only this: `posix_spawn` itself never
    /// reached exec, so there is no duration, no output, and no exit code
    /// to report.
    internal static let failedToSpawn = Outcome(status: .failed, exitCode: nil, durationMs: 0, lines: 0, output: [])

    /// The number of trailing output lines a run's `output` tail carries
    /// (plan.md §7.3, the Shelltool shape).
    private static let tailLineCount = 32

    /// Runs `executableURL` directly (no shell), in its own process group.
    ///
    /// - Parameters:
    ///   - executableURL: The script file to exec.
    ///   - arguments: Positional arguments to pass.
    ///   - workingDirectory: The child's working directory.
    ///   - timeout: How long to allow the run before `SIGKILL`ing its
    ///     process group.
    /// - Returns: The run's outcome.
    internal static func run(
        executableURL: URL, arguments: [String], workingDirectory: URL, timeout: TimeInterval
    ) async -> Outcome {
        let pipe = Pipe()
        guard
            let pid = Self.spawn(
                executableURL: executableURL, arguments: arguments, workingDirectory: workingDirectory,
                writeFD: pipe.fileHandleForWriting.fileDescriptor)
        else {
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
            return Self.failedToSpawn
        }

        // The parent's own copy of the write end must close so EOF becomes
        // observable on the read end once every process referencing the
        // dup'd copies (the child, and any grandchildren it forks before
        // exec) has exited.
        try? pipe.fileHandleForWriting.close()

        let start = ContinuousClock.now
        async let capturedData = Self.readAllBlocking(from: pipe.fileHandleForReading)
        let (exitCode, timedOut) = await Self.waitOrTimeout(pid: pid, timeout: timeout)
        let data = await capturedData
        try? pipe.fileHandleForReading.close()

        let durationMs = Int(start.duration(to: .now).components.seconds * 1000)
        let allLines = Self.lines(of: data)
        let tail = Self.tailFormatted(lines: allLines)
        return Outcome(
            status: timedOut ? .timedOut : .completed, exitCode: exitCode, durationMs: durationMs,
            lines: allLines.count, output: tail)
    }

    // MARK: - Spawn

    /// Spawns `executableURL` via `posix_spawn`, in its own process group,
    /// with `writeFD` dup'd to both stdout and stderr.
    ///
    /// - Parameters:
    ///   - executableURL: The script file to exec.
    ///   - arguments: Positional arguments to pass.
    ///   - workingDirectory: The child's working directory.
    ///   - writeFD: The pipe write end to dup to stdout/stderr.
    /// - Returns: The spawned child's pid, or `nil` if `posix_spawn` itself
    ///   failed.
    private static func spawn(
        executableURL: URL, arguments: [String], workingDirectory: URL, writeFD: Int32
    ) -> pid_t? {
        var fileActions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, writeFD, 1)
        posix_spawn_file_actions_adddup2(&fileActions, writeFD, 2)
        posix_spawn_file_actions_addclose(&fileActions, writeFD)
        posix_spawn_file_actions_addchdir(&fileActions, workingDirectory.path)

        var attributes: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)

        let executablePath = executableURL.path
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(executablePath)]
        argv.append(contentsOf: arguments.map { strdup($0) })
        argv.append(nil)
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, executablePath, &fileActions, &attributes, argv, environ)
        return spawnResult == 0 ? pid : nil
    }

    // MARK: - Wait / timeout race

    /// Either `pid`'s wait outcome, or a timeout.
    private enum RaceOutcome: Sendable {
        case exited(Int32?)
        case timedOut
    }

    /// Races `pid`'s exit against `timeout`, `SIGKILL`ing `pid`'s whole
    /// process group if the timeout wins.
    ///
    /// - Parameters:
    ///   - pid: The process (and process-group leader) to wait for.
    ///   - timeout: How long to wait before killing the group.
    /// - Returns: The exit code (`nil` if killed or never reaped) and
    ///   whether the timeout fired.
    private static func waitOrTimeout(pid: pid_t, timeout: TimeInterval) async -> (
        exitCode: Int32?, timedOut: Bool
    ) {
        await withTaskGroup(of: RaceOutcome.self) { group in
            group.addTask { .exited(await Self.waitBlocking(pid: pid)) }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return .timedOut
            }

            guard let first = await group.next() else { return (nil, true) }
            switch first {
            case .exited(let exitCode):
                group.cancelAll()
                return (exitCode, false)
            case .timedOut:
                _ = killpg(pid, SIGKILL)
                // The still-running wait task unblocks once the group
                // dies; consume its eventual result rather than issuing a
                // second, redundant `waitpid` for the same pid.
                guard case .exited(let exitCode) = await group.next() else {
                    return (nil, true)
                }
                return (exitCode, true)
            }
        }
    }

    /// Blocks (on a background thread) until `pid` exits, then reports its
    /// exit code.
    ///
    /// - Parameter pid: The process to wait for.
    /// - Returns: The exit code for a normal exit, or `nil` when `pid`
    ///   terminated by signal or `waitpid` itself failed.
    private static func waitBlocking(pid: pid_t) async -> Int32? {
        await Self.runOnGlobalQueue {
            var status: Int32 = 0
            let waited = waitpid(pid, &status, 0)
            guard waited == pid, (status & 0x7f) == 0 else { return nil }
            return (status >> 8) & 0xff
        }
    }

    // MARK: - Output capture

    /// Blocks (on a background thread) reading `handle` until EOF.
    ///
    /// - Parameter handle: The pipe read end to drain.
    /// - Returns: Every byte read.
    private static func readAllBlocking(from handle: FileHandle) async -> Data {
        await Self.runOnGlobalQueue { handle.readDataToEndOfFile() }
    }

    /// Runs a blocking `work` closure on the global utility-QoS dispatch
    /// queue, bridging it to `async` -- the single place `waitBlocking` and
    /// `readAllBlocking` share this `withCheckedContinuation` wiring, so
    /// neither repeats it as its own inline continuation.
    ///
    /// - Parameter work: The blocking work to run off the cooperative pool.
    /// - Returns: `work`'s result.
    private static func runOnGlobalQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: work())
            }
        }
    }

    /// Splits `data` (interpreted as UTF-8, lossily) into lines.
    ///
    /// - Parameter data: The captured merged stdout+stderr bytes.
    /// - Returns: The captured lines, in arrival order.
    private static func lines(of data: Data) -> [String] {
        String(decoding: data, as: UTF8.self).splitIntoLines.map(String.init)
    }

    /// Formats `lines`' last `tailLineCount` entries as `"{n}: {text}"`,
    /// `n` the line's 1-based arrival order.
    ///
    /// - Parameter lines: Every captured line, in arrival order.
    /// - Returns: The formatted tail.
    private static func tailFormatted(lines: [String]) -> [String] {
        let startIndex = max(lines.count - Self.tailLineCount, 0)
        return lines.enumerated().dropFirst(startIndex).map { index, text in
            "\(index + 1): \(text)"
        }
    }
}
