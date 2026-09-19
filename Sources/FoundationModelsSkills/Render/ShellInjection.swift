import Foundation
import FoundationModelsExtras

/// Pass 2 of the §5 render pipeline: shell-command injection, body renders only.
///
/// Recognizes two forms, both single-shot over the *original* input text (never re-scanning
/// substituted output, honoring the same no-re-scan contract that `RenderPass` documents and
/// `ArgumentSubstitution` keeps): inline `` !`command` ``, matched only when the `!` sits at the
/// very start of the flattened text or immediately after a whitespace character (a mid-word
/// `` foo!`cmd` `` never matches, so it is left untouched, verbatim); and fenced ` ```! ` blocks,
/// whose entire fenced region -- opening fence line through closing fence line -- is replaced by
/// its contents' execution. Both anchors read the *flattened* text, not the span: a `$1` splice
/// directly before a `!` or a fence never turns a mid-word site into a text-start one, because
/// each `.original` span is scanned together with the character that precedes it (see
/// `injectedSpans(in:precededBy:request:)`). Every match is resolved from one left-to-right
/// scan (`Self.injectionPattern.matches(in:options:range:)`) computed once against the pass's
/// input, so a shell command's own output -- even output shaped like `$0`, another
/// `` !`command` ``, or `{{ HOME }}`, none of which this pass or an earlier one ever sees again --
/// is spliced in after matching has already finished and can never trigger a second match.
///
/// Each recognized command runs via `/bin/sh -c`, with `RenderRequest.skillDirectory` as its
/// working directory and the host process's environment fully inherited (plan.md decision #28's
/// "scrubbing... while `` !`env` `` runs unscrubbed would be theater" rationale, applied here to
/// its own §5 shell). Merged stdout+stderr is captured and inlined as plain text at the
/// injection site, with trailing newlines trimmed (matching POSIX `$(...)` command-substitution
/// semantics, the shell convention this syntax otherwise mirrors). Commands re-execute on every
/// `render(_:request:)` call -- this pass holds no cache, so "dynamic at render, static in
/// transcript" (plan.md §5) falls out of `ShellRenderPass`'s per-call contract with no extra
/// bookkeeping here.
///
/// **The limits.** `FoundationModelsExtras.ProcessRunner` starts every command, thus each one
/// runs in a process group of its own, stands in `ProcessRegistry.global` while it runs, and
/// dies with its whole group at `RenderPolicy.shellCommandTimeout`. The read of the output stops
/// at `RenderPolicy.shellOutputByteLimit`, thus a command that writes without end cannot grow the
/// memory of the host. A command that passes either limit writes no output into the body: this
/// pass writes the inert marker of that limit in its place, and the render of the rest of the
/// body goes on.
///
/// **Body only.** `RenderPipeline.renderMetadata` never includes this pass in its pass-set
/// (`description`/`metadata.*` values render at metadata-build/reload/list time, where shell
/// execution would fire on every watcher event rather than once per call) -- enforced entirely
/// by pipeline composition, since `RenderRequest` carries no body-vs-metadata flag for this pass
/// to check itself.
///
/// **macOS only** (plan.md §8) -- this package's platform floor already excludes iOS at the
/// manifest level, so no `#if os(macOS)` guard is needed in this file itself.
public struct ShellInjection: ShellRenderPass {
    /// The inert text an injection site is replaced with instead of the output of its command,
    /// naming the reason.
    ///
    /// One shape serves every reason, thus a body reads the same whichever limit or policy
    /// stopped the command, and a host that scans a rendered body reads one form.
    ///
    /// - Parameter reason: Why the site carries no output.
    /// - Returns: The marker text.
    private static func marker(reason: String) -> String {
        "[shell execution \(reason)]"
    }

    /// The inert text every injection site is replaced with instead of running anything.
    ///
    /// Substituted when `RenderPolicy.isShellExecutionDisabled` is `true`; shared by both
    /// recognized forms (inline and fenced) -- neither is treated differently under the
    /// disabled policy.
    public static let disabledMarker = marker(reason: "disabled")

    /// The inert text an injection site carries when its command passed
    /// `RenderPolicy.shellCommandTimeout` and the runner killed its whole process group.
    ///
    /// The partial output of the command never reaches the body, and the render of the rest of
    /// the body goes on.
    public static let timedOutMarker = marker(reason: "timed out")

    /// The inert text an injection site carries when its command wrote more than
    /// `RenderPolicy.shellOutputByteLimit`.
    ///
    /// The kept part of the output never reaches the body, and the render of the rest of the
    /// body goes on.
    public static let outputOverTheLimitMarker = marker(reason: "output over the limit")

    /// Creates a `ShellInjection` pass.
    ///
    /// Takes no configuration -- every instance behaves identically, driven entirely by the
    /// `RenderRequest` each `render(_:request:)` call receives.
    public init() {}

