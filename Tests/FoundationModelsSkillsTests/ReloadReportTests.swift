import Foundation
import Testing

@testable import FoundationModelsSkills

/// Holds ``ReloadReport`` -- what one hot reload changed, as lines a host
/// writes -- to the counts it reads and to the text of its lines.
@Suite struct ReloadReportTests {
    /// The fixture skill that carries `disable-model-invocation: true`, thus
    /// the metadata of the fixture stack holds exactly one hidden skill.
    private static let modelHiddenSkillID = "deploy"

    // MARK: - The counts of the report

    @Test func theSkillCountIsTheCountOfTheMetadataThatTheReportGot() async {
        let registry = Self.makeFixtureRegistry()
        let onePublishedSkill = Array(registry.metadata().prefix(1))
        #expect(
            registry.metadata().count > onePublishedSkill.count,
            "the fixture stack must hold more than one skill, or this case proves nothing")

        let report = await ReloadReport.make(metadata: onePublishedSkill, registry: registry)

        #expect(report.skillCount == onePublishedSkill.count)
    }

    @Test func theModelVisibleCountLeavesTheHiddenFixtureSkillOut() async {
        let registry = Self.makeFixtureRegistry()
        let metadata = registry.metadata()
        #expect(
            metadata.contains { $0.id == Self.modelHiddenSkillID && !$0.isModelVisible },
            "the fixture catalog must still carry the model-hidden skill, or this case proves nothing")

        let report = await ReloadReport.make(metadata: metadata, registry: registry)

        #expect(report.modelVisibleCount == metadata.count - 1)
    }

    @Test func thePreloadedCharacterCountIsTheLengthOfTheRefreshedPreloadText() async {
        let registry = Self.makeFixtureRegistry()
        let preloaded = await registry.preloadedBodies()
        #expect(!preloaded.isEmpty, "the fixture stack must preload a body, or this case proves nothing")

        let report = await ReloadReport.make(metadata: registry.metadata(), registry: registry)

        #expect(report.preloadedCharacterCount == preloaded.count)
    }

    @Test func theCommandIDsAreTheIDsOfTheRefreshedListing() async {
        let registry = Self.makeFixtureRegistry()

        let report = await ReloadReport.make(metadata: registry.metadata(), registry: registry)

        #expect(report.commandIDs == registry.commandListing().map(\.id))
    }

    // MARK: - The lines of the report

    /// The counts of the report that the line cases read.
    private static let skillCount = 3

    /// How many of those skills the model sees, in the line cases.
    private static let modelVisibleCount = 2

    /// The length of the preload text, in the line cases.
    private static let preloadedCharacterCount = 140

    /// The ids of the listing, in the line cases.
    private static let commandIDs = ["alpha", "beta"]

    /// The report the line cases read.
    private static func makeReport() -> ReloadReport {
        ReloadReport(
            skillCount: skillCount,
            modelVisibleCount: modelVisibleCount,
            preloadedCharacterCount: preloadedCharacterCount,
            commandIDs: commandIDs)
    }

    @Test func theFirstLineNamesTheSkillCountAndTheModelVisibleCount() {
        #expect(Self.makeReport().lines.first == "reload: 3 skills, 2 model-visible")
    }

    @Test func theSecondLineNamesTheLengthOfThePreloadText() {
        #expect(Self.makeReport().lines[1] == "preload: 140 rendered characters")
    }

    @Test func theLastLineNamesEveryIDOfTheListing() {
        #expect(Self.makeReport().lines.last == "listing: alpha, beta")
    }

    @Test func theReportHasOneLineForEachOfItsThreeReadings() {
        #expect(Self.makeReport().lines.count == 3)
    }

    // MARK: - Fixture assembly

    /// Builds a registry over the `Examples/skill-library` fixture stack.
    ///
    /// - Returns: The registry every case in this suite reports over.
    private static func makeFixtureRegistry() -> SkillsRegistry {
        SkillsRegistry(stack: FixtureLibrary.stack())
    }
}
