import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsSkills

/// Proves the `marketplace` command group of the CLI (marketplace.md §9.2 and
/// §9.3).
///
/// Every case runs over a `GitFixtureRepository` that a `file://` URL names, a
/// temporary cache folder, and a temporary configuration stack. Thus no case
/// reaches the network, no case starts the `git` binary, and no case reads the
/// real home folder.
@Suite("Marketplace CLI")
struct MarketplaceCLITests {
    /// The alias that most cases give the fixture marketplace.
    private static let alias = "team"

    /// The body of the one skill of the fixture commit.
    private static let skillBody = "alpha body"

    // MARK: - add

    @Test func addWritesTheSourceToTheUserFile() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()

        let result = await fixture.run(["add", repository.url, "--alias", Self.alias])

        #expect(result.exitCode == 0)
        let saved = try MarketplaceConfig.load(from: fixture.stack, includeProject: false)
        #expect(saved.marketplaces == [MarketplaceSource(repository.url, alias: Self.alias)])
    }

    @Test func addKeepsTheEarlierSourcesAndPutsTheNewOneLast() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let first = try GitFixtureRepository()
        let second = try GitFixtureRepository()

        _ = await fixture.run(["add", first.url, "--alias", "first"])
        let result = await fixture.run(["add", second.url, "--alias", "second", "--ref", "main"])

        #expect(result.exitCode == 0)
        let saved = try MarketplaceConfig.load(from: fixture.stack, includeProject: false)
        #expect(
            saved.marketplaces == [
                MarketplaceSource(first.url, alias: "first"),
                MarketplaceSource(second.url, ref: "main", alias: "second"),
            ])
    }

    @Test func addRefusesAURLThatCarriesACredential() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let secret = "s3cret-token"

        let result = await fixture.run(["add", "https://user:\(secret)@example.invalid/skills.git"])

        #expect(result.exitCode != 0)
        #expect(!result.output.contains(secret))
        #expect(!FileManager.default.fileExists(atPath: fixture.userFile.path))
    }

    @Test func addRefusesASecondSourceWithTheSamePreFetchKey() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        _ = await fixture.run(["add", repository.url, "--alias", Self.alias])

        let result = await fixture.run(["add", repository.url, "--alias", Self.alias])

        #expect(result.exitCode != 0)
        let saved = try MarketplaceConfig.load(from: fixture.stack, includeProject: false)
        #expect(saved.marketplaces.count == 1)
    }

    // MARK: - remove

    @Test func removeTakesTheSourceOutOfTheUserFile() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        _ = await fixture.run(["add", repository.url, "--alias", Self.alias])

        let result = await fixture.run(["remove", Self.alias])

        #expect(result.exitCode == 0)
        let saved = try MarketplaceConfig.load(from: fixture.stack, includeProject: false)
        #expect(saved.marketplaces.isEmpty)
    }

    @Test func removeWithAnUnknownIDGivesANonZeroExit() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }

        let result = await fixture.run(["remove", "nothing-here"])

        #expect(result.exitCode != 0)
        #expect(result.output.contains("nothing-here"))
    }

    // MARK: - list

    @Test func listNamesEachSourceAndSaysThatNothingIsInstalledYet() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        _ = await fixture.run(["add", repository.url, "--alias", Self.alias])

        let result = await fixture.run(["list"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains(Self.alias))
        #expect(result.output.contains(MarketplaceRow.notInstalledStatus))
    }

    @Test func listShowsTheCommitOfTheInstalledSnapshot() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        let sha = try repository.commit(files: MarketplaceTestSupport.skillTree(body: Self.skillBody))
        _ = await fixture.run(["add", repository.url, "--alias", Self.alias])
        _ = await fixture.run(["update"])

        let result = await fixture.run(["list"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains(sha))
    }

    @Test func listReadsTheProjectFileOnlyWithTheIncludeProjectFlag() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        let projectAlias = "from-project"
        try MarketplaceTestSupport.writeFile(
            text: """
                marketplaces:
                  - url: \(repository.url)
                    alias: \(projectAlias)
                """,
            to: fixture.projectFile)

        let withoutFlag = await fixture.run(["list"])
        let withFlag = await fixture.run(["list", "--include-project"])

        #expect(!withoutFlag.output.contains(projectAlias))
        #expect(withFlag.output.contains(projectAlias))
    }

    // MARK: - check

    @Test func checkReportsTheRemoteHeadAndDownloadsNothing() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        let sha = try repository.commit(files: MarketplaceTestSupport.skillTree(body: Self.skillBody))
        _ = await fixture.run(["add", repository.url, "--alias", Self.alias])

        let result = await fixture.run(["check"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains(sha))
        let installed = try MarketplaceConfig.load(from: fixture.stack, includeProject: false)
        #expect(installed.marketplaces.count == 1)
        #expect(!fixture.cacheHoldsASnapshot)
    }

    @Test func checkWithAnUnknownIDGivesANonZeroExit() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        try repository.commit(files: MarketplaceTestSupport.skillTree(body: Self.skillBody))
        _ = await fixture.run(["add", repository.url, "--alias", Self.alias])

        let result = await fixture.run(["check", "nothing-here"])

        #expect(result.exitCode != 0)
        #expect(result.output.contains("nothing-here"))
    }

    // MARK: - update

    @Test func updateInstallsTheRemoteHead() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        let sha = try repository.commit(files: MarketplaceTestSupport.skillTree(body: Self.skillBody))
        _ = await fixture.run(["add", repository.url, "--alias", Self.alias])

        let result = await fixture.run(["update", Self.alias])

        #expect(result.exitCode == 0)
        #expect(result.output.contains(sha))
        #expect(fixture.cacheHoldsASnapshot)
    }

    @Test func updateWithForceInstallsTheSameCommitAgain() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        let sha = try repository.commit(files: MarketplaceTestSupport.skillTree(body: Self.skillBody))
        _ = await fixture.run(["add", repository.url, "--alias", Self.alias])
        _ = await fixture.run(["update"])

        let withoutForce = await fixture.run(["update"])
        let withForce = await fixture.run(["update", "--force"])

        #expect(!withoutForce.output.contains(sha))
        #expect(withForce.output.contains(sha))
    }

    @Test func updateWithAnUnknownIDGivesANonZeroExit() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        try repository.commit(files: MarketplaceTestSupport.skillTree(body: Self.skillBody))
        _ = await fixture.run(["add", repository.url, "--alias", Self.alias])

        let result = await fixture.run(["update", "nothing-here"])

        #expect(result.exitCode != 0)
        #expect(result.output.contains("nothing-here"))
    }

    // MARK: - pin and unpin

    @Test func pinHoldsTheCommitAndListSaysSo() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        let sha = try repository.commit(files: MarketplaceTestSupport.skillTree(body: Self.skillBody))
        _ = await fixture.run(["add", repository.url, "--alias", Self.alias])
        _ = await fixture.run(["update"])

        let pinned = await fixture.run(["pin", Self.alias, sha])
        let listed = await fixture.run(["list"])

        #expect(pinned.exitCode == 0)
        #expect(listed.output.contains(MarketplaceRow.pinnedStatus))
    }

    @Test func unpinDropsThePinAndListSaysSo() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        let sha = try repository.commit(files: MarketplaceTestSupport.skillTree(body: Self.skillBody))
        _ = await fixture.run(["add", repository.url, "--alias", Self.alias])
        _ = await fixture.run(["update"])
        _ = await fixture.run(["pin", Self.alias, sha])

        let unpinned = await fixture.run(["unpin", Self.alias])
        let listed = await fixture.run(["list"])

        #expect(unpinned.exitCode == 0)
        #expect(!listed.output.contains(MarketplaceRow.pinnedStatus))
    }

    @Test func pinWithAnUnknownIDGivesANonZeroExit() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }
        let repository = try GitFixtureRepository()
        let sha = try repository.commit(files: MarketplaceTestSupport.skillTree(body: Self.skillBody))
        _ = await fixture.run(["add", repository.url, "--alias", Self.alias])

        let result = await fixture.run(["pin", "nothing-here", sha])

        #expect(result.exitCode != 0)
        #expect(result.output.contains("nothing-here"))
    }

    // MARK: - The group next to the driver tree

    @Test func theGroupRunsOnlyWhenTheArgumentsNameIt() async throws {
        let fixture = try MarketplaceCLIFixture()
        defer { fixture.remove() }

        let named = await SkillsCLI.runMarketplace(
            arguments: [SkillsCLI.marketplaceCommandName, "list"], context: fixture.context)
        let notNamed = await SkillsCLI.runMarketplace(
            arguments: ["skill", "list"], context: fixture.context)

        #expect(named?.exitCode == 0)
        #expect(notNamed == nil)
    }
}

