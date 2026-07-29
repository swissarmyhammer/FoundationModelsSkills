import Foundation
import FoundationModelsSkills
import Testing

/// Tests for `SkillValidator` and `SkillDiagnostic` -- lenient domain
/// validation over a `DecodedSkill` (plan.md §4, §7.1; decision #27), parity
/// target the `skills-ref` reference validator.
///
/// Covers every rule in `SkillValidator`'s own table doc comment: `name`
/// irregularities (load anyway), missing/empty `description` (excluded from
/// the model surface, kept user-invocable), `description`/`compatibility`
/// over-limit (kept as data), unparseable YAML (skip), the retired `partial:
/// true` (hidden from every surface), a shadowed id and an oversized body
/// (both advisory), and unknown top-level keys (advisory) -- plus a
/// diagnostics snapshot over the real `broken/` and `spec-clean` fixtures,
/// asserting layer provenance on every diagnostic.
struct SkillValidatorTests {
    // MARK: - Test helpers

    /// Builds a synthetic `DiscoveredSkill` + `.decoded` outcome and runs
    /// `SkillValidator.validate(discovered:outcome:)` -- the workhorse for
    /// every rule-level test below, which cares about one frontmatter/body
    /// combination in isolation rather than a real fixture on disk.
    ///
    /// - Parameters:
    ///   - id: The directory id `SkillValidator` should treat as canonical.
    ///   - frontmatter: The decoded frontmatter to validate.
    ///   - body: The render-pipeline body to validate.
    ///   - rootIndex: The synthetic winning root's position.
    ///   - shadowedCandidates: Lower-precedence candidates this id shadowed.
    /// - Returns: `SkillValidator`'s result.
    private func validate(
        id: String = "my-skill",
        frontmatter: SkillFrontmatter,
        body: String = "Body text.\n",
        rootIndex: Int = 0,
        shadowedCandidates: [DiscoveredSkill.ShadowedCandidate] = []
    ) -> SkillValidator.Result {
        let root = URL(fileURLWithPath: "/fixture-root")
        let skillDirectory = root.appendingPathComponent(id, isDirectory: true)
        let discovered = DiscoveredSkill(
            id: id, skillDirectory: skillDirectory,
            skillFileURL: skillDirectory.appendingPathComponent("SKILL.md"),
            rootIndex: rootIndex, root: root, shadowedCandidates: shadowedCandidates)
        let decodedSkill = DecodedSkill(frontmatter: frontmatter, body: body, notes: [])
        return SkillValidator.validate(discovered: discovered, outcome: .decoded(decodedSkill))
    }

    /// Discovers and validates one real fixture id under `root`, via the
    /// `validate(discovered:text:)` convenience -- the workhorse for the
    /// fixture-stack diagnostics-snapshot tests below.
    ///
    /// - Parameters:
    ///   - root: The layer root to discover over (e.g. `broken/`).
    ///   - id: The fixture's directory id.
    /// - Throws: If the fixture id is not found under `root`, or its
    ///   `SKILL.md` cannot be read.
    /// - Returns: `SkillValidator`'s result, plus the `DiscoveredSkill` used
    ///   (for provenance assertions).
    private func validateFixture(
        root: URL, id: String
    ) throws -> (result: SkillValidator.Result, discovered: DiscoveredSkill) {
        let discovered = try #require(SkillDiscovery(roots: [root]).discover().first { $0.id == id })
        let text = try String(contentsOf: discovered.skillFileURL, encoding: .utf8)
        return (SkillValidator.validate(discovered: discovered, text: text), discovered)
    }

    // MARK: - Rule matrix: load-anyway vs hide (proves the acceptance criterion's table)

    /// One row of the rule matrix: a frontmatter combination that must raise
    /// a diagnostic, and whether the resulting skill still loads (with data
    /// kept) or is hidden from every surface.
    private struct RuleMatrixCase: Sendable {
        let name: String
        let frontmatter: SkillFrontmatter
        let expectHidden: Bool
    }

