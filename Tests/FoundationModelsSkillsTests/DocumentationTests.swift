import Foundation
import Testing

@testable import FoundationModelsSkills

/// Holds every document of this package to the override rule that the code
/// realizes (plan.md §3, §4, decision #32).
///
/// The unit of override is the file. For one path of a skill, the copy in the
/// highest layer directory that holds it wins, and a file that only a lower
/// directory holds stays visible. `SkillDiscovery` reads that combined view
/// over the layer directories, `DiscoveredSkill` carries each of them, and
/// `RunScript` runs a script in the layer directory that gave the winning
/// copy.
///
/// The suite reads each document from the disk, found from this file's
/// `#filePath`. Thus a document that states the rule that shipped before
/// fails a case here, and a document that states no rule at all fails one
/// too.
///
/// Each name of the public API comes from the type itself. Thus a rename
/// makes this suite fail until each document names the new field.
@Suite("Override rule docs")
struct DocumentationTests {
    // MARK: - The documents

    /// The design record, relative to the package root.
    private static let planPath = "plan.md"

    /// The host guide of the operations, relative to the package root.
    private static let operationsPath = "docs/operations.md"

    /// The record of each change to the public API, relative to the package
    /// root.
    private static let changelogPath = "CHANGELOG.md"

    /// The README of the package, relative to the package root.
    private static let readmePath = "README.md"

    /// The design record of the marketplaces, relative to the package root.
    private static let marketplaceDesignPath = "marketplace.md"

    /// The host guide of the marketplaces, relative to the package root.
    private static let marketplaceGuidePath = "docs/marketplaces.md"

    /// The security posture, relative to the package root.
    private static let securityPath = "docs/security.md"

    /// The guide for a person who changes this package, relative to the
    /// package root.
    private static let developmentPath = "docs/development.md"

    /// The lower copy of the fixture skill that shows the override
    /// (plan.md §11), relative to the package root.
    private static let defaultsBaseStylePath =
        "Examples/skill-library/defaults/base-style/SKILL.md"

    /// The higher copy of the same fixture skill, relative to the package
    /// root.
    private static let userBaseStylePath = "Examples/skill-library/user/base-style/SKILL.md"

    /// Every document that a reader takes the override rule from.
    private static let documents = [
        planPath, operationsPath, changelogPath, readmePath, marketplaceDesignPath,
        marketplaceGuidePath, securityPath, developmentPath, defaultsBaseStylePath,
        userBaseStylePath,
    ]

    /// Every document that describes the behavior of today.
    ///
    /// `CHANGELOG.md` is the record of what changed, thus it alone names the
    /// field that is gone.
    private static let currentBehaviorDocuments = documents.filter { $0 != changelogPath }

    /// Every document that must state the override rule in its own words.
    ///
    /// `CHANGELOG.md` records a change and not a rule, and
    /// `docs/development.md` records the deviations from the plan. Neither
    /// one describes the stack to a reader.
    private static let ruleStatingDocuments = documents.filter {
        $0 != changelogPath && $0 != developmentPath
    }

    // MARK: - The rule that shipped before

    /// Each wording of the rule that shipped before: a higher layer hid every
    /// file of a lower layer of the same skill.
    ///
    /// Each entry is lower case, because the comparison reads the lower case
    /// of the document.
    private static let earlierRuleWordings = [
        "full-replace",
        "full replace",
        "fully replace",
        "replaces the full",
        "replaces the whole",
        "replaces the defaults copy",
        "there is no merge",
        "field-by-field merge",
    ]

    /// The name of the `DiscoveredSkill` field that carried the copies that
    /// lost. The field is gone, thus no document may give it as a field of
    /// today.
    private static let removedShadowedCandidatesFieldName = "shadowedCandidates"

    /// The working-directory claim of plan.md §7.3 that is not exact any
    /// more. One skill has more than one layer directory now.
    private static let earlierWorkingDirectoryClaim = "cwd = the skill directory"

    // MARK: - The rule of today

    /// The sentence that each document must state.
    private static let overrideRuleSentence = "The unit of override is the file"

    /// The working directory of a `run script` run, spelled as
    /// `RunScript.execute` spells it.
    private static let winningLayerWorkingDirectory =
        "the layer directory that gave the winning copy"

    /// The name of what `SkillDiscovery` reads over the layer directories.
    private static let combinedViewPhrase = "combined view"

    /// The file paths of the layer example that the host guide of the
    /// operations must give (card ^cw1z0q7).
    ///
    /// The example shows one file from each of the three layers, thus a
    /// reader sees that a lower layer still gives the files that no higher
    /// layer holds.
    private static let layerExamplePaths = [
        "defaults/review/scripts/report.sh",
        "user/review/scripts/lint.sh",
        "project/review/references/house-style.md",
    ]

