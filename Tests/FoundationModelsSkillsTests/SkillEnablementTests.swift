import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsSkills

/// Tests for the `enabled` frontmatter key of a skill.
///
/// The key comes from Extras. A skill with `enabled: false` is off. A value
/// that is not a bool also turns the skill off, with one diagnostic. A
/// missing key leaves the skill on. A skill that is off is not in the
/// catalog, thus no surface shows it: not the model list, not the tool
/// description, not search, not the preload, and not the user `/` menu. Only
/// the host view `records()` lists it, as off.
struct SkillEnablementTests {
    // MARK: - Constants

    /// The skill that stays on in each case.
    private static let onSkillID = "alpha"

    /// The skill that each case turns off.
    private static let offSkillID = "bravo"

    /// The frontmatter line that turns a skill off.
    private static let offFrontmatter = "enabled: false\n"

    /// The frontmatter line that turns a skill on in so many words.
    private static let onFrontmatter = "enabled: true\n"

    /// The frontmatter line whose value is a string, not a bool.
    private static let invalidFrontmatter = "enabled: \"yes\"\n"

    /// The frontmatter line that puts a skill into the preload.
    private static let preloadFrontmatter = "preload: true\n"

    /// The body of the skill that is off. A preload that holds it shows the
    /// skill.
    private static let offSkillBody = "The body of the skill that is off."

    /// A stub `SKILL.md` that holds only the key that turns a skill off.
    private static let offStub = "---\nenabled: false\n---\n"

    // MARK: - The model surface

    @Test func aDisabledSkillIsNotInTheMetadata() throws {
        let fixture = try Fixture(testedFrontmatter: Self.offFrontmatter)
        defer { fixture.remove() }

        #expect(fixture.registry.metadata().map(\.id) == [Self.onSkillID])
    }

    @Test func aDisabledSkillIsNotInTheListOfTheToolDescription() throws {
        let fixture = try Fixture(testedFrontmatter: Self.offFrontmatter)
        defer { fixture.remove() }

        let tool = try SkillsTool.make(context: ResourceTestSupport.makeContext(registry: fixture.registry))

        #expect(tool.skillIDs == [Self.onSkillID])
        #expect(!tool.description.contains("`\(Self.offSkillID)`"))
    }

