import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsSkills

/// Tests for `SkillWriter`: `add`, `edit` and `remove` of a skill in the
/// `.user` or `.project` layer of a registry, the refusals of each, and the
/// reload after each write.
///
/// Each test makes a stack of layer directories in temporary folders with
/// `LayerFixtureSupport`. The default stack holds a defaults, a user and a
/// project layer, lowest precedence first.
struct SkillWriterTests {
    /// The name of the skill that a test writes.
    private static let skillName = "new-skill"

    /// The file name of the skill file.
    private static let skillFileName = "SKILL.md"

    /// The path of a file of a skill that is not the skill file.
    private static let referencePath = "references/guide.md"

    /// The text of a file of a skill that is not the skill file.
    private static let referenceText = "Guide text.\n"

    /// The text of a skill file whose frontmatter YAML does not parse.
    private static let unparseableMarkdown = "---\nname: [unclosed\n---\nBody.\n"

    /// The text of a skill file that has no `description`, which the
    /// validator gives a warning for.
    private static let noDescriptionMarkdown = "---\nname: \(skillName)\n---\nBody.\n"

    /// The text of a skill file whose `enabled` value is not a bool.
    private static let badEnabledMarkdown = ReloadTestSupport.skillFileContents(
        id: skillName, extraFrontmatter: "enabled: sometimes\n")

    /// The names that are not one safe path component.
    private static let badNames = ["", ".", "..", "a/b", "../escape", "/absolute"]

    /// The paths that leave the skill folder, or that are not relative.
    private static let escapingPaths = ["../other-skill/SKILL.md", "/etc/hosts", "", "~/notes.md"]

    // MARK: - add

