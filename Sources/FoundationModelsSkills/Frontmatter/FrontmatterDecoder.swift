import Foundation
import Yams

/// The result of successfully decoding one skill's raw text: the decoded
/// frontmatter, its render-pipeline body (the text after the frontmatter
/// fence, byte-for-byte as the Extras document stack gives it -- plan.md §5),
/// and any diagnostic-worthy notes accumulated along the way. Notes combine
/// `SkillFrontmatter.notes` (mistyped `metadata.*` values and
/// top-level/`metadata.*` conflicts) with `FrontmatterDecoder`'s own
/// quoting-fallback-retry note, when one fired.
///
/// Consumed by the downstream `SkillsRegistry` validator, which layers
/// agentskills.io + Claude semantics (required `description`, `name ==
/// directoryName`, shadowing, etc.) on top and surfaces every note as an
/// `.advisory` diagnostic -- this type carries no such judgment itself.
public struct DecodedSkill: Sendable, Equatable {
    /// The decoded frontmatter fields.
    public var frontmatter: SkillFrontmatter
    /// The render-pipeline body: everything after the closing frontmatter
    /// fence (or the whole text, when there was no frontmatter block at
    /// all).
    public var body: String
    /// Diagnostic-worthy notes accumulated while decoding.
    public var notes: [String]

    /// Creates a decoded skill from its already-decoded frontmatter, its
    /// render-pipeline body, and any diagnostic-worthy notes accumulated
    /// while decoding.
    ///
    /// - Parameters:
    ///   - frontmatter: The decoded frontmatter fields.
    ///   - body: The render-pipeline body -- everything after the closing
    ///     frontmatter fence (or the whole text, when there was no
    ///     frontmatter block).
    ///   - notes: Diagnostic-worthy notes, combining `SkillFrontmatter`'s own
    ///     mistyped-`metadata.*` and top-level/`metadata.*` conflict notes
    ///     with `FrontmatterDecoder`'s quoting-fallback-retry note, when one
    ///     fired.
    public init(frontmatter: SkillFrontmatter, body: String, notes: [String]) {
        self.frontmatter = frontmatter
        self.body = body
        self.notes = notes
    }
}

/// Decodes the frontmatter text of one skill into `SkillFrontmatter`.
///
/// The split of a document into its frontmatter and its body is the work of
/// `FoundationModelsExtras`, which `SkillsRegistry` gets from the layer
/// stack. This decoder gets the raw text between the fences only, and the
/// Yams decode on top of it is the schema work of this package (plan.md §4,
/// decision #27/#29).
///
/// **Never throws.** A Yams parse failure runs the quoting-fallback retry for
/// the common cross-client authoring mistake -- an unquoted colon inside
/// `description:`, which a strict YAML parser reads as a nested mapping
/// (plan.md §4). If the retry succeeds, the result is `.decoded` with a note
/// recording that a retry happened; if the retry cannot even be attempted (no
/// `description:` line to requote, or it is already quoted) or still fails
/// after being attempted, the result is `.skipped(reason:)` -- a value, never
/// a thrown error, matching the spec's client-implementation guide's lenient
/// posture.
public enum FrontmatterDecoder {
    /// The outcome of decoding one skill's raw text.
    public enum Outcome: Sendable, Equatable {
        /// Frontmatter decoded -- on the first attempt, or after a
        /// quoting-fallback retry (in which case `DecodedSkill.notes`
        /// records that).
        case decoded(DecodedSkill)
        /// The frontmatter block was present but could not be parsed as
        /// YAML, even after the quoting-fallback retry. `reason` is
        /// diagnostic text, not a thrown error.
        case skipped(reason: String)

        /// Joins the two halves of one document again: the outcome of the
        /// frontmatter decode, and the body the split gave beside it.
        ///
        /// - Parameters:
        ///   - metadata: What `decode(frontmatter:)` gave for the frontmatter
        ///     of this document, or `nil` when the document holds no
        ///     frontmatter block at all.
        ///   - body: The render-pipeline body: the text after the closing
        ///     fence, or the whole text when there is no frontmatter block.
        public init(metadata: MetadataOutcome?, body: String) {
            guard let metadata else {
                self = .decoded(DecodedSkill(frontmatter: SkillFrontmatter(), body: body, notes: []))
                return
            }
            switch metadata {
            case .decoded(let frontmatter, let notes):
                self = .decoded(DecodedSkill(frontmatter: frontmatter, body: body, notes: notes))
            case .skipped(let reason):
                self = .skipped(reason: reason)
            }
        }
    }

    /// The half of the outcome that has no body: what one decode of a
    /// frontmatter block gives.
    ///
    /// The decode seam of `FrontmatterDocumentStack` is
    /// `(String) -> Metadata?`, and it gets the frontmatter text only. Thus
    /// this type is the `Metadata` of that stack, and `Outcome` joins it with
    /// the body again. A failure is a value here, never `nil`, so that its
    /// message survives the trip through the stack.
    public enum MetadataOutcome: Sendable, Equatable {
        /// The frontmatter decoded -- on the first attempt, or after a
        /// quoting-fallback retry, which `notes` then records.
        case decoded(frontmatter: SkillFrontmatter, notes: [String])
        /// The frontmatter block was present but could not be parsed as
        /// YAML, even after the quoting-fallback retry. `reason` is
        /// diagnostic text, not a thrown error.
        case skipped(reason: String)
    }