    private static let ruleMatrixCases: [RuleMatrixCase] = [
        RuleMatrixCase(
            name: "name mismatch",
            frontmatter: SkillFrontmatter(name: "totally-different", description: "A description."),
            expectHidden: false),
        RuleMatrixCase(
            name: "name too long",
            frontmatter: SkillFrontmatter(
                name: String(repeating: "a", count: 65), description: "A description."),
            expectHidden: false),
        RuleMatrixCase(
            name: "name bad characters",
            frontmatter: SkillFrontmatter(name: "My_Skill", description: "A description."),
            expectHidden: false),
        RuleMatrixCase(
            name: "name leading hyphen",
            frontmatter: SkillFrontmatter(name: "-my-skill", description: "A description."),
            expectHidden: false),
        RuleMatrixCase(
            name: "name trailing hyphen",
            frontmatter: SkillFrontmatter(name: "my-skill-", description: "A description."),
            expectHidden: false),
        RuleMatrixCase(
            name: "name consecutive hyphens",
            frontmatter: SkillFrontmatter(name: "my--skill", description: "A description."),
            expectHidden: false),
        RuleMatrixCase(
            name: "description over limit",
            frontmatter: SkillFrontmatter(
                name: "my-skill", description: String(repeating: "d", count: 1025)),
            expectHidden: false),
        RuleMatrixCase(
            name: "compatibility over limit",
            frontmatter: SkillFrontmatter(
                name: "my-skill", description: "A description.",
                compatibility: String(repeating: "c", count: 501)),
            expectHidden: false),
        RuleMatrixCase(
            name: "partial flag",
            frontmatter: SkillFrontmatter(name: "my-skill", description: "A description.", partial: true),
            expectHidden: true),
    ]

    @Test("rule matrix: every irregularity raises a diagnostic; only partial:true hides",
        arguments: ruleMatrixCases)
    private func ruleMatrixLoadAnywayVsHide(_ ruleCase: RuleMatrixCase) {
        let result = validate(frontmatter: ruleCase.frontmatter)
        #expect(!result.diagnostics.isEmpty, "\(ruleCase.name) should raise a diagnostic")
        #expect(result.skill != nil, "\(ruleCase.name) should still load")
        #expect(result.skill?.isHidden == ruleCase.expectHidden, "\(ruleCase.name)")
    }

    // MARK: - name: rules (load anyway)

    @Test(
        "name irregularities each draw a diagnostic but still load under the directory id",
        arguments: [
            String(repeating: "a", count: 65),
            "My_Skill",
            "-my-skill",
            "my-skill-",
            "my--skill",
            "different-name",
        ])
    func nameIrregularityDrawsDiagnosticAndLoadsAnyway(name: String) {
        let result = validate(id: "my-skill", frontmatter: SkillFrontmatter(name: name, description: "d"))
        #expect(result.diagnostics.contains { $0.severity == .warning })
        #expect(result.skill != nil)
        #expect(result.skill?.id == "my-skill")
    }

    @Test func validNameMatchingDirectoryIDProducesNoDiagnostic() {
        let result = validate(
            id: "my-skill", frontmatter: SkillFrontmatter(name: "my-skill", description: "d"))
        #expect(result.diagnostics.isEmpty)
    }

    @Test func absentNameProducesNoDiagnosticClaudeStyleCompat() {
        let result = validate(id: "my-skill", frontmatter: SkillFrontmatter(description: "d"))
        #expect(result.diagnostics.isEmpty)
        #expect(result.skill != nil)
    }

    // MARK: - description: required (excluded from model surface, kept user-invocable)

    @Test("missing or empty description excludes the model surface but stays user-invocable",
        arguments: [nil, ""] as [String?])
    func missingOrEmptyDescriptionExcludesModelSurface(description: String?) {
        let result = validate(frontmatter: SkillFrontmatter(name: "my-skill", description: description))
        #expect(result.diagnostics.contains { $0.severity == .warning })
        #expect(result.skill?.isModelVisibleEligible == false)
        #expect(result.skill?.isUserInvocableEligible == true)
        #expect(result.skill?.isHidden == false)
    }

    @Test func presentDescriptionWithinLimitProducesNoDiagnostic() {
        let result = validate(frontmatter: SkillFrontmatter(name: "my-skill", description: "A description."))
        #expect(result.diagnostics.isEmpty)
        #expect(result.skill?.isModelVisibleEligible == true)
    }

    @Test func descriptionOverLimitIsAWarningButDataIsKept() {
        let longDescription = String(repeating: "d", count: 1025)
        let result = validate(
            frontmatter: SkillFrontmatter(name: "my-skill", description: longDescription))
        #expect(result.diagnostics.contains { $0.severity == .warning })
        #expect(result.skill?.isModelVisibleEligible == true)
        #expect(result.skill?.frontmatter.description == longDescription)
    }

    @Test func descriptionAtExactlyTheLimitProducesNoOverLimitDiagnostic() {
        let exactDescription = String(repeating: "d", count: 1024)
        let result = validate(
            frontmatter: SkillFrontmatter(name: "my-skill", description: exactDescription))
        #expect(result.diagnostics.isEmpty)
    }

    // MARK: - compatibility: over-limit is a warning, data kept

    @Test func compatibilityOverLimitIsAWarningButDataIsKept() {
        let longCompatibility = String(repeating: "c", count: 501)
        let result = validate(
            frontmatter: SkillFrontmatter(
                name: "my-skill", description: "A description.", compatibility: longCompatibility))
        #expect(result.diagnostics.contains { $0.severity == .warning })
        #expect(result.skill?.frontmatter.compatibility == longCompatibility)
    }