    @Test func addWritesTheSkillFileInTheUserLayerByDefault() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown())

        #expect(fixture.fileExists(Self.skillFileName, of: Self.skillName, in: .user))
    }

    @Test func addWritesTheSkillFileInTheProjectLayerWithProject() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown(), layer: .project)

        #expect(fixture.fileExists(Self.skillFileName, of: Self.skillName, in: .project))
    }

    @Test func addWithProjectWritesNothingInTheUserLayer() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown(), layer: .project)

        #expect(!fixture.folderExists(Self.skillName, in: .user))
    }

    @Test func addWritesTheGivenMarkdown() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown())

        #expect(try fixture.text(of: Self.skillFileName, of: Self.skillName, in: .user) == Self.markdown())
    }

    @Test func addGivesTheNameTheLayerAndThePathOfTheFile() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        let outcome = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown())

        let expected = SkillWriteResult(
            name: Self.skillName, layer: .user,
            path: fixture.url(of: Self.skillFileName, of: Self.skillName, in: .user).path)
        #expect(outcome == .success(expected))
    }

    @Test func addRefusesAFolderThatIsAlreadyInThatLayer() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user, descriptionSuffix: "first")

        let outcome = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown())

        #expect(ResourceTestSupport.correctiveMessage(of: outcome) != nil)
    }

    @Test func addOfAFolderThatIsAlreadyInThatLayerKeepsTheOldFile() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user, descriptionSuffix: "first")

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown(descriptionSuffix: "second"))

        #expect(
            try fixture.text(of: Self.skillFileName, of: Self.skillName, in: .user)
                == Self.markdown(descriptionSuffix: "first"))
    }

    /// A skill of the defaults layer is overridden with `add` of the same
    /// name in the user layer.
    @Test func addInTheUserLayerOverridesASkillOfTheDefaultsLayer() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .defaults, descriptionSuffix: "built in")
        fixture.registry.reload()

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown(descriptionSuffix: "override"))

        #expect(Self.description(of: Self.skillName, in: fixture.registry)?.contains("override") == true)
    }

    @Test(arguments: SkillWriterTests.badNames)
    func addRefusesABadName(name: String) throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        let outcome = try fixture.writer.add(name: name, skillMarkdown: Self.markdown())

        #expect(ResourceTestSupport.correctiveMessage(of: outcome) != nil)
    }

    @Test(arguments: SkillWriterTests.badNames)
    func addOfABadNameWritesNothing(name: String) throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        _ = try fixture.writer.add(name: name, skillMarkdown: Self.markdown())

        #expect(fixture.allFiles() == [])
    }

    @Test func addRefusesMarkdownWhoseFrontmatterDoesNotParse() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        let outcome = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.unparseableMarkdown)

        #expect(ResourceTestSupport.correctiveMessage(of: outcome) != nil)
    }

    @Test func addOfMarkdownWhoseFrontmatterDoesNotParseWritesNothing() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.unparseableMarkdown)

        #expect(!fixture.folderExists(Self.skillName, in: .user))
    }

    /// The corrective of a warning gives the text of the warning, thus the
    /// model can correct the file.
    @Test func addRefusesMarkdownThatTheValidatorWarnsAbout() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        let outcome = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.noDescriptionMarkdown)

        #expect(ResourceTestSupport.correctiveMessage(of: outcome)?.contains("description") == true)
    }

    @Test func addOfMarkdownThatTheValidatorWarnsAboutWritesNothing() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.noDescriptionMarkdown)

        #expect(!fixture.folderExists(Self.skillName, in: .user))
    }

    /// A value of `enabled` that is not a bool turns the skill off, thus such
    /// a file does not load.
    @Test func addRefusesMarkdownWhoseEnabledValueIsNotABool() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.badEnabledMarkdown)

        #expect(!fixture.folderExists(Self.skillName, in: .user))
    }

    @Test func addToALayerThatTheRegistryDoesNotHaveGivesACorrectiveThatNamesIt() throws {
        let fixture = try WriterFixture(sources: [.defaults, .project])
        defer { fixture.remove() }

        let outcome = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown())

        #expect(ResourceTestSupport.correctiveMessage(of: outcome)?.contains("user") == true)
    }

    @Test func addToALayerThatTheRegistryDoesNotHaveWritesNothing() throws {
        let fixture = try WriterFixture(sources: [.defaults, .project])
        defer { fixture.remove() }

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown())

        #expect(fixture.allFiles() == [])
    }

    /// `init(roots:)` labels each root `.project`, thus a registry over bare
    /// roots has no user layer.
    @Test func addInTheUserLayerOfARegistryOverBareRootsGivesACorrective() throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { LayerFixtureSupport.removeDirectories([root]) }
        let writer = SkillWriter(registry: SkillsRegistry(roots: [root], mode: .open))

        let outcome = try writer.add(name: Self.skillName, skillMarkdown: Self.markdown())

        #expect(ResourceTestSupport.correctiveMessage(of: outcome) != nil)
    }

    @Test func addPutsTheNewSkillIntoMetadata() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown())

        #expect(fixture.registry.metadata().map(\.id) == [Self.skillName])
    }

    @Test func addPublishesExactlyOneReload() async throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        let tally = ReloadTestSupport.EventTally()
        let subscription = ReloadTestSupport.tally(fixture.registry.onReload, into: tally)
        defer { subscription.cancel() }

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown())

        await ReloadTestSupport.expectExactlyOneEvent(tally)
    }

    // MARK: - edit

    @Test func editWritesTheSkillFileInTheUserLayerByDefault() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user, descriptionSuffix: "before")

        _ = try fixture.writer.edit(
            name: Self.skillName, path: Self.skillFileName, content: Self.markdown(descriptionSuffix: "after"))

        #expect(
            try fixture.text(of: Self.skillFileName, of: Self.skillName, in: .user)
                == Self.markdown(descriptionSuffix: "after"))
    }

    @Test func editWritesTheSkillFileInTheProjectLayerWithProject() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .project, descriptionSuffix: "before")

        _ = try fixture.writer.edit(
            name: Self.skillName, path: Self.skillFileName, content: Self.markdown(descriptionSuffix: "after"),
            layer: .project)

        #expect(
            try fixture.text(of: Self.skillFileName, of: Self.skillName, in: .project)
                == Self.markdown(descriptionSuffix: "after"))
    }

    @Test func editOfTheProjectLayerKeepsTheCopyOfTheUserLayer() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user, descriptionSuffix: "user copy")
        try fixture.writeSkill(Self.skillName, in: .project, descriptionSuffix: "project copy")

        _ = try fixture.writer.edit(
            name: Self.skillName, path: Self.skillFileName, content: Self.markdown(descriptionSuffix: "after"),
            layer: .project)

        #expect(
            try fixture.text(of: Self.skillFileName, of: Self.skillName, in: .user)
                == Self.markdown(descriptionSuffix: "user copy"))
    }

    @Test func editWritesAFileOfTheSkillThatIsNotTheSkillFile() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user)

        _ = try fixture.writer.edit(name: Self.skillName, path: Self.referencePath, content: Self.referenceText)

        #expect(try fixture.text(of: Self.referencePath, of: Self.skillName, in: .user) == Self.referenceText)
    }

    @Test func editGivesTheNameTheLayerAndThePathOfTheFile() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .project)

        let outcome = try fixture.writer.edit(
            name: Self.skillName, path: Self.referencePath, content: Self.referenceText, layer: .project)

        let expected = SkillWriteResult(
            name: Self.skillName, layer: .project,
            path: fixture.url(of: Self.referencePath, of: Self.skillName, in: .project).path)
        #expect(outcome == .success(expected))
    }

    @Test(arguments: SkillWriterTests.escapingPaths)
    func editRefusesAPathOutOfTheSkillFolder(path: String) throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user)

        let outcome = try fixture.writer.edit(name: Self.skillName, path: path, content: Self.referenceText)

        #expect(ResourceTestSupport.correctiveMessage(of: outcome) != nil)
    }

    @Test(arguments: SkillWriterTests.escapingPaths)
    func editOfAPathOutOfTheSkillFolderWritesNothing(path: String) throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user)
        let before = fixture.allFiles()

        _ = try fixture.writer.edit(name: Self.skillName, path: path, content: Self.referenceText)

        #expect(fixture.allFiles() == before)
    }

    @Test func editRefusesASkillThatIsOnlyInTheDefaultsLayerWithACorrectiveThatNamesTheLayer() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .defaults)

        let outcome = try fixture.writer.edit(
            name: Self.skillName, path: Self.skillFileName, content: Self.markdown(descriptionSuffix: "after"))

        #expect(ResourceTestSupport.correctiveMessage(of: outcome)?.contains("defaults") == true)
    }

    @Test func editOfASkillThatIsOnlyInAReadOnlyLayerTellsTheModelToUseAdd() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .defaults)

        let outcome = try fixture.writer.edit(
            name: Self.skillName, path: Self.skillFileName, content: Self.markdown(descriptionSuffix: "after"))

        #expect(ResourceTestSupport.correctiveMessage(of: outcome)?.contains("`add`") == true)
    }

    @Test func editRefusesASkillThatIsOnlyInAMarketplaceLayerWithACorrectiveThatNamesTheLayer() throws {
        let fixture = try WriterFixture(sources: [.marketplace, .user, .project])
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .marketplace)

        let outcome = try fixture.writer.edit(
            name: Self.skillName, path: Self.skillFileName, content: Self.markdown(descriptionSuffix: "after"))

        #expect(ResourceTestSupport.correctiveMessage(of: outcome)?.contains("marketplace") == true)
    }

    @Test func editOfASkillThatIsOnlyInAMarketplaceLayerWritesNothing() throws {
        let fixture = try WriterFixture(sources: [.marketplace, .user, .project])
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .marketplace)
        let before = fixture.allFiles()

        _ = try fixture.writer.edit(
            name: Self.skillName, path: Self.skillFileName, content: Self.markdown(descriptionSuffix: "after"))

        #expect(fixture.allFiles() == before)
    }

    /// The corrective names the other writable layer that holds the skill,
    /// thus the model can give that layer.
    @Test func editRefusesASkillThatIsOnlyInTheOtherWritableLayer() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .project)

        let outcome = try fixture.writer.edit(
            name: Self.skillName, path: Self.skillFileName, content: Self.markdown(descriptionSuffix: "after"))

        #expect(ResourceTestSupport.correctiveMessage(of: outcome)?.contains("project") == true)
    }

    @Test func editOfASkillThatIsOnlyInTheOtherWritableLayerWritesNothing() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .project)

        _ = try fixture.writer.edit(
            name: Self.skillName, path: Self.skillFileName, content: Self.markdown(descriptionSuffix: "after"))

        #expect(!fixture.folderExists(Self.skillName, in: .user))
    }

    @Test func editRefusesASkillFileThatTheValidatorWarnsAbout() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user, descriptionSuffix: "before")

        _ = try fixture.writer.edit(name: Self.skillName, path: Self.skillFileName, content: Self.noDescriptionMarkdown)

        #expect(
            try fixture.text(of: Self.skillFileName, of: Self.skillName, in: .user)
                == Self.markdown(descriptionSuffix: "before"))
    }

    @Test(arguments: SkillWriterTests.badNames)
    func editRefusesABadName(name: String) throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        let outcome = try fixture.writer.edit(name: name, path: Self.referencePath, content: Self.referenceText)

        #expect(ResourceTestSupport.correctiveMessage(of: outcome) != nil)
    }

    @Test func editOfALayerThatTheRegistryDoesNotHaveGivesACorrectiveThatNamesIt() throws {
        let fixture = try WriterFixture(sources: [.defaults, .user])
        defer { fixture.remove() }

        let outcome = try fixture.writer.edit(
            name: Self.skillName, path: Self.skillFileName, content: Self.markdown(), layer: .project)

        #expect(ResourceTestSupport.correctiveMessage(of: outcome)?.contains("project") == true)
    }

    @Test func editPutsTheChangeIntoMetadata() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user, descriptionSuffix: "before")
        fixture.registry.reload()

        _ = try fixture.writer.edit(
            name: Self.skillName, path: Self.skillFileName, content: Self.markdown(descriptionSuffix: "after"))

        #expect(Self.description(of: Self.skillName, in: fixture.registry)?.contains("after") == true)
    }

    @Test func editPublishesExactlyOneReload() async throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user, descriptionSuffix: "before")
        fixture.registry.reload()
        let tally = ReloadTestSupport.EventTally()
        let subscription = ReloadTestSupport.tally(fixture.registry.onReload, into: tally)
        defer { subscription.cancel() }

        _ = try fixture.writer.edit(
            name: Self.skillName, path: Self.skillFileName, content: Self.markdown(descriptionSuffix: "after"))

        await ReloadTestSupport.expectExactlyOneEvent(tally)
    }

    // MARK: - remove

    @Test func removeDeletesTheFolderInTheUserLayerByDefault() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user)

        _ = try fixture.writer.remove(name: Self.skillName)

        #expect(!fixture.folderExists(Self.skillName, in: .user))
    }

    @Test func removeDeletesTheFolderInTheProjectLayerWithProject() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .project)

        _ = try fixture.writer.remove(name: Self.skillName, layer: .project)

        #expect(!fixture.folderExists(Self.skillName, in: .project))
    }

    @Test func removeOfTheProjectLayerKeepsTheCopyOfTheUserLayer() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user)
        try fixture.writeSkill(Self.skillName, in: .project)

        _ = try fixture.writer.remove(name: Self.skillName, layer: .project)

        #expect(fixture.folderExists(Self.skillName, in: .user))
    }

    @Test func removeGivesTheNameTheLayerAndThePathOfTheFolder() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user)

        let outcome = try fixture.writer.remove(name: Self.skillName)

        let expected = SkillWriteResult(
            name: Self.skillName, layer: .user, path: fixture.folderURL(of: Self.skillName, in: .user).path)
        #expect(outcome == .success(expected))
    }

    @Test func removeRefusesAFolderThatIsNotInThatLayer() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        let outcome = try fixture.writer.remove(name: Self.skillName)

        #expect(ResourceTestSupport.correctiveMessage(of: outcome) != nil)
    }

    @Test func removeRefusesASkillThatIsOnlyInTheDefaultsLayerWithACorrectiveThatNamesTheLayer() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .defaults)

        let outcome = try fixture.writer.remove(name: Self.skillName)

        #expect(ResourceTestSupport.correctiveMessage(of: outcome)?.contains("defaults") == true)
    }

    @Test(arguments: SkillWriterTests.badNames)
    func removeRefusesABadName(name: String) throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }

        let outcome = try fixture.writer.remove(name: name)

        #expect(ResourceTestSupport.correctiveMessage(of: outcome) != nil)
    }

    /// A name of `.` names the layer root itself, thus a writer that did not
    /// check the name would remove the whole layer.
    @Test func removeOfTheNameDotKeepsTheLayerRoot() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user)

        _ = try fixture.writer.remove(name: ".")

        #expect(fixture.folderExists(Self.skillName, in: .user))
    }

    @Test func removeOfALayerThatTheRegistryDoesNotHaveGivesACorrectiveThatNamesIt() throws {
        let fixture = try WriterFixture(sources: [.defaults, .project])
        defer { fixture.remove() }

        let outcome = try fixture.writer.remove(name: Self.skillName)

        #expect(ResourceTestSupport.correctiveMessage(of: outcome)?.contains("user") == true)
    }

    @Test func removeTakesTheSkillOutOfMetadata() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user)
        fixture.registry.reload()

        _ = try fixture.writer.remove(name: Self.skillName)

        #expect(fixture.registry.metadata().isEmpty)
    }

    @Test func removePublishesExactlyOneReload() async throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .user)
        fixture.registry.reload()
        let tally = ReloadTestSupport.EventTally()
        let subscription = ReloadTestSupport.tally(fixture.registry.onReload, into: tally)
        defer { subscription.cancel() }

        _ = try fixture.writer.remove(name: Self.skillName)

        await ReloadTestSupport.expectExactlyOneEvent(tally)
    }

    // MARK: - The defaults layer is never written

    /// Each operation on a skill that the defaults layer also holds leaves
    /// the defaults folder byte for byte as it was.
    @Test func theDefaultsFolderIsUnchangedAfterEachOperation() throws {
        let fixture = try WriterFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(Self.skillName, in: .defaults, descriptionSuffix: "built in")
        let before = try fixture.contents(of: .defaults)

        _ = try fixture.writer.add(name: Self.skillName, skillMarkdown: Self.markdown(descriptionSuffix: "override"))
        #expect(try fixture.contents(of: .defaults) == before, "after add")

        _ = try fixture.writer.edit(name: Self.skillName, path: Self.referencePath, content: Self.referenceText)
        #expect(try fixture.contents(of: .defaults) == before, "after edit")

        _ = try fixture.writer.remove(name: Self.skillName)
        #expect(try fixture.contents(of: .defaults) == before, "after remove")
    }

    // MARK: - Helpers

    /// A valid skill file of `skillName`.
    ///
    /// - Parameter descriptionSuffix: Text at the end of the description, so
    ///   two versions of the file differ.
    /// - Returns: The text of the skill file.
    private static func markdown(descriptionSuffix: String = "") -> String {
        ReloadTestSupport.skillFileContents(id: skillName, descriptionSuffix: descriptionSuffix)
    }

    /// The description of the skill `id` in the metadata of `registry`.
    ///
    /// - Parameters:
    ///   - id: The skill id.
    ///   - registry: The registry to read.
    /// - Returns: The description, or `nil` when the metadata has no such
    ///   skill.
    private static func description(of id: String, in registry: SkillsRegistry) -> String? {
        registry.metadata().first { $0.id == id }?.description
    }
}

