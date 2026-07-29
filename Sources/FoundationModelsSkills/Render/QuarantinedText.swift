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

    /// Wraps `spans` directly.
    ///
    /// - Parameter spans: The spans to wrap, in order.
    public init(spans: [Span]) {
        self.spans = spans
    }

    /// Wraps `text` as a single `.original` span -- the render pipeline's
    /// starting point, before any pass has run.
    ///
    /// - Parameter text: The render request's source text.
    public init(original text: String) {
        spans = text.isEmpty ? [] : [.original(text)]
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
        try QuarantinedText(
            spans: spans.flatMap { span -> [Span] in
                switch span {
                case .original(let text): return try transform(text)
                case .quarantined: return [span]
                }
            })
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
    /// - Parameter value: The substituted value to quarantine.
    mutating func appendQuarantined(_ value: String) {
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
