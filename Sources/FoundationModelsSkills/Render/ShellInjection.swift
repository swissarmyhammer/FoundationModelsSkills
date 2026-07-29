import Foundation

/// Pass 2 of the §5 render pipeline: shell-command injection, body renders only.
///
/// Recognizes two forms, both single-shot over the *original* input text (never re-scanning
/// substituted output, satisfying `RenderPass`'s no-re-scan contract the same way
/// `ArgumentSubstitution` does): inline `` !`command` ``, matched only when the `!` sits at the
/// very start of `text` or immediately after a whitespace character (a mid-word `` foo!`cmd` ``
/// never matches, so it is left untouched, verbatim); and fenced ` ```! ` blocks, whose entire
/// fenced region -- opening fence line through closing fence line -- is replaced by its
/// contents' execution. Every match is resolved from one left-to-right scan
/// (`Self.injectionPattern.matches(in:range:)`) computed once against the pass's input, so a
/// shell command's own output -- even output shaped like `$0`, another `` !`command` ``, or
/// `{{ HOME }}`, none of which this pass or an earlier one ever sees again -- is spliced in after
/// matching has already finished and can never trigger a second match.
///
/// Each recognized command runs via `/bin/sh -c`, with `RenderRequest.skillDirectory` as its
/// working directory and the host process's environment fully inherited (plan.md decision #28's
/// "scrubbing... while `` !`env` `` runs unscrubbed would be theater" rationale, applied here to
/// its own §5 shell). Merged stdout+stderr is captured and inlined as plain text at the
/// injection site, with trailing newlines trimmed (matching POSIX `$(...)` command-substitution
/// semantics, the shell convention this syntax otherwise mirrors). Commands re-execute on every
/// `render(_:request:)` call -- this pass holds no cache, so "dynamic at render, static in
/// transcript" (plan.md §5) falls out of `RenderPass`'s per-call contract with no extra
/// bookkeeping here.
///
/// **Body only.** `RenderPipeline.renderMetadata` never includes this pass in its pass-set
/// (`description`/`metadata.*` values render at metadata-build/reload/list time, where shell
/// execution would fire on every watcher event rather than once per call) -- enforced entirely
/// by pipeline composition, since `RenderRequest` carries no body-vs-metadata flag for this pass
/// to check itself.
///
/// **macOS only** (plan.md §8) -- this package's platform floor already excludes iOS at the
/// manifest level, so no `#if os(macOS)` guard is needed in this file itself.
public struct ShellInjection: RenderPass {
    /// The inert text every injection site is replaced with instead of running anything.
    ///
    /// Substituted when `RenderPolicy.isShellExecutionDisabled` is `true`; shared by both
    /// recognized forms (inline and fenced) -- neither is treated differently under the
    /// disabled policy.
    public static let disabledMarker = "[shell execution disabled]"

    /// Creates a `ShellInjection` pass.
    ///
    /// Takes no configuration -- every instance behaves identically, driven entirely by the
    /// `RenderRequest` each `render(_:request:)` call receives.
    public init() {}

    /// Executes every recognized `` !`command` ``/fenced ` ```! ` injection in `text`, inlining
    /// each command's merged, trimmed output at its injection site.
    ///
    /// - Parameters:
    ///   - text: The input text to scan -- pass 1's output, since this pass always runs second
    ///     in the body pass-set (`RenderPipeline.renderBody`).
    ///   - request: The render request this pass runs under; `skillDirectory` supplies the
    ///     working directory every command runs in, and `policy.isShellExecutionDisabled` gates
    ///     whether anything runs at all.
    /// - Returns: `text` with every recognized injection replaced by its command's output (or,
    ///   under a disabled policy, by `disabledMarker`).
    /// - Throws: Whatever `Foundation.Process.run()` throws when a command fails to launch (e.g.
    ///   `request.skillDirectory` does not exist).
    public func render(_ text: String, request: RenderRequest) throws -> String {
        var output = ""
        var lastEnd = text.startIndex
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)

        for match in Self.injectionPattern.matches(in: text, range: fullRange) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            output += text[lastEnd..<matchRange.lowerBound]
            lastEnd = matchRange.upperBound