/// A stack of layer directories in temporary folders, a registry over the
/// stack, and a writer of that registry.
private struct WriterFixture {
    /// The source of each layer, lowest precedence first.
    let sources: [DotfolderStack.Source]

    /// The root of each layer, in the order of `sources`.
    let directories: [URL]

    /// The registry over the layers.
    let registry: SkillsRegistry

    /// The writer under test.
    var writer: SkillWriter { SkillWriter(registry: registry) }

    /// Makes one temporary folder for each source, and a registry over them.
    ///
    /// - Parameter sources: The source of each layer, lowest precedence
    ///   first. The default is a defaults, a user and a project layer.
    /// - Throws: Whatever `LayerFixtureSupport.makeLayerDirectories(count:)`
    ///   throws.
    init(sources: [DotfolderStack.Source] = [.defaults, .user, .project]) throws {
        self.sources = sources
        directories = try LayerFixtureSupport.makeLayerDirectories(count: sources.count)
        registry = SkillsRegistry(
            layers: zip(sources, directories).map { DotfolderStack.Layer(source: $0, root: $1) }, mode: .open)
    }

    /// Removes each layer folder.
    func remove() {
        LayerFixtureSupport.removeDirectories(directories)
    }

    /// The root of the layer of `source`.
    ///
    /// - Parameter source: The source of the layer.
    /// - Returns: The root of the first layer of that source.
    func root(of source: DotfolderStack.Source) -> URL {
        let index = sources.firstIndex(of: source) ?? sources.startIndex
        return directories[index]
    }

