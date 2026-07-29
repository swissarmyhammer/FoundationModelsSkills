/// The result of a `run script` operation: the process's outcome, its exit
/// code, timing, and a bounded tail of its merged stdout+stderr (plan.md
/// §7.3, the Shelltool result shape).
public struct RunScriptResult: Encodable, Sendable, Equatable {
    /// The run script's owning skill id.
    public let id: String

    /// The script's path, relative to the skill directory.
    public let path: String

    /// `"completed"`, `"timed_out"`, or `"failed"`.
    public let status: String

    /// The process's exit code, or `nil` when it never exited normally
    /// (timed out or killed).
    public let exitCode: Int?

    /// Wall-clock duration of the run, in milliseconds.
    public let durationMs: Int

    /// The total number of merged stdout+stderr lines captured, even when
    /// `output` was truncated to its tail.
    public let lines: Int

    /// The last (at most) 32 captured lines, each formatted `"{n}: {text}"`
    /// with `n` the line's 1-based arrival order.
    public let output: [String]

    /// Creates a `RunScriptResult` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - id: The run script's owning skill id.
    ///   - path: The script's path, relative to the skill directory.
    ///   - status: `"completed"`, `"timed_out"`, or `"failed"`.
    ///   - exitCode: The process's exit code, or `nil`.
    ///   - durationMs: Wall-clock duration of the run, in milliseconds.
    ///   - lines: The total number of merged stdout+stderr lines captured.
    ///   - output: The last (at most) 32 captured lines, formatted.
    public init(id: String, path: String, status: String, exitCode: Int?, durationMs: Int, lines: Int, output: [String])
    {
        self.id = id
        self.path = path
        self.status = status
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.lines = lines
        self.output = output
    }
}