    @Test func compatibilityWithinLimitProducesNoDiagnostic() {
        let result = validate(
            frontmatter: SkillFrontmatter(
                name: "my-skill", description: "A description.", compatibility: "Requires bash."))
        #expect(result.diagnostics.isEmpty)
    }

    @Test func compatibilityAbsentProducesNoDiagnostic() {
        let result = validate(frontmatter: SkillFrontmatter(name: "my-skill", description: "A description."))
        #expect(result.diagnostics.isEmpty)
    }

    // MARK: - Unparseable YAML: skip

    @Test func unparseableYAMLSkipOutcomeProducesASkipDiagnosticAndNoSkill() {
        let root = URL(fileURLWithPath: "/fixture-root")
        let skillDirectory = root.appendingPathComponent("bad-skill", isDirectory: true)
        let discovered = DiscoveredSkill(
            id: "bad-skill", skillDirectory: skillDirectory,
            skillFileURL: skillDirectory.appendingPathComponent("SKILL.md"),
            rootIndex: 2, root: root)

        let result = SkillValidator.validate(
            discovered: discovered, outcome: .skipped(reason: "unparseable YAML frontmatter"))

        #expect(result.skill == nil)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.severity == .skip)
        #expect(result.diagnostics.first?.skillID == "bad-skill")
        #expect(result.diagnostics.first?.message.contains("unparseable YAML frontmatter") == true)
        #expect(result.diagnostics.first?.provenance.rootIndex == 2)
        #expect(result.diagnostics.first?.provenance.root == root)
    }

    // MARK: - partial: true (retired): hidden from every surface

    @Test func partialTrueDrawsDiagnosticAndHidesFromEverySurface() {
        let result = validate(
            frontmatter: SkillFrontmatter(name: "my-skill", description: "A description.", partial: true))
        #expect(result.diagnostics.contains { $0.severity == .warning })
        #expect(result.skill?.isHidden == true)
        #expect(result.skill?.isModelVisibleEligible == false)
        #expect(result.skill?.isUserInvocableEligible == false)
    }

    @Test func partialFalseOrAbsentDoesNotHide() {
        for partial in [false, nil] as [Bool?] {
            let result = validate(
                frontmatter: SkillFrontmatter(name: "my-skill", description: "A description.", partial: partial))
            #expect(result.skill?.isHidden == false)
        }
    }

    // MARK: - Shadowed id: advisory only

    @Test func shadowedIDDrawsAnAdvisoryDiagnostic() {
        let shadowed = DiscoveredSkill.ShadowedCandidate(
            rootIndex: 0, root: URL(fileURLWithPath: "/lower-root"),
            skillDirectory: URL(fileURLWithPath: "/lower-root/my-skill"))
        let result = validate(
            frontmatter: SkillFrontmatter(name: "my-skill", description: "A description."),
            shadowedCandidates: [shadowed])
        #expect(result.diagnostics.contains { $0.severity == .advisory })
        #expect(result.skill != nil)
        #expect(result.skill?.isModelVisibleEligible == true)
    }

    @Test func noShadowedCandidatesProducesNoShadowDiagnostic() {
        let result = validate(frontmatter: SkillFrontmatter(name: "my-skill", description: "A description."))
        #expect(result.diagnostics.isEmpty)
    }

    // MARK: - SKILL.md body over 500 lines: advisory only

    @Test func bodyOverFiveHundredLinesDrawsAnAdvisoryDiagnostic() {
        let longBody = Array(repeating: "line", count: 501).joined(separator: "\n")
        let result = validate(
            frontmatter: SkillFrontmatter(name: "my-skill", description: "A description."), body: longBody)
        #expect(result.diagnostics.contains { $0.severity == .advisory })
    }

    @Test func bodyAtExactlyFiveHundredLinesProducesNoDiagnostic() {
        let exactBody = Array(repeating: "line", count: 500).joined(separator: "\n")
        let result = validate(
            frontmatter: SkillFrontmatter(name: "my-skill", description: "A description."), body: exactBody)
        #expect(result.diagnostics.isEmpty)
    }

    // A real `DecodedSkill.body` is carried byte-for-byte from disk, and
    // every real `SKILL.md` file ends in a trailing newline -- these two
    // cases mirror that realistic shape (rather than the newline-free join
    // above) to guard against an off-by-one where a single trailing `\n`
    // gets miscounted as an extra, empty final line.

    @Test func bodyAtExactlyFiveHundredLinesWithATrailingNewlineProducesNoDiagnostic() {
        let exactBody = Array(repeating: "line", count: 500).joined(separator: "\n") + "\n"
        let result = validate(
            frontmatter: SkillFrontmatter(name: "my-skill", description: "A description."), body: exactBody)
        #expect(result.diagnostics.isEmpty)
    }