    /// The folder of the skill `name` in the layer of `source`.
    ///
    /// - Parameters:
    ///   - name: The skill name.
    ///   - source: The source of the layer.
    /// - Returns: The URL of the folder.
    func folderURL(of name: String, in source: DotfolderStack.Source) -> URL {
        root(of: source).appendingPathComponent(name, isDirectory: true)
    }

    /// The file `path` of the skill `name` in the layer of `source`.
    ///
    /// - Parameters:
    ///   - path: The path of the file, relative to the skill folder.
    ///   - name: The skill name.
    ///   - source: The source of the layer.
    /// - Returns: The URL of the file.
    func url(of path: String, of name: String, in source: DotfolderStack.Source) -> URL {
        folderURL(of: name, in: source).appendingPathComponent(path)
    }

    /// Writes a valid skill file of `name` in the layer of `source`.
    ///
    /// - Parameters:
    ///   - name: The skill name.
    ///   - source: The source of the layer.
    ///   - descriptionSuffix: Text at the end of the description.
    /// - Throws: Whatever `ReloadTestSupport.writeSkillFile` throws.
    func writeSkill(_ name: String, in source: DotfolderStack.Source, descriptionSuffix: String = "") throws {
        try ReloadTestSupport.writeSkillFile(id: name, in: root(of: source), descriptionSuffix: descriptionSuffix)
    }

