import Foundation

/// One skill that passed through `SkillValidator`'s lenient rules (plan.md
/// §4, decision #27) -- the frontmatter and body as decoded, unchanged by
/// validation, plus the eligibility flags a downstream `SkillsRegistry`
/// combines with a skill's own `disable-model-invocation`/`user-invocable`
/// frontmatter (plan.md §6) to compute final surface visibility.
///
/// Produced only when the decode outcome was `.decoded` --
/// `SkillValidator.Result.skill` is `nil` for the `.skipped` case
/// (unparseable YAML), since there is no frontmatter/body to carry.
public struct ValidatedSkill: Sendable, Equatable {
    /// The canonical id -- the directory name, never the frontmatter `name`
    /// (plan.md §4), unaffected by any name irregularity a diagnostic may
    /// report.
    public var id: String
    /// The decoded frontmatter, unchanged by validation.
    public var frontmatter: SkillFrontmatter
    /// The render-pipeline body, unchanged by validation.
    public var body: String
    /// Whether this skill is eligible for the model-facing surface.
    ///
    /// `false` when `description` is missing or empty (it cannot be
    /// disclosed) or when `isHidden` is `true`.
    public var isModelVisibleEligible: Bool
    /// Whether this skill is eligible for the user `/` menu surface.
    ///
    /// `false` only when `isHidden` is `true`.
    public var isUserInvocableEligible: Bool
    /// Whether this skill is hidden from every surface.
    ///
    /// `true` only for the retired `partial: true` flag (decision #29).
    public var isHidden: Bool

    /// Creates a `ValidatedSkill` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - id: The canonical id -- the directory name.
    ///   - frontmatter: The decoded frontmatter, unchanged by validation.
    ///   - body: The render-pipeline body, unchanged by validation.
    ///   - isModelVisibleEligible: Whether this skill is eligible for the
    ///     model-facing surface.
    ///   - isUserInvocableEligible: Whether this skill is eligible for the
    ///     user `/` menu surface.
    ///   - isHidden: Whether this skill is hidden from every surface.
    public init(
        id: String, frontmatter: SkillFrontmatter, body: String,
        isModelVisibleEligible: Bool, isUserInvocableEligible: Bool, isHidden: Bool
    ) {
        self.id = id
        self.frontmatter = frontmatter
        self.body = body
        self.isModelVisibleEligible = isModelVisibleEligible
        self.isUserInvocableEligible = isUserInvocableEligible
        self.isHidden = isHidden
    }
}

/// Applies agentskills.io + Claude lenient domain validation to one
/// discovered skill's decode result (plan.md §4, §7.1; decision #27),
/// producing a `ValidatedSkill` plus every `SkillDiagnostic` raised along the
/// way -- parity target the `skills-ref` reference validator.
///
/// Every rule below is independent and never fatal to the skill's own load in
/// isolation, except unparseable YAML (the decoder's own `.skipped` outcome,
/// carried straight through as a `.skip` diagnostic with no `ValidatedSkill`
/// produced):
///
/// | Rule | Severity | Consequence |
/// |---|---|---|
/// | `name` irregularities (length, charset, hyphens, `!= directoryName`) | warning | load anyway |
/// | missing/empty `description` | warning | excluded from the model surface, kept user-invocable |
/// | `description` over 1024 characters | warning | kept as data |
/// | `compatibility` over 500 characters | warning | kept as data |
/// | `compatibility` present but empty | advisory | kept as data |
/// | unparseable YAML (decoder `.skipped`) | skip | not loaded at all |
/// | `partial: true` | warning | hidden from every surface |
/// | shadowed id | advisory | none |
/// | `SKILL.md` body over 500 lines | advisory | none |
/// | unknown top-level keys | advisory | none |
public enum SkillValidator {
    /// The result of validating one discovered skill's decode outcome.
    public struct Result: Sendable, Equatable {
        /// The validated skill, or `nil` when the decode outcome was
        /// `.skipped` (unparseable YAML) and there is no frontmatter/body to
        /// carry.
        public var skill: ValidatedSkill?
        /// Every diagnostic raised while validating, in rule-table order.
        public var diagnostics: [SkillDiagnostic]

        /// Creates a `Result` by directly assigning every field.
        ///
        /// - Parameters:
        ///   - skill: The validated skill, or `nil` for the `.skipped` case.
        ///   - diagnostics: Every diagnostic raised while validating.
        public init(skill: ValidatedSkill?, diagnostics: [SkillDiagnostic]) {
            self.skill = skill
            self.diagnostics = diagnostics
        }
    }