    /// Executes every recognized `` !`command` ``/fenced ` ```! ` injection in `text`, inlining
    /// each command's merged, trimmed output at its injection site.
    ///
    /// Scans only `text`'s `.original` spans -- a `.quarantined` span (pass 1's substituted
    /// argument values, e.g.) is never scanned for `` !`command` ``/fenced injection, satisfying
    /// plan.md §5's no-re-scan contract: a model-supplied argument containing `` !`echo pwned` ``
    /// is inserted as inert text, never executed. Each command's own output becomes its own
    /// `.quarantined` span in turn, so a later pass (Stencil) never re-scans it either.
    ///
    /// - Parameters:
    ///   - text: The input text to scan -- pass 1's output, since this pass always runs second
    ///     in the body pass-set (`RenderPipeline.renderBody`).
    ///   - request: The render request this pass runs under; `skillDirectory` supplies the
    ///     working directory every command runs in, and `policy.isShellExecutionDisabled` gates
    ///     whether anything runs at all.
    /// - Returns: `text` with every recognized injection (found within an `.original` span)
    ///   replaced by its command's output (or, under a disabled policy or a limit the command
    ///   passed, by the matching marker), quarantined.
    /// - Throws: `ProcessRunner.Failure` when a command never reached exec -- for example when
    ///   `request.skillDirectory` does not exist.
    public func render(_ text: QuarantinedText, request: RenderRequest) async throws -> QuarantinedText {
        try await text.mappingOriginalSpans(awaiting: { spanText, precedingCharacter in
            try await Self.injectedSpans(in: spanText, precededBy: precedingCharacter, request: request)
        })
    }

    /// Scans one `.original` span's `text` left to right for every recognized injection,
    /// building the span list that replaces it.
    ///
    /// The scan runs over `precedingCharacter` + `text`, with the match range restricted to
    /// `text` itself: the carried character is visible to the grammar's lookbehind and
    /// start-of-line anchor (`.withTransparentBounds`, plus `.withoutAnchoringBounds` so `^` does
    /// not simply bind to the range's own start) but is never part of a match, never re-emitted,
    /// and never scanned for an injection of its own. That is how the grammar reads the flattened
    /// text's `abc$1!`cmd`` as mid-word -- the `c` that ends the argument value precedes the `!`
    /// -- while still reading a `$1` value that ends in whitespace, or a newline before a fence,
    /// as the anchor it is.
    ///
    /// - Parameters:
    ///   - text: One `.original` span's text to scan.
    ///   - precedingCharacter: The character immediately before `text` in the flattened text,
    ///     or `nil` when `text` starts the flattened text.
    ///   - request: The render request this pass runs under.
    /// - Returns: The spans that replace `text`: literal runs as `.original`, every command's
    ///   output (or the marker that stands in its place) as its own `.quarantined` span.
    /// - Throws: Whatever `resolvedOutput(forCommand:request:)` throws.
    private static func injectedSpans(
        in text: String, precededBy precedingCharacter: Character?, request: RenderRequest
    ) async throws -> [QuarantinedText.Span] {
        let scanned = precedingCharacter.map { String($0) + text } ?? text
        let contentStart = precedingCharacter == nil ? scanned.startIndex : scanned.index(after: scanned.startIndex)
        var builder = SpanBuilder()
        var lastEnd = contentStart
        let contentRange = NSRange(contentStart..<scanned.endIndex, in: scanned)

        for match in Self.injectionPattern.matches(in: scanned, options: Self.spanScanOptions, range: contentRange) {
            guard let matchRange = Range(match.range, in: scanned) else { continue }
            builder.appendOriginal(scanned[lastEnd..<matchRange.lowerBound])
            lastEnd = matchRange.upperBound
            let command = Self.command(from: match, in: scanned)
            builder.appendQuarantined(try await Self.resolvedOutput(forCommand: command, request: request))
        }
        builder.appendOriginal(scanned[lastEnd...])
        return builder.finish()
    }

    // MARK: - Injection classification

    /// The named capture group names `injectionPattern`'s regex string and `command(from:in:)`'s
    /// `NamedCaptureGroup.text(from:name:in:)` lookups share.
    ///
    /// Defined once here so the group names embedded in the regex pattern and the strings used
    /// to look those groups back up can never drift out of sync.
    private enum GroupName {
        static let inlineCommand = "inlineCommand"
        static let fencedCommand = "fencedCommand"
    }

    /// Extracts the command text from one `injectionPattern` match, whichever alternative's
    /// named capture group participated.
    ///
    /// Both alternatives replace their entire match with the command's output -- the inline
    /// form's anchor is a zero-width lookbehind, so no prefix text is ever consumed -- which is
    /// why the two need no further discrimination here.
    ///
    /// - Parameters:
    ///   - match: One match produced by `injectionPattern` against `text`.
    ///   - text: The text `match` was matched against, needed to extract named-group substrings.
    /// - Returns: The command text `match` captured.
    private static func command(from match: NSTextCheckingResult, in text: String) -> String {
        for groupName in [GroupName.inlineCommand, GroupName.fencedCommand] {
            if let command = NamedCaptureGroup.text(from: match, name: groupName, in: text) {
                return command
            }
        }
        preconditionFailure("ShellInjection.injectionPattern matched but no known alternative captured.")
    }