    /// Whether the file `path` of the skill `name` is in the layer of
    /// `source`.
    ///
    /// - Parameters:
    ///   - path: The path of the file, relative to the skill folder.
    ///   - name: The skill name.
    ///   - source: The source of the layer.
    /// - Returns: `true` when the file exists.
    func fileExists(_ path: String, of name: String, in source: DotfolderStack.Source) -> Bool {
        FileManager.default.fileExists(atPath: url(of: path, of: name, in: source).path)
    }

    /// Whether the folder of the skill `name` is in the layer of `source`.
    ///
    /// - Parameters:
    ///   - name: The skill name.
    ///   - source: The source of the layer.
    /// - Returns: `true` when the folder exists.
    func folderExists(_ name: String, in source: DotfolderStack.Source) -> Bool {
        FileManager.default.fileExists(atPath: folderURL(of: name, in: source).path)
    }

    /// The text of the file `path` of the skill `name` in the layer of
    /// `source`.
    ///
    /// - Parameters:
    ///   - path: The path of the file, relative to the skill folder.
    ///   - name: The skill name.
    ///   - source: The source of the layer.
    /// - Returns: The text of the file.
    /// - Throws: Whatever `String(contentsOf:encoding:)` throws.
    func text(of path: String, of name: String, in source: DotfolderStack.Source) throws -> String {
        try String(contentsOf: url(of: path, of: name, in: source), encoding: .utf8)
    }

