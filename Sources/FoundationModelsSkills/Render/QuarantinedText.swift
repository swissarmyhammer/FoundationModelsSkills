import Foundation

/// Text broken into alternating provenance-tagged spans, enforcing plan.md
/// §5's no-re-scan contract across passes, not just within one.
///
/// A `.original` span is body/metadata source text (or an earlier pass's
/// untouched leftover) -- eligible for whichever pass runs next to scan and
/// substitute. A `.quarantined` span is text an earlier pass spliced in by
/// substitution -- copied through verbatim by every later pass, never
/// scanned, matching plan.md §5's "each pass single-shot and not
/// re-scanned by later passes."
public struct QuarantinedText: Sendable, Equatable {
    /// One contiguous run of text, tagged with where it came from.
    public enum Span: Sendable, Equatable {
        /// Original body/metadata text, or an earlier pass's untouched
        /// leftover -- eligible for the next pass's own scan.
        case original(String)

        /// Text spliced in by an earlier pass's substitution -- copied
        /// through verbatim by every later pass, never scanned.
        case quarantined(String)

        /// This span's text, regardless of provenance.
        var text: String {
            switch self {
            case .original(let text), .quarantined(let text): return text
            }
        }
    }

    /// This text's spans, in order.
    public var spans: [Span]

    /// Wraps `spans`, normalized: every empty span is dropped, and adjacent
    /// `.original` spans are joined into one.
    ///
    /// An empty `.quarantined` span -- a `$N` past the supplied argument
    /// count, a declared name with no value, a shell command with no output
    /// -- carries no text for a later pass to protect, so keeping it would
    /// only split the `.original` text around it into two spans. That split
    /// is what let an untrusted body mint spans for free: a body of
    /// repeated `$1` with no arguments would otherwise reach pass 3 as N
    /// separate templates. Dropping the empty span here, and re-joining the
    /// `.original` text on either side, keeps a span boundary meaningful:
    /// one exists only where substituted text actually sits.
    ///
    /// - Parameter spans: The spans to wrap, in order.
    public init(spans: [Span]) {
        self.spans = Self.normalized(spans)
    }

    /// Wraps `text` as a single `.original` span -- the render pipeline's
    /// starting point, before any pass has run.
    ///
    /// - Parameter text: The render request's source text.
    public init(original text: String) {
        self.init(spans: [.original(text)])
    }

    /// Drops every empty span in `spans` and joins each run of adjacent
    /// `.original` spans into one -- `init(spans:)`'s normalization.
    ///
    /// Adjacent `.quarantined` spans stay distinct: each is one splice, and
    /// nothing downstream depends on two splices reading as one.
    ///
    /// - Parameter spans: The spans to normalize, in order.
    /// - Returns: The normalized spans.
    private static func normalized(_ spans: [Span]) -> [Span] {
        var result: [Span] = []
        for span in spans where !span.text.isEmpty {
            if case .original(let text) = span, case .original(let previous)? = result.last {
                result[result.count - 1] = .original(previous + text)
            } else {
                result.append(span)
            }
        }
        return result
    }

    /// This text's spans concatenated, discarding provenance.
    ///
    /// The render pipeline's final result, once every pass has run.
    public var flattened: String {
        spans.map(\.text).joined()
    }

    /// Runs `transform` over every `.original` span's text, replacing it
    /// with the spans `transform` returns; every `.quarantined` span passes
    /// through untouched -- `transform` never sees it.
    ///
    /// The single seam every render pass uses to honor the no-re-scan
    /// contract: a pass calls this once, supplying its own scan/substitute
    /// logic as `transform`, and never touches `spans`/the `.quarantined`
    /// case directly.
    ///
    /// - Parameter transform: Splits one `.original` span's text into the
    ///   spans that replace it -- typically a run of `.original` (untouched
    ///   leftover) and `.quarantined` (newly substituted) spans, built via
    ///   `SpanBuilder`.
    /// - Returns: A new `QuarantinedText` with every `.original` span
    ///   replaced by `transform`'s output, in the same relative order.
    /// - Throws: Whatever `transform` throws.
    public func mappingOriginalSpans(_ transform: (String) throws -> [Span]) rethrows -> QuarantinedText {
        try mappingOriginalSpans { text, _ in try transform(text) }
    }