/// A temporary configuration stack, a temporary cache folder, and one call
/// that runs the `marketplace` group over both.
///
/// The fixture removes the folder that it made when a case releases it, thus a
/// case leaves nothing behind.
private struct MarketplaceCLIFixture {
    /// The dotfolder name of the test stack.
    private static let stackName = "skills"

    /// The name of the folder of the stack that holds the user layer.
    private static let userDirectoryName = "user"

    /// The name of the folder that holds the working directory of the stack.
    private static let projectDirectoryName = "project"

    /// The name of the folder that holds the marketplace cache.
    private static let cacheDirectoryName = "cache"

    /// The temporary folder that holds every other folder of the fixture.
    let root: URL

    /// The context that every run of the fixture uses.
    let context: MarketplaceCLIContext

    /// The dotfolder stack that holds `marketplaces.yaml`.
    var stack: DotfolderStack {
        context.stack
    }

    /// The `marketplaces.yaml` path of the user layer.
    let userFile: URL

    /// The `marketplaces.yaml` path of the project layer.
    let projectFile: URL

    /// The cache folder of the fixture.
    private let cacheDirectory: URL

    /// Makes the temporary folders and the context. No layer holds a file yet.
    ///
    /// - Throws: The error of a folder write, or of a missing stack layer.
    init() throws {
        root = try MarketplaceTestSupport.makeTempDirectory()
        cacheDirectory = root.appendingPathComponent(Self.cacheDirectoryName, isDirectory: true)
        let stack = DotfolderStack(
            name: Self.stackName,
            workingDirectory: root.appendingPathComponent(Self.projectDirectoryName, isDirectory: true),
            userDirectory: root.appendingPathComponent(Self.userDirectoryName, isDirectory: true),
            environment: [:])
        context = MarketplaceCLIContext(
            stack: stack, environment: [MarketplaceCache.cacheVariable: cacheDirectory.path])
        userFile = try #require(stack.layers.first { $0.source == .user })
            .root.appendingPathComponent(MarketplaceConfig.fileName)
        projectFile = try #require(stack.layers.first { $0.source == .project })
            .root.appendingPathComponent(MarketplaceConfig.fileName)
    }

    /// Whether the cache folder holds at least one installed snapshot.
    var cacheHoldsASnapshot: Bool {
        let state = try? MarketplaceState.load(
            from: MarketplaceCache.stateFile(inCacheDirectory: cacheDirectory))
        return state?.marketplaces.values.contains { $0.currentSha != nil } == true
    }

    /// Runs the `marketplace` group over the folders of the fixture.
    ///
    /// - Parameter arguments: The arguments after the group name.
    /// - Returns: What the run gave.
    func run(_ arguments: [String]) async -> MarketplaceCLIResult {
        await MarketplaceCLI.run(arguments: arguments, context: context)
    }

    /// Removes the temporary folder and everything in it.
    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