    /// Validates `discovered`'s already-decoded skill, dispatching on
    /// `outcome`.
    ///
    /// - Parameters:
    ///   - discovered: The skill's discovery record -- supplies the
    ///     canonical id and the winning-layer provenance every diagnostic
    ///     carries.
    ///   - outcome: `FrontmatterDecoder.decode(text:)`'s result for this
    ///     skill's `SKILL.md`.
    /// - Returns: The validated skill (`nil` for `.skipped`) plus every
    ///   diagnostic raised.
    public static func validate(
        discovered: DiscoveredSkill, outcome: FrontmatterDecoder.Outcome
    ) -> Result {
        let provenance = SkillDiagnostic.Provenance(discovered: discovered)
        switch outcome {
        case .skipped(let reason):
            let diagnostic = SkillDiagnostic(
                severity: .skip, skillID: discovered.id, provenance: provenance,
                message: "SKILL.md frontmatter did not decode: \(reason)")
            return Result(skill: nil, diagnostics: [diagnostic])
        case .decoded(let decodedSkill):
            return validateDecoded(
                id: discovered.id, shadowedCandidates: discovered.shadowedCandidates,
                decodedSkill: decodedSkill, provenance: provenance)
        }
    }

    /// Convenience over `validate(discovered:outcome:)` for a caller that
    /// still has a skill's raw `SKILL.md` text rather than an already-decoded
    /// outcome -- decodes via `FrontmatterDecoder.decode(text:)` first.
    ///
    /// - Parameters:
    ///   - discovered: The skill's discovery record.
    ///   - text: The raw `SKILL.md`-style document text.
    /// - Returns: The validated skill (`nil` for unparseable YAML) plus every
    ///   diagnostic raised.
    public static func validate(discovered: DiscoveredSkill, text: String) -> Result {
        validate(discovered: discovered, outcome: FrontmatterDecoder.decode(text: text))
    }

    // MARK: - Rule table

    /// One rule's context: everything a `Rule.evaluate` closure needs, drawn
    /// from `discovered` and the decoded skill and bundled once per
    /// validation call, rather than threaded as separate parameters through
    /// every rule.
    private struct RuleContext: Sendable {
        let id: String
        let frontmatter: SkillFrontmatter
        let body: String
        let shadowedCandidateCount: Int
        let provenance: SkillDiagnostic.Provenance
    }

    /// What a rule's diagnostic does to a skill's eligibility, beyond simply
    /// being reported.
    ///
    /// `none` covers advisory-only findings and rules whose skill just loads
    /// with the irregularity noted as data.
    private enum Consequence {
        /// No effect beyond the diagnostic itself.
        case none
        /// Excludes the skill from the model-facing surface.
        case excludeFromModelSurface
        /// Hides the skill from every surface.
        case hide
    }

    /// One independent lenient-validation rule -- a row of this type's own
    /// table doc comment.
    ///
    /// `evaluate` returns at most one diagnostic per skill; `consequence` is
    /// fixed per rule, not derived from the diagnostic's content.
    private struct Rule: Sendable {
        let evaluate: @Sendable (RuleContext) -> SkillDiagnostic?
        let consequence: Consequence
    }

    /// The full rule table `validateDecoded` iterates, in the order this
    /// type's own table doc comment lists them.
    private static let rules: [Rule] = [
        Rule(evaluate: nameIrregularityDiagnostic, consequence: .none),
        Rule(evaluate: missingDescriptionDiagnostic, consequence: .excludeFromModelSurface),
        Rule(evaluate: descriptionOverLimitDiagnostic, consequence: .none),
        Rule(evaluate: compatibilityOverLimitDiagnostic, consequence: .none),
        Rule(evaluate: emptyCompatibilityDiagnostic, consequence: .none),
        Rule(evaluate: partialFlagDiagnostic, consequence: .hide),
        Rule(evaluate: shadowedIDDiagnostic, consequence: .none),
        Rule(evaluate: bodyLineCountDiagnostic, consequence: .none),
        Rule(evaluate: unknownTopLevelKeysDiagnostic, consequence: .none),
    ]