    /// The single-pass injection grammar (plan.md §5.2).
    ///
    /// Two alternatives: inline `` !`command` `` -- whose leading `(?<![^\s])` lookbehind
    /// requires that no non-whitespace character precede the `!`, i.e. that it sit at the very
    /// start of the flattened text or immediately after whitespace (a mid-word `` foo!`cmd` `` has
    /// a letter immediately before its `!`, so it never matches either alternative) -- and a
    /// fenced ` ```! ` block, anchored to its own lines via `.anchorsMatchLines` so `^`/`$` bind
    /// per line rather than only at the whole text's start and end. The fenced content capture
    /// (`[\s\S]*?`) matches across newlines without needing `.dotMatchesLineSeparators`, and its
    /// closing fence tolerates trailing horizontal whitespace before end-of-line.
    private static let injectionPattern = try! NSRegularExpression(
        pattern:
            #"(?<![^\s])!`(?<\#(GroupName.inlineCommand)>[^`\n]+)`|^```!\n(?<\#(GroupName.fencedCommand)>[\s\S]*?)\n```[ \t]*$"#,
        options: [.anchorsMatchLines])

    /// The matching options `injectedSpans(in:precededBy:request:)` scans each span under.
    ///
    /// `.withTransparentBounds` lets the inline form's lookbehind see the carried preceding
    /// character outside the match range; `.withoutAnchoringBounds` stops `^` from matching at
    /// the range's own start, so the fenced form's line anchor binds only at the flattened text's
    /// true start or after a real newline -- one the carried character may itself supply.
    private static let spanScanOptions: NSRegularExpression.MatchingOptions = [
        .withTransparentBounds, .withoutAnchoringBounds,
    ]

    // MARK: - Execution

    /// Resolves one recognized `command`'s substitution: `disabledMarker` under a disabled
    /// policy, the marker of the limit the command passed, or that command's actual merged,
    /// trimmed output.
    ///
    /// - Parameters:
    ///   - command: The shell command text captured from either injection form.
    ///   - request: The render request this pass runs under; `policy.isShellExecutionDisabled`
    ///     gates execution, the two limits of the policy bound the run, and `skillDirectory`
    ///     supplies the working directory when it runs.
    /// - Returns: `disabledMarker`, `timedOutMarker`, `outputOverTheLimitMarker`, or `command`'s
    ///   captured output.
    /// - Throws: Whatever `run(command:workingDirectory:policy:)` throws.
    private static func resolvedOutput(forCommand command: String, request: RenderRequest) async throws -> String {
        guard !request.policy.isShellExecutionDisabled else { return disabledMarker }
        return try await run(
            command: command, workingDirectory: request.skillDirectory, policy: request.policy)
    }

    /// The shell every recognized command runs under.
    private static let shellURL = URL(fileURLWithPath: "/bin/sh")

    /// The option that tells the shell to read its command from the argument that follows.
    private static let shellCommandOption = "-c"

    /// The count of lines the pass keeps of one command's output.
    ///
    /// The byte limit of the policy is the true bound of the memory, and the pass inlines the
    /// whole output rather than a tail of it, thus the count of lines holds back nothing.
    private static let outputLineCap = Int.max

    /// Runs `command` via `/bin/sh -c` with `workingDirectory` as its current directory and the
    /// host process's environment fully inherited, capturing merged stdout+stderr.
    ///
    /// `ProcessRunner` of `FoundationModelsExtras` starts the shell directly, thus the shell and
    /// each process it starts share one process group, the pid stands in `ProcessRegistry.global`
    /// while the command runs, and the group dies with `SIGKILL` at the timeout. The exit code
    /// of the command decides nothing: a command that failed inlines whatever it wrote, exactly
    /// as `$(...)` of a shell does.
    ///
    /// - Parameters:
    ///   - command: The command string passed to `sh -c`.
    ///   - workingDirectory: The child process's working directory -- the skill's own directory,
    ///     matching plan.md decision #28's cwd discipline for the sibling §7.3.1 script path.
    ///   - policy: The policy of the render, which carries the timeout and the byte limit.
    /// - Returns: The command's merged stdout+stderr, decoded as UTF-8 with trailing newlines
    ///   trimmed, or the marker of the limit the command passed.
    /// - Throws: `ProcessRunner.Failure` when the shell never reached exec -- for example when
    ///   `workingDirectory` does not exist.
    private static func run(command: String, workingDirectory: URL, policy: RenderPolicy) async throws -> String {
        let outcome = try await ProcessRunner.run(
            executable: shellURL,
            arguments: [shellCommandOption, command],
            workingDirectory: workingDirectory,
            timeout: policy.shellCommandTimeout,
            outputCap: ProcessRunner.OutputCap(
                lineCount: outputLineCap, byteLimit: policy.shellOutputByteLimit))

        guard outcome.termination != .timedOut else { return timedOutMarker }
        guard !outcome.isTruncated else { return outputOverTheLimitMarker }
        return trimmingTrailingNewlines(outcome.output.joined(separator: "\n"))
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