    /// Every file and folder below the layer of `source`, with the bytes of
    /// each file, by path relative to the layer root.
    ///
    /// - Parameter source: The source of the layer.
    /// - Returns: The bytes of each file; a folder maps to empty bytes.
    /// - Throws: Whatever `Data(contentsOf:)` throws.
    func contents(of source: DotfolderStack.Source) throws -> [String: Data] {
        let root = root(of: source)
        let paths = FileManager.default.subpaths(atPath: root.path) ?? []
        return try Dictionary(
            uniqueKeysWithValues: paths.map { path in (path, try Self.bytes(at: root.appendingPathComponent(path))) })
    }

    /// Every path below each layer root, each with the index of its layer in
    /// front, sorted.
    ///
    /// - Returns: The sorted paths.
    func allFiles() -> [String] {
        directories.enumerated().flatMap { index, root in
            (FileManager.default.subpaths(atPath: root.path) ?? []).map { "\(index)/\($0)" }
        }
        .sorted()
    }

    /// The bytes of the file at `url`, or empty bytes for a folder.
    ///
    /// - Parameter url: The file or folder.
    /// - Returns: The bytes.
    /// - Throws: Whatever `Data(contentsOf:)` throws.
    private static func bytes(at url: URL) throws -> Data {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue
        else { return Data() }
        return try Data(contentsOf: url)
    }
}