    /// The heading of the decision that records the correction of decision #3
    /// and decision #29.
    private static let correctionDecisionHeading = "32. **Override → the file is the unit.**"

    // MARK: - The names the code gives

    /// A `DiscoveredSkill` that stands for nothing, read for the names of its
    /// fields.
    ///
    /// Discovery opens no file to make one, thus the URL carries no meaning
    /// here.
    private static let sampleSkill: DiscoveredSkill = {
        let placeholder = URL(fileURLWithPath: "/")
        return DiscoveredSkill(
            id: "", skillDirectory: placeholder, skillFileURL: placeholder, rootIndex: 0,
            root: placeholder)
    }()

    /// The name of the type that carries one layer directory of a skill,
    /// taken from the type itself.
    private static let contributingDirectoryTypeName =
        String(describing: DiscoveredSkill.ContributingDirectory.self)

    /// The name of the `DiscoveredSkill` field that carries the layer
    /// directories, taken from the value and not from a copy of the spelling.
    ///
    /// `nil` when no field of the type holds that list any more, which
    /// ``theDiscoveredSkillTypeCarriesItsLayerDirectories()`` reports.
    private static let contributingDirectoriesFieldName: String? =
        Mirror(reflecting: sampleSkill)
        .children
        .first { $0.value is [DiscoveredSkill.ContributingDirectory] }?
        .label

    /// Every claim that a document must make.
    private static let claims: [DocumentClaim] =
        ruleStatingDocuments.map { DocumentClaim(document: $0, text: overrideRuleSentence) }
        + layerExamplePaths.map { DocumentClaim(document: operationsPath, text: $0) }
        + [
            DocumentClaim(document: planPath, text: correctionDecisionHeading),
            DocumentClaim(document: planPath, text: winningLayerWorkingDirectory),
            DocumentClaim(document: operationsPath, text: winningLayerWorkingDirectory),
            DocumentClaim(document: operationsPath, text: combinedViewPhrase),
            DocumentClaim(
                document: changelogPath, text: String(describing: DiscoveredSkill.self)),
            DocumentClaim(document: changelogPath, text: contributingDirectoryTypeName),
            DocumentClaim(
                document: changelogPath, text: removedShadowedCandidatesFieldName),
        ]
        + (contributingDirectoriesFieldName.map { field in
            [planPath, changelogPath].map { DocumentClaim(document: $0, text: field) }
        } ?? [])

    /// One row for each document and each wording of the rule that shipped
    /// before.
    private static let earlierRuleRows: [DocumentClaim] = documents.flatMap { document in
        earlierRuleWordings.map { DocumentClaim(document: document, text: $0) }
    }

    // MARK: - The cases

    @Test(arguments: earlierRuleRows)
    func noDocumentStatesTheRuleThatShippedBefore(row: DocumentClaim) throws {
        let text = try FixtureLibrary.readText(relativePath: row.document).lowercased()

        #expect(
            !text.contains(row.text),
            """
            \(row.document) must not say "\(row.text)": the unit of override is the file, thus a \
            lower layer still gives each file that no higher layer holds
            """)
    }

    @Test(arguments: currentBehaviorDocuments)
    func noDocumentGivesTheRemovedFieldAsAFieldOfToday(document: String) throws {
        let text = try FixtureLibrary.readText(relativePath: document)

        #expect(
            !text.contains(Self.removedShadowedCandidatesFieldName),
            """
            \(document) must not name "\(Self.removedShadowedCandidatesFieldName)": \
            DiscoveredSkill has no such field any more
            """)
    }

    @Test func thePlanGivesTheWorkingDirectoryOfAScriptRun() throws {
        let plan = try FixtureLibrary.readText(relativePath: Self.planPath)

        #expect(
            !plan.contains(Self.earlierWorkingDirectoryClaim),
            """
            \(Self.planPath) must not say "\(Self.earlierWorkingDirectoryClaim)": one skill has \
            more than one layer directory, thus a script runs in \
            \(Self.winningLayerWorkingDirectory)
            """)
    }

    @Test(arguments: claims)
    func theDocumentationMakesEveryClaim(claim: DocumentClaim) throws {
        let text = try FixtureLibrary.readText(relativePath: claim.document)

        #expect(
            text.contains(claim.text),
            "\(claim.document) must state \"\(claim.text)\"")
    }

    @Test func theDiscoveredSkillTypeCarriesItsLayerDirectories() {
        #expect(
            Self.contributingDirectoriesFieldName != nil,
            """
            DiscoveredSkill carries no [\(Self.contributingDirectoryTypeName)] field, thus the \
            cases that hold the documents to naming that field prove nothing
            """)
    }
}