    /// Runs `transform` over every `.original` span's text together with
    /// the character that precedes that span in the flattened text, replacing
    /// the span with the spans `transform` returns; every `.quarantined` span
    /// passes through untouched -- `transform` never sees its text.
    ///
    /// The preceding character is the last character of whatever span --
    /// `.original` or `.quarantined` -- sits immediately before this one in
    /// `spans`, or `nil` for the very first span. It exists for a grammar
    /// whose match depends on what comes *before* a match site (a
    /// start-of-line or after-whitespace anchor, as `ShellInjection`'s
    /// inline form has): scanning a span in isolation would read every span
    /// start as a text start, so a splice could turn a mid-word site into a
    /// line-start one. Handing the pass the real preceding character lets it
    /// anchor against the flattened text without ever scanning the
    /// `.quarantined` text that character came from.
    ///
    /// - Parameter transform: Splits one `.original` span's text, given the
    ///   character preceding it in the flattened text, into the spans that
    ///   replace it.
    /// - Returns: A new `QuarantinedText` with every `.original` span
    ///   replaced by `transform`'s output, in the same relative order.
    /// - Throws: Whatever `transform` throws.
    public func mappingOriginalSpans(
        _ transform: (_ text: String, _ precedingCharacter: Character?) throws -> [Span]
    ) rethrows -> QuarantinedText {
        var precedingCharacter: Character?
        var mapped: [Span] = []
        for span in spans {
            switch span {
            case .original(let text): mapped += try transform(text, precedingCharacter)
            case .quarantined: mapped.append(span)
            }
            precedingCharacter = span.text.last ?? precedingCharacter
        }
        return QuarantinedText(spans: mapped)
    }
}

/// Accumulates one `.original` span's replacement spans while scanning it
/// left to right: literal (unmatched) runs coalesce into `.original` spans,
/// and each substituted value becomes its own `.quarantined` span.
///
/// Shared by `ArgumentSubstitution` and `ShellInjection` -- the two passes
/// that splice newly substituted content into their scan -- so neither
/// repeats this literal-buffering bookkeeping as its own inline state.
struct SpanBuilder {
    private var spans: [QuarantinedText.Span] = []
    private var literal = ""

    /// Appends `text` to the pending literal run.
    ///
    /// - Parameter text: Unmatched (or escaped-verbatim) text to carry
    ///   through as `.original`.
    mutating func appendOriginal<S: StringProtocol>(_ text: S) {
        literal += text
    }

    /// Flushes any pending literal run, then appends `value` as its own
    /// `.quarantined` span.
    ///
    /// An empty `value` appends nothing and leaves the pending literal run
    /// intact, so the literal text on either side of an empty substitution
    /// stays one `.original` span -- the same rule `QuarantinedText.init(spans:)`
    /// enforces, applied here before the split is ever made.
    ///
    /// - Parameter value: The substituted value to quarantine.
    mutating func appendQuarantined(_ value: String) {
        guard !value.isEmpty else { return }
        flushLiteral()
        spans.append(.quarantined(value))
    }

    /// Flushes any pending literal run and returns the accumulated spans.
    ///
    /// - Returns: Every span appended so far, in order.
    mutating func finish() -> [QuarantinedText.Span] {
        flushLiteral()
        return spans
    }

    /// Appends the pending literal run as an `.original` span, if non-empty,
    /// and resets it.
    private mutating func flushLiteral() {
        guard !literal.isEmpty else { return }
        spans.append(.original(literal))
        literal = ""
    }
}