            switch Self.classify(match, in: text) {
            case .inline(let prefix, let command):
                output += prefix
                output += try Self.resolvedOutput(forCommand: command, request: request)
            case .fenced(let command):
                output += try Self.resolvedOutput(forCommand: command, request: request)
            }
        }
        output += text[lastEnd...]

        return output
    }

    // MARK: - Injection classification

    /// One recognized injection, discriminated from an `injectionPattern` match by
    /// `classify(_:in:)`.
    private enum Injection {
        /// `` !`command` `` -- carries the whitespace/start-of-text `prefix` the match consumed
        /// (re-emitted verbatim ahead of the command's output, since only the `` !`...` `` syntax
        /// itself is replaced) alongside the captured `command` text.
        case inline(prefix: String, command: String)
        /// A fenced ` ```! ` block -- the entire fenced region (both fence lines and everything
        /// between them) is replaced by `command`'s output; there is no prefix to preserve.
        case fenced(command: String)
    }

    /// The named capture group names `injectionPattern`'s regex string and `classify(_:in:)`'s
    /// `NamedCaptureGroup.text(from:name:in:)` lookups share.
    ///
    /// Defined once here so the group names embedded in the regex pattern and the strings used
    /// to look those groups back up can never drift out of sync.
    private enum GroupName {
        static let prefix = "prefix"
        static let inlineCommand = "inlineCommand"
        static let fencedCommand = "fencedCommand"
    }

    /// Classifies one `injectionPattern` match into an `Injection` by checking which
    /// alternative's named capture group participated.
    ///
    /// - Parameters:
    ///   - match: One match produced by `injectionPattern` against `text`.
    ///   - text: The text `match` was matched against, needed to extract named-group substrings.
    /// - Returns: The injection `match` represents.
    private static func classify(_ match: NSTextCheckingResult, in text: String) -> Injection {
        if let command = NamedCaptureGroup.text(from: match, name: GroupName.inlineCommand, in: text) {
            let prefix = NamedCaptureGroup.text(from: match, name: GroupName.prefix, in: text) ?? ""
            return .inline(prefix: prefix, command: command)
        }
        if let command = NamedCaptureGroup.text(from: match, name: GroupName.fencedCommand, in: text) {
            return .fenced(command: command)
        }
        preconditionFailure("ShellInjection.injectionPattern matched but no known alternative captured.")
    }

    /// The single-pass injection grammar (plan.md §5.2).
    ///
    /// Two alternatives: inline `` !`command` `` -- whose leading `(?<prefix>^|\s)` requires the
    /// `!` to sit at the very start of the text or immediately after whitespace (a mid-word
    /// `` foo!`cmd` `` has no whitespace/start immediately before its `!`, so it never matches
    /// either alternative) -- and a fenced ` ```! ` block, anchored to its own lines via
    /// `.anchorsMatchLines` so `^`/`$` bind per line rather than only at the whole text's start
    /// and end. The fenced content capture (`[\s\S]*?`) matches across newlines without needing
    /// `.dotMatchesLineSeparators`, and its closing fence tolerates trailing horizontal
    /// whitespace before end-of-line.
    private static let injectionPattern = try! NSRegularExpression(
        pattern:
            #"(?<\#(GroupName.prefix)>^|\s)!`(?<\#(GroupName.inlineCommand)>[^`\n]+)`|^```!\n(?<\#(GroupName.fencedCommand)>[\s\S]*?)\n```[ \t]*$"#,
        options: [.anchorsMatchLines])

    // MARK: - Execution

    /// Resolves one recognized `command`'s substitution: `disabledMarker` under a disabled
    /// policy, or that command's actual merged, trimmed output.
    ///
    /// - Parameters:
    ///   - command: The shell command text captured from either injection form.
    ///   - request: The render request this pass runs under; `policy.isShellExecutionDisabled`
    ///     gates execution, and `skillDirectory` supplies the working directory when it runs.
    /// - Returns: `disabledMarker`, or `command`'s captured output.
    /// - Throws: Whatever `run(command:workingDirectory:)` throws.
    private static func resolvedOutput(forCommand command: String, request: RenderRequest) throws -> String {
        guard !request.policy.isShellExecutionDisabled else { return disabledMarker }
        return try run(command: command, workingDirectory: request.skillDirectory)
    }

    /// Runs `command` via `/bin/sh -c` with `workingDirectory` as its current directory and the
    /// host process's environment fully inherited, capturing merged stdout+stderr.
    ///
    /// - Parameters:
    ///   - command: The command string passed to `sh -c`.
    ///   - workingDirectory: The child process's working directory -- the skill's own directory,
    ///     matching plan.md decision #28's cwd discipline for the sibling §7.3.1 script path.
    /// - Returns: The command's merged stdout+stderr, decoded as UTF-8 with trailing newlines
    ///   trimmed.
    /// - Throws: Whatever `Foundation.Process.run()` throws (e.g. `workingDirectory` does not
    ///   exist).
    private static func run(command: String, workingDirectory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = workingDirectory

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return trimmingTrailingNewlines(String(decoding: data, as: UTF8.self))
    }

    /// Strips every trailing `"\n"` from `text`, mirroring POSIX `$(...)` command-substitution
    /// semantics.
    ///
    /// - Parameter text: The text to trim.
    /// - Returns: `text` with every trailing newline removed; unchanged when `text` has none.
    private static func trimmingTrailingNewlines(_ text: String) -> String {
        var trimmed = Substring(text)
        while trimmed.hasSuffix("\n") {
            trimmed.removeLast()
        }
        return String(trimmed)
    }
}