    @Test func searchDoesNotFindADisabledSkill() async throws {
        let fixture = try Fixture(testedFrontmatter: Self.offFrontmatter)
        defer { fixture.remove() }
        let tool = try SkillsTool.make(context: ResourceTestSupport.makeContext(registry: fixture.registry))

        let answer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "search skill", "query": Self.offSkillID]))

        #expect(!SkillLineReader.ids(in: answer).contains(Self.offSkillID))
    }

    @Test func thePreloadLeavesOutADisabledSkill() async throws {
        let fixture = try Fixture(testedFrontmatter: Self.offFrontmatter + Self.preloadFrontmatter)
        defer { fixture.remove() }

        #expect(!(await fixture.registry.preloadedBodies()).contains(Self.offSkillBody))
    }

    // MARK: - The user surface

    @Test func theCommandListingLeavesOutADisabledSkill() throws {
        let fixture = try Fixture(testedFrontmatter: Self.offFrontmatter)
        defer { fixture.remove() }

        #expect(fixture.registry.commandListing().map(\.id) == [Self.onSkillID])
    }

    // MARK: - use skill

    @Test func useSkillGivesADisabledIDTheCorrectiveOfAnUnknownID() async throws {
        let fixture = try Fixture(testedFrontmatter: Self.offFrontmatter)
        defer { fixture.remove() }
        let unknown = try Fixture(testedFrontmatter: nil)
        defer { unknown.remove() }

        let disabledAnswer = try await Self.useAnswer(id: Self.offSkillID, registry: fixture.registry)
        let unknownAnswer = try await Self.useAnswer(id: Self.offSkillID, registry: unknown.registry)

        #expect(disabledAnswer == unknownAnswer)
    }

    // MARK: - The layers

    @Test func aHigherStubThatTurnsASkillOffHidesTheLowerCopy() throws {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 2)
        defer { LayerFixtureSupport.removeDirectories(directories) }
        try ReloadTestSupport.writeSkillFile(id: Self.onSkillID, in: directories[0])
        try ReloadTestSupport.writeSkillFile(id: Self.offSkillID, in: directories[0])
        try LayerFixtureSupport.writeTextFile(
            Self.offStub, at: "\(Self.offSkillID)/\(SkillDiscovery.skillFileName)", in: directories[1])

        let registry = SkillsRegistry(roots: directories)

        #expect(registry.metadata().map(\.id) == [Self.onSkillID])
        #expect(registry.diagnostics.isEmpty)
    }

    // MARK: - The value of the key

    @Test func aValueThatIsNotABoolTurnsTheSkillOffWithOneDiagnostic() throws {
        let fixture = try Fixture(testedFrontmatter: Self.invalidFrontmatter)
        defer { fixture.remove() }

        let diagnostics = fixture.registry.diagnostics

        #expect(fixture.registry.metadata().map(\.id) == [Self.onSkillID])
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.skillID == Self.offSkillID)
    }

    @Test func aDisabledSkillGivesNoDiagnostic() throws {
        let fixture = try Fixture(testedFrontmatter: Self.offFrontmatter)
        defer { fixture.remove() }

        #expect(fixture.registry.diagnostics.isEmpty)
    }

    @Test func aSkillWithNoEnabledKeyIsOn() throws {
        let fixture = try Fixture(testedFrontmatter: "")
        defer { fixture.remove() }

        #expect(fixture.registry.metadata().map(\.id) == [Self.onSkillID, Self.offSkillID])
    }

    @Test func enabledTrueIsAKnownKeyThatLeavesTheSkillOn() throws {
        let fixture = try Fixture(testedFrontmatter: Self.onFrontmatter)
        defer { fixture.remove() }

        #expect(fixture.registry.metadata().map(\.id) == [Self.onSkillID, Self.offSkillID])
        #expect(fixture.registry.diagnostics.isEmpty)
    }

    // MARK: - The host surface

    @Test func theRecordsHoldADisabledSkillAsOff() throws {
        let fixture = try Fixture(testedFrontmatter: Self.offFrontmatter)
        defer { fixture.remove() }

        let records = fixture.registry.records()

        #expect(records.map(\.id) == [Self.onSkillID, Self.offSkillID])
        #expect(records.map(\.isEnabled) == [true, false])
        #expect(fixture.registry.diagnostics.isEmpty)
    }

    @Test func theRecordsHoldASkillWithAValueThatIsNotABoolAsOff() throws {
        let fixture = try Fixture(testedFrontmatter: Self.invalidFrontmatter)
        defer { fixture.remove() }

        let records = fixture.registry.records()

        #expect(records.map(\.id) == [Self.onSkillID, Self.offSkillID])
        #expect(records.map(\.isEnabled) == [true, false])
        #expect(fixture.registry.diagnostics.count == 1)
    }

    @Test func aRecordGivesTheLayerOfTheSkill() throws {
        let fixture = try Fixture(testedFrontmatter: Self.offFrontmatter)
        defer { fixture.remove() }

        let records = fixture.registry.records()

        #expect(records.map(\.layer) == [.project, .project])
        #expect(records.map(\.marketplace) == [nil, nil])
    }

    // MARK: - Helpers

    /// Gives the answer of the fused tool to one `use skill` call.
    ///
    /// - Parameters:
    ///   - id: The skill id of the call.
    ///   - registry: The registry the tool reads.
    /// - Returns: The answer of the tool.
    /// - Throws: Whatever `SkillsTool.make(context:)` or `call(arguments:)`
    ///   throws.
    private static func useAnswer(id: String, registry: SkillsRegistry) async throws -> String {
        let tool = try SkillsTool.make(context: ResourceTestSupport.makeContext(registry: registry))
        return try await tool.call(arguments: GeneratedContent(properties: ["op": "use skill", "id": id]))
    }

    // MARK: - Fixtures

    /// A temporary layer that holds `onSkillID` and, when asked, `offSkillID`,
    /// and an unwatched registry over it.
    private struct Fixture {
        /// The temporary layer root.
        let root: URL

        /// The registry over `root`.
        let registry: SkillsRegistry

        /// Writes the skills into a new root, and builds the registry.
        ///
        /// - Parameter testedFrontmatter: The extra frontmatter lines of
        ///   `offSkillID`, or `nil` to leave that skill out of the layer.
        /// - Throws: Whatever the directory or a file write throws.
        init(testedFrontmatter: String?) throws {
            root = try HotReloadTestSupport.makeTempDirectory()
            try ReloadTestSupport.writeSkillFile(id: SkillEnablementTests.onSkillID, in: root)
            if let testedFrontmatter {
                try ReloadTestSupport.writeSkillFile(
                    id: SkillEnablementTests.offSkillID, in: root, extraFrontmatter: testedFrontmatter,
                    body: SkillEnablementTests.offSkillBody)
            }
            registry = SkillsRegistry(roots: [root])
        }

        /// Deletes the temporary root.
        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