    @Test func bodyOverFiveHundredLinesWithATrailingNewlineDrawsAnAdvisoryDiagnostic() {
        let longBody = Array(repeating: "line", count: 501).joined(separator: "\n") + "\n"
        let result = validate(
            frontmatter: SkillFrontmatter(name: "my-skill", description: "A description."), body: longBody)
        #expect(result.diagnostics.contains { $0.severity == .advisory })
    }

    // MARK: - Unknown top-level keys: advisory only

    @Test func unknownTopLevelKeysDrawAnAdvisoryDiagnostic() {
        let frontmatter = SkillFrontmatter(
            name: "my-skill", description: "A description.",
            unknownTopLevelKeys: ["frobnicate", "widget"])
        let result = validate(frontmatter: frontmatter)
        #expect(result.diagnostics.contains { $0.severity == .advisory })
        #expect(result.skill?.isModelVisibleEligible == true)
    }

    @Test func noUnknownTopLevelKeysProducesNoDiagnostic() {
        let result = validate(frontmatter: SkillFrontmatter(name: "my-skill", description: "A description."))
        #expect(result.diagnostics.isEmpty)
    }

    // MARK: - Diagnostic provenance carries the winning layer

    @Test func diagnosticProvenanceMatchesTheDiscoveredWinningLayer() throws {
        let result = validate(
            frontmatter: SkillFrontmatter(name: "wrong-name", description: "A description."), rootIndex: 2)
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.provenance.rootIndex == 2)
        #expect(diagnostic.provenance.root == URL(fileURLWithPath: "/fixture-root"))
    }

    // MARK: - Fixture stack: broken/ + spec-clean diagnostics snapshot

    private static let brokenRoot = FixtureLibrary.url(relativePath: "broken")
    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    @Test func specCleanFixtureProducesZeroDiagnostics() throws {
        let (result, _) = try validateFixture(root: Self.projectSkillsRoot, id: "spec-clean")
        #expect(result.diagnostics.isEmpty)
        #expect(result.skill?.isModelVisibleEligible == true)
        #expect(result.skill?.isUserInvocableEligible == true)
        #expect(result.skill?.isHidden == false)
    }

    @Test func brokenBadColonDescriptionFixtureDecodesCleanlyViaRetryProducingNoValidatorDiagnostics()
        throws
    {
        // The unquoted-colon description is a *decoder*-level concern (the
        // quoting-fallback retry, covered by FrontmatterDecoderTests) --
        // once decoded, this fixture's name matches its directory and its
        // description is present, so SkillValidator itself has nothing to
        // report.
        let (result, _) = try validateFixture(root: Self.brokenRoot, id: "bad-colon-description")
        #expect(result.diagnostics.isEmpty)
        #expect(result.skill != nil)
    }

    @Test func brokenMissingDescriptionFixtureProducesExactlyOneWarningDiagnosticWithProvenance()
        throws
    {
        let (result, discovered) = try validateFixture(root: Self.brokenRoot, id: "missing-description")
        #expect(result.diagnostics.count == 1)
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.skillID == "missing-description")
        #expect(diagnostic.provenance.rootIndex == discovered.rootIndex)
        #expect(diagnostic.provenance.root == discovered.root)
        #expect(result.skill?.isModelVisibleEligible == false)
        #expect(result.skill?.isUserInvocableEligible == true)
        #expect(result.skill?.isHidden == false)
    }

    @Test func brokenNameMismatchFixtureProducesExactlyOneWarningDiagnosticWithProvenance() throws {
        let (result, discovered) = try validateFixture(root: Self.brokenRoot, id: "name-mismatch")
        #expect(result.diagnostics.count == 1)
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.skillID == "name-mismatch")
        #expect(diagnostic.provenance.rootIndex == discovered.rootIndex)
        #expect(diagnostic.provenance.root == discovered.root)
        #expect(result.skill?.id == "name-mismatch")
        #expect(result.skill?.isModelVisibleEligible == true)
    }

    @Test func brokenPartialFlagFixtureProducesExactlyOneWarningDiagnosticAndHides() throws {
        let (result, discovered) = try validateFixture(root: Self.brokenRoot, id: "partial-flag")
        #expect(result.diagnostics.count == 1)
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.skillID == "partial-flag")
        #expect(diagnostic.provenance.rootIndex == discovered.rootIndex)
        #expect(diagnostic.provenance.root == discovered.root)
        #expect(result.skill?.isHidden == true)
        #expect(result.skill?.isModelVisibleEligible == false)
        #expect(result.skill?.isUserInvocableEligible == false)
    }
}