    /// Runs every `rules` entry over one decoded skill, folding each raised
    /// diagnostic's `consequence` into the resulting `ValidatedSkill`'s
    /// eligibility flags.
    ///
    /// - Parameters:
    ///   - id: The canonical id (directory name).
    ///   - shadowedCandidates: `discovered.shadowedCandidates`, for the
    ///     shadowed-id rule.
    ///   - decodedSkill: The successfully decoded frontmatter + body.
    ///   - provenance: The winning-layer provenance every diagnostic carries.
    /// - Returns: The validated skill plus every diagnostic raised.
    private static func validateDecoded(
        id: String, shadowedCandidates: [DiscoveredSkill.ShadowedCandidate],
        decodedSkill: DecodedSkill, provenance: SkillDiagnostic.Provenance
    ) -> Result {
        let context = RuleContext(
            id: id, frontmatter: decodedSkill.frontmatter, body: decodedSkill.body,
            shadowedCandidateCount: shadowedCandidates.count, provenance: provenance)

        var diagnostics: [SkillDiagnostic] = []
        var isModelVisibleEligible = true
        var isHidden = false
        for rule in rules {
            guard let diagnostic = rule.evaluate(context) else { continue }
            diagnostics.append(diagnostic)
            switch rule.consequence {
            case .none: break
            case .excludeFromModelSurface: isModelVisibleEligible = false
            case .hide: isHidden = true
            }
        }

        let skill = ValidatedSkill(
            id: id, frontmatter: decodedSkill.frontmatter, body: decodedSkill.body,
            isModelVisibleEligible: isHidden ? false : isModelVisibleEligible,
            isUserInvocableEligible: !isHidden, isHidden: isHidden)
        return Result(skill: skill, diagnostics: diagnostics)
    }

    // MARK: - name: rules

    /// One independent character-class/length/equality check applied to a
    /// present frontmatter `name:` (plan.md §4) -- data-driven so adding or
    /// adjusting a check never grows a parallel `if` branch.
    private struct NameCheck: Sendable {
        /// Whether `name` (compared against `directoryID` where relevant)
        /// violates this check.
        let violates: @Sendable (_ name: String, _ directoryID: String) -> Bool
        /// The diagnostic text fragment reported when `violates` is `true`.
        let description: String
    }

