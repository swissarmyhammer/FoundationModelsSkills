import Foundation
import FoundationModelsExtras
import Yams

/// The result of successfully decoding one skill's raw text: the decoded
/// frontmatter, its render-pipeline body (the text after the frontmatter
/// fence, byte-for-byte from `FrontmatterDocument.split` -- plan.md §5), and
/// any diagnostic-worthy notes accumulated along the way. Notes combine
/// `SkillFrontmatter.notes` (top-level/`metadata.*` conflicts) with
/// `FrontmatterDecoder`'s own quoting-fallback-retry note, when one fired.
///
/// Consumed by the downstream `SkillsRegistry` validator, which layers
/// agentskills.io + Claude semantics (required `description`, `name ==
/// directoryName`, shadowing, etc.) on top -- this type carries no such
/// judgment itself.
public struct DecodedSkill: Sendable, Equatable {
    /// The decoded frontmatter fields.
    public var frontmatter: SkillFrontmatter
    /// The render-pipeline body: everything after the closing frontmatter
    /// fence (or the whole text, when there was no frontmatter block at
    /// all).
    public var body: String
    /// Diagnostic-worthy notes accumulated while decoding.
    public var notes: [String]

    public init(frontmatter: SkillFrontmatter, body: String, notes: [String]) {
        self.frontmatter = frontmatter
        self.body = body
        self.notes = notes
    }
}

/// Decodes a skill's raw `SKILL.md`-style text into `SkillFrontmatter` --
/// `FrontmatterDocument.split` does the textual frontmatter/body split
/// (`FoundationModelsExtras`); the Yams decode on top is this package's own
/// (plan.md §4, decision #27/#29).
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
    }

    /// The literal top-level key line prefix the quoting-fallback retry
    /// looks for -- matches only an unindented `description:` line, since
    /// every fixture and the spec both keep `description` at the mapping's
    /// top level.
    private static let descriptionLinePrefix = "description:"

    /// Splits `text` via `FrontmatterDocument.split` and Yams-decodes the
    /// frontmatter block into `SkillFrontmatter`, retrying once with the
    /// quoting fallback on a parse failure.
    ///
    /// - Parameter text: The raw `SKILL.md`-style document text (frontmatter
    ///   fence + body).
    /// - Returns: `.decoded` with the frontmatter, body, and notes, or
    ///   `.skipped` with a diagnostic reason. Text with no frontmatter block
    ///   at all (per `FrontmatterDocument.split`) decodes to
    ///   `SkillFrontmatter`'s all-nil/empty defaults, never `.skipped` --
    ///   required-field enforcement (e.g. a missing `description`) is the
    ///   validator's job, not this decoder's.
    public static func decode(text: String) -> Outcome {
        let (frontmatterText, body) = FrontmatterDocument.split(text: text)
        guard let frontmatterText,
            !frontmatterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .decoded(DecodedSkill(frontmatter: SkillFrontmatter(), body: body, notes: []))
        }

        if let frontmatter = Self.tryDecode(frontmatterText) {
            return .decoded(DecodedSkill(frontmatter: frontmatter, body: body, notes: frontmatter.notes))
        }

        guard let retriedText = Self.quotingFallback(frontmatterText) else {
            return .skipped(reason: "unparseable YAML frontmatter")
        }

        guard let frontmatter = Self.tryDecode(retriedText) else {
            return .skipped(
                reason: "unparseable YAML frontmatter, even after quoting-fallback retry on 'description:'"
            )
        }

        var notes = frontmatter.notes
        notes.append(
            "frontmatter YAML required a quoting-fallback retry: quoted the unquoted-colon "
                + "'description:' value.")
        return .decoded(DecodedSkill(frontmatter: frontmatter, body: body, notes: notes))
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