    /// The literal top-level key line prefix the quoting-fallback retry
    /// looks for -- matches only an unindented `description:` line, since
    /// every fixture and the spec both keep `description` at the mapping's
    /// top level.
    private static let descriptionLinePrefix = "description:"

    /// The note the decoder records when the quoting-fallback retry fired
    /// and then decoded.
    private static let quotingFallbackNote =
        "frontmatter YAML required a quoting-fallback retry: quoted the unquoted-colon "
        + "'description:' value."

    /// The reason a frontmatter block that no retry can repair gives.
    private static let unparseableReason = "unparseable YAML frontmatter"

    /// The reason a frontmatter block that the retry fired on, and that still
    /// did not decode, gives.
    private static let unparseableAfterRetryReason =
        "unparseable YAML frontmatter, even after quoting-fallback retry on 'description:'"

    /// Yams-decodes one frontmatter block into `SkillFrontmatter`, retrying
    /// once with the quoting fallback on a parse failure.
    ///
    /// - Parameter frontmatterText: The raw text between the `---` fences, as
    ///   the Extras split gives it.
    /// - Returns: `.decoded` with the frontmatter and its notes, or
    ///   `.skipped` with a diagnostic reason. An empty block, or one of
    ///   whitespace only, decodes to `SkillFrontmatter`'s all-nil/empty
    ///   defaults, never `.skipped` -- required-field enforcement (e.g. a
    ///   missing `description`) is the validator's job, not this decoder's.
    public static func decode(frontmatter frontmatterText: String) -> MetadataOutcome {
        guard !frontmatterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .decoded(frontmatter: SkillFrontmatter(), notes: [])
        }

        if let frontmatter = Self.tryDecode(frontmatterText) {
            return .decoded(frontmatter: frontmatter, notes: frontmatter.notes)
        }

        guard let retriedText = Self.quotingFallback(frontmatterText) else {
            return .skipped(reason: Self.unparseableReason)
        }

        guard let frontmatter = Self.tryDecode(retriedText) else {
            return .skipped(reason: Self.unparseableAfterRetryReason)
        }

        return .decoded(frontmatter: frontmatter, notes: frontmatter.notes + [Self.quotingFallbackNote])
    }

    /// Attempts a single Yams decode of `frontmatterText`, swallowing any
    /// error -- the caller decides what to do next (retry, or skip).
    private static func tryDecode(_ frontmatterText: String) -> SkillFrontmatter? {
        try? YAMLDecoder().decode(SkillFrontmatter.self, from: frontmatterText)
    }

    /// Quotes an unquoted-colon `description:` value -- the common
    /// cross-client authoring mistake plan.md §4 calls out (a description
    /// like `Deploy to staging: verify...` reads as a nested YAML mapping to
    /// a strict parser without quoting). Operates textually, line by line,
    /// so it never depends on Yams having already told it *why* parsing
    /// failed.
    ///
    /// **Known limitation:** this only requotes the single physical line
    /// beginning with `description:`. A `description:` authored as a
    /// multi-line YAML plain/folded scalar (a legitimate way to author a
    /// long description, with continuation lines indented under the key)
    /// only has its first line quoted; the retried decode then fails safely
    /// (the continuation lines are no longer valid after a completed quoted
    /// scalar), landing on `.skipped` rather than fixing the value. In
    /// scope: the required fixture's single-line case
    /// (`broken/bad-colon-description/SKILL.md`); multi-line folded
    /// descriptions are a follow-up if they show up in practice.
    ///
    /// - Parameter frontmatterText: The raw frontmatter text (between the
    ///   `---` fences) that failed to decode.
    /// - Returns: The retried text with its `description:` value quoted (and
    ///   any pre-existing backslash/quote characters escaped), or `nil` if
    ///   there is no top-level `description:` line, or its value is already
    ///   quoted -- nothing this retry can change, so the caller should skip
    ///   immediately rather than re-attempt an identical decode.
    private static func quotingFallback(_ frontmatterText: String) -> String? {
        var lines = frontmatterText.components(separatedBy: "\n")

        for index in lines.indices {
            let line = lines[index]
            let hasTrailingCarriageReturn = line.hasSuffix("\r")
            let content = hasTrailingCarriageReturn ? String(line.dropLast()) : line
            guard content.hasPrefix(Self.descriptionLinePrefix) else { continue }

            let rawValue = content.dropFirst(Self.descriptionLinePrefix.count)
                .trimmingCharacters(in: .whitespaces)
            guard !rawValue.isEmpty, !Self.isAlreadyQuoted(rawValue) else { return nil }

            let escaped =
                rawValue
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let quotedLine = "\(Self.descriptionLinePrefix) \"\(escaped)\""
            lines[index] = hasTrailingCarriageReturn ? quotedLine + "\r" : quotedLine
            return lines.joined(separator: "\n")
        }

        // No top-level `description:` line found -- nothing to retry.
        return nil
    }

    /// Whether `value` is already fully wrapped in matching quotes (single
    /// or double) -- if so, the quoting-fallback retry has nothing to add.
    private static func isAlreadyQuoted(_ value: String) -> Bool {
        (value.count >= 2 && value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.count >= 2 && value.hasPrefix("'") && value.hasSuffix("'"))
    }
}