    /// Whether `scalar` is one of `name:`'s allowed characters: a lowercase
    /// letter, a digit, or a hyphen.
    ///
    /// - Parameter scalar: The Unicode scalar to test.
    /// - Returns: `true` if `scalar` is allowed in a `name:` value.
    private static func isValidNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
    }

    /// agentskills.io's `name:` rules (plan.md §4): 1-64 characters,
    /// `[a-z0-9-]` only, no leading/trailing hyphen, no consecutive `--`,
    /// and `name == directoryName`.
    private static let nameChecks: [NameCheck] = [
        NameCheck(
            violates: { name, _ in name.isEmpty || name.count > 64 },
            description: "must be 1-64 characters"),
        NameCheck(
            violates: { name, _ in name.unicodeScalars.contains { !isValidNameScalar($0) } },
            description: "must contain only lowercase letters, digits, and hyphens"),
        NameCheck(
            violates: { name, _ in name.hasPrefix("-") || name.hasSuffix("-") },
            description: "must not start or end with a hyphen"),
        NameCheck(
            violates: { name, _ in name.contains("--") },
            description: "must not contain consecutive hyphens"),
        NameCheck(
            violates: { name, directoryID in name != directoryID },
            description: "must equal its directory name"),
    ]

    /// Rule: a present frontmatter `name:` that violates any `nameChecks`
    /// rule draws one combined `.warning` diagnostic -- the skill still
    /// loads under the directory-name id regardless (plan.md §4).
    ///
    /// An absent `name:` (Claude-style inputs, plan.md §4) draws no
    /// diagnostic at all.
    ///
    /// - Parameter context: The rule context.
    /// - Returns: A diagnostic combining every violated check, or `nil` when
    ///   `name:` is absent or violates nothing.
    private static func nameIrregularityDiagnostic(_ context: RuleContext) -> SkillDiagnostic? {
        guard let name = context.frontmatter.name else { return nil }
        let violations = nameChecks.filter { $0.violates(name, context.id) }.map(\.description)
        guard !violations.isEmpty else { return nil }
        return SkillDiagnostic(
            severity: .warning, skillID: context.id, provenance: context.provenance,
            message: "frontmatter name '\(name)' \(violations.joined(separator: "; ")); "
                + "loaded under directory id '\(context.id)' anyway.")
    }

    // MARK: - description: / compatibility: character limits

    /// The spec's `description:` character limit (plan.md §4).
    private static let descriptionCharacterLimit = 1024
    /// The spec's `compatibility:` character limit (plan.md §4).
    private static let compatibilityCharacterLimit = 500

    /// Diagnoses a frontmatter string field exceeding a spec character limit
    /// -- shared by the `description` and `compatibility` over-limit checks
    /// so the two rules aren't near-duplicate blocks differing only by field
    /// name and limit.
    ///
    /// - Parameters:
    ///   - fieldName: The frontmatter field's name, for the message.
    ///   - value: The field's current value; `nil` or empty is a different
    ///     rule's concern and is skipped here.
    ///   - limit: The spec's maximum character count for this field.
    ///   - context: The rule context.
    /// - Returns: A `.warning` diagnostic when `value` exceeds `limit`, else
    ///   `nil`.
    private static func overLimitDiagnostic(
        fieldName: String, value: String?, limit: Int, context: RuleContext
    ) -> SkillDiagnostic? {
        guard let value, !value.isEmpty, value.count > limit else { return nil }
        return SkillDiagnostic(
            severity: .warning, skillID: context.id, provenance: context.provenance,
            message: "\(fieldName) is \(value.count) characters, exceeding the spec's \(limit)-character "
                + "limit; kept as data.")
    }

    /// Rule: `description:` over `descriptionCharacterLimit` characters draws
    /// a `.warning` diagnostic; the value is kept as data.
    ///
    /// - Parameter context: The rule context.
    /// - Returns: A diagnostic when over the limit, else `nil`.
    private static func descriptionOverLimitDiagnostic(_ context: RuleContext) -> SkillDiagnostic? {
        overLimitDiagnostic(
            fieldName: "description", value: context.frontmatter.description,
            limit: descriptionCharacterLimit, context: context)
    }

    /// Rule: `compatibility:` over `compatibilityCharacterLimit` characters
    /// draws a `.warning` diagnostic; the value is kept as data.
    ///
    /// - Parameter context: The rule context.
    /// - Returns: A diagnostic when over the limit, else `nil`.
    private static func compatibilityOverLimitDiagnostic(_ context: RuleContext) -> SkillDiagnostic? {
        overLimitDiagnostic(
            fieldName: "compatibility", value: context.frontmatter.compatibility,
            limit: compatibilityCharacterLimit, context: context)
    }

    /// Rule: `compatibility:` present but empty draws an `.advisory`
    /// diagnostic -- the spec's 1-character floor, distinct from
    /// `overLimitDiagnostic`'s upper-bound-only check (which short-circuits
    /// on an empty value, since an empty string can never exceed a limit).
    /// A wholly absent `compatibility:` is unremarkable and draws nothing;
    /// only an explicit `compatibility: ""` is worth a note.
    ///
    /// - Parameter context: The rule context.
    /// - Returns: A diagnostic when `compatibility:` is present but empty,
    ///   else `nil`.
    private static func emptyCompatibilityDiagnostic(_ context: RuleContext) -> SkillDiagnostic? {
        guard context.frontmatter.compatibility == "" else { return nil }
        return SkillDiagnostic(
            severity: .advisory, skillID: context.id, provenance: context.provenance,
            message: "compatibility is present but empty; kept as data.")
    }

    // MARK: - description: required

    /// Rule: a missing, empty, or whitespace-only `description:` draws a
    /// `.warning` diagnostic and excludes the skill from the model-facing
    /// surface (it cannot be disclosed without one) while keeping it
    /// user-invocable -- this package's one deliberate softening of the
    /// client-implementation guide's skip-entirely rule (plan.md §4,
    /// decision #27).
    ///
    /// Trims before testing emptiness so `description: "   "` -- whitespace
    /// a model could never usefully disclose -- draws the same diagnostic
    /// as a genuinely absent or empty value, rather than slipping through
    /// as "present".
    ///
    /// - Parameter context: The rule context.
    /// - Returns: A diagnostic when `description:` is missing, empty, or
    ///   whitespace-only, else `nil`.
    private static func missingDescriptionDiagnostic(_ context: RuleContext) -> SkillDiagnostic? {
        let trimmed = context.frontmatter.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == nil || trimmed == "" else {
            return nil
        }
        return SkillDiagnostic(
            severity: .warning, skillID: context.id, provenance: context.provenance,
            message: "description is missing or empty; excluded from the model-facing surface, "
                + "kept user-invocable.")
    }

    // MARK: - partial: true (retired)

    /// Rule: `partial: true` is retired (decision #29) -- shared building
    /// blocks are now `_partials/*.md` files in the stack, not skill
    /// directories.
    ///
    /// Draws a `.warning` diagnostic and hides the skill from every surface,
    /// preserving the old intent without reviving the field.
    ///
    /// - Parameter context: The rule context.
    /// - Returns: A diagnostic when `partial:` is `true`, else `nil`.
    private static func partialFlagDiagnostic(_ context: RuleContext) -> SkillDiagnostic? {
        guard context.frontmatter.partial == true else { return nil }
        return SkillDiagnostic(
            severity: .warning, skillID: context.id, provenance: context.provenance,
            message: "'partial: true' is retired (decision #29); hidden from every surface.")
    }

    // MARK: - Shadowed id

    /// Rule: an id that shadowed one or more lower-precedence copies draws
    /// an `.advisory` diagnostic naming how many (plan.md §4) --
    /// informational only, no effect on eligibility.
    ///
    /// - Parameter context: The rule context.
    /// - Returns: A diagnostic when `shadowedCandidateCount` is nonzero, else
    ///   `nil`.
    private static func shadowedIDDiagnostic(_ context: RuleContext) -> SkillDiagnostic? {
        let count = context.shadowedCandidateCount
        guard count > 0 else { return nil }
        return SkillDiagnostic(
            severity: .advisory, skillID: context.id, provenance: context.provenance,
            message: "shadows \(count) lower-precedence copy\(count == 1 ? "" : "ies") of this id.")
    }

    // MARK: - Body line count

    /// The spec's recommended maximum `SKILL.md` body line count (plan.md
    /// §4).
    private static let recommendedMaximumBodyLineCount = 500

    /// Counts `text`'s lines the way a line-oriented tool like `wc -l` would:
    /// a single trailing newline (the normal shape of a file read from disk)
    /// does not count as an extra, empty final line.
    ///
    /// Splitting on `"\n"` alone over-counts by one whenever `text` ends
    /// with a newline, since that produces a spurious empty trailing
    /// element -- `DecodedSkill.body` is carried byte-for-byte from disk, so
    /// every real `SKILL.md` body hits this case.
    ///
    /// - Parameter text: The text to count lines in.
    /// - Returns: `0` for an empty string; otherwise the number of
    ///   newline-delimited lines, ignoring one trailing newline.
    private static func lineCount(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines.count
    }

    /// Rule: a body over `recommendedMaximumBodyLineCount` lines draws an
    /// `.advisory` diagnostic -- informational only, no effect on
    /// eligibility.
    ///
    /// - Parameter context: The rule context.
    /// - Returns: A diagnostic when the body exceeds the recommended line
    ///   count, else `nil`.
    private static func bodyLineCountDiagnostic(_ context: RuleContext) -> SkillDiagnostic? {
        let count = lineCount(of: context.body)
        guard count > recommendedMaximumBodyLineCount else { return nil }
        return SkillDiagnostic(
            severity: .advisory, skillID: context.id, provenance: context.provenance,
            message: "SKILL.md body is \(count) lines, exceeding the spec's recommended "
                + "\(recommendedMaximumBodyLineCount)-line limit.")
    }

    // MARK: - Unknown top-level keys

    /// Rule: any top-level frontmatter key `FrontmatterDecoder` did not
    /// recognize draws an `.advisory` diagnostic naming them (plan.md §4) --
    /// informational only, never blocks loading.
    ///
    /// - Parameter context: The rule context.
    /// - Returns: A diagnostic when `unknownTopLevelKeys` is nonempty, else
    ///   `nil`.
    private static func unknownTopLevelKeysDiagnostic(_ context: RuleContext) -> SkillDiagnostic? {
        guard !context.frontmatter.unknownTopLevelKeys.isEmpty else { return nil }
        return SkillDiagnostic(
            severity: .advisory, skillID: context.id, provenance: context.provenance,
            message: "unrecognized top-level frontmatter key(s): "
                + "\(context.frontmatter.unknownTopLevelKeys.joined(separator: ", ")).")
    }
}
