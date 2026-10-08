import Foundation
import Testing

/// Guards the resolved dependency graph against the Router package that the
/// live-Router path pulled into this package.
///
/// This suite is a *live-resolution tripwire*, not a lockfile check.
/// `.gitignore` ignores `Package.resolved`, thus Git holds no copy of it and
/// there is no lockfile to read. SwiftPM resolves the graph before
/// `swift test` runs, thus the file is on disk when this test reads it, and
/// what the test reads is the graph that the current `main` of each sibling
/// gives today. A sibling that declares one of the denied packages again fails
/// this suite on the next run, with no local change.
///
/// The suite asserts a deny list, and never an allow list. Every sibling is
/// pinned to `branch: "main"`, thus an upstream package that adds a new and
/// harmless dependency would fail an allow-list assertion although nothing in
/// this package changed. A deny list names only the packages that must stay
/// out, thus the suite fails for the one reason it exists.
///
/// A second case guards the *prose*. The resolved graph and the text that
/// describes it are two different things, and a reader believes the text. Thus
/// ``namesNoRemovedRouterPackage()`` reads the shipped files and fails when one
/// of them still names the Router.
@Suite("Dependency graph")
struct DependencyGraphTests {
    /// The name of the removed Router package, spelled as prose and manifests
    /// spell it.
    ///
    /// ``removedIdentities`` lower-cases it, because SwiftPM writes a package
    /// identity in lower case. ``namesNoRemovedRouterPackage()`` reads it as it
    /// stands, because prose keeps the camel-case spelling. One constant serves
    /// both, thus the two guards can never name different packages.
    private static let removedPackageName = "FoundationModelsRouter"

    /// The package identities that the resolved graph must not hold.
    ///
    /// SwiftPM writes each identity in lower case, thus each entry is spelled
    /// that way. ``removedPackageName`` supplied the routing types, and it is
    /// the one denied package.
    ///
    /// The MLX packages (`mlx-swift`, `mlx-swift-lm`, `swift-huggingface`
    /// and `swift-transformers`) are deliberately absent from the list. The
    /// model pool of `FoundationModelsExtras` declares them, and
    /// `FoundationModelsMetadataRegistry` takes its `PooledEmbedder` from
    /// that pool. Thus they are expected in this graph.
    private static let removedIdentities: Set<String> = [
        removedPackageName.lowercased()
    ]

    /// What the prose walk reads, relative to the package root: the shipped
    /// sources, the package manifest, and the documentation. An entry may name
    /// a directory, which is read to its full depth, or one file.
    private static let prosePaths = [sourcesPath, manifestFileName, documentationPath]

    /// The resolution file, relative to the package root.
    private static let resolutionFileName = "Package.resolved"

    /// The sources folder, relative to the package root.
    private static let sourcesPath = "Sources"

    /// The package manifest, relative to the package root.
    private static let manifestFileName = "Package.swift"

    /// The git package that the marketplace code of this package used, which
    /// the `Marketplace` product of `FoundationModelsExtras` owns now.
    ///
    /// This package declares no git package of its own now. The `Marketplace`
    /// product links libgit2, thus the library reaches libgit2 through that
    /// product and through no entry of this manifest.
    private static let removedGitPackageName = "swift-libgit2"

    /// The product that gives this package the marketplace types, as the
    /// manifest declares it.
    ///
    /// The whole declaration is the marker, and not the name alone: the word
    /// `Marketplace` stands in many a comment of the manifest, thus a check
    /// for the name alone would pass on prose.
    private static let marketplaceProductDeclaration =
        #".product(name: "Marketplace", package: "FoundationModelsExtras")"#

    /// The C module of the removed git package, as an import line spells it.
    private static let removedGitModuleImport = "import libgit2"

    /// The marketplace types that `FoundationModelsExtras` owns now, thus no
    /// file of this package may declare one of them again.
    ///
    /// A call of such a type is right and stays: the CLI of this package
    /// builds a `MarketplaceStore` and reads a `MarketplaceConfig`. Only a
    /// declaration is the defect, because a second declaration of one name
    /// makes every use of that name ambiguous.
    private static let extrasOwnedTypeNames = [
        "CatalogResolver",
        "GitTransport",
        "MarketplaceCache",
        "MarketplaceConfig",
        "MarketplaceStore",
        "SnapshotWriter",
    ]

    /// The keywords that open a type declaration in Swift.
    private static let typeDeclarationKeywords = [
        "actor", "class", "enum", "extension", "protocol", "struct",
    ]

    /// The test folder, relative to the package root.
    private static let testsPath = "Tests"

    /// The example folder, relative to the package root.
    private static let examplesPath = "Examples"

    /// What the fixture walk reads, relative to the package root: the shipped
    /// sources, the tests, and the examples. The documentation stands outside
    /// it, because a document of this package may still tell a reader where
    /// the catalog fixtures live now.
    private static let fixtureWalkPaths = [sourcesPath, testsPath, examplesPath]

    /// The name of the deleted catalog-fixture folder under `Examples/`.
    ///
    /// The name joins from two parts when the case runs. The walk below reads
    /// `Tests/`, thus one whole literal here would make this file report
    /// itself, and a walk that can never come back empty proves nothing. The
    /// join keeps the whole name off every line of every file, thus the walk
    /// needs no exception for its own suite.
    private static let deletedFixtureFolderName = "marketplace" + "-fixtures"

    /// The opening text of a call of the deleted fixture helper, joined from
    /// two parts for the reason ``deletedFixtureFolderName`` states.
    private static let deletedFixtureHelperCall = "marketplaceCatalog" + "("

    /// Each name of the deleted catalog fixtures that no file may hold now.
    private static let deletedFixtureNames = [
        deletedFixtureFolderName, deletedFixtureHelperCall,
    ]

    /// The documentation directory, relative to the package root.
    private static let documentationPath = "docs"

    /// The retired repository that once held the `Operations` and
    /// `OperationsCLI` modules.
    ///
    /// `FoundationModelsExtras` holds both modules since 2026-08-29, and
    /// `Package.swift` says the repository is retired.
    private static let retiredOperationsRepository = "FoundationModelsOperationTool"

    /// The word that makes a mention of ``retiredOperationsRepository``
    /// history instead of a claim about today.
    private static let retirementMarker = "retired"

    /// The README, relative to the package root.
    private static let readmeFileName = "README.md"

    /// The test file that holds the compiled copy of the README usage block,
    /// relative to the package root.
    ///
    /// That file imports only `FoundationModels`, `FoundationModelsSkills`
    /// and `Testing`. Its short import list is the compile guard itself, thus
    /// the equality case lives here, where `Foundation` is already imported,
    /// and never there.
    private static let usageBlockCopyPath =
        "Tests/FoundationModelsSkillsTests/ReadmeExampleTests.swift"

    /// The line that opens the README's first Swift code fence.
    private static let swiftFenceOpen = "```swift"

    /// The line that closes a Markdown code fence.
    private static let fenceClose = "```"

    /// The comment that stands above the compiled copy of the usage block.
    private static let usageBlockStartMarker = "// The README usage block starts here."

    /// The comment that stands below the compiled copy of the usage block.
    private static let usageBlockEndMarker = "// The README usage block ends here."

    /// The prefix of an import line, which the README block carries and the
    /// compiled copy does not, because a Swift file imports at its top.
    private static let importLinePrefix = "import "

    @Test("Package.resolved does not hold the Router package")
    func resolvesNoRouterPackage() throws {
        let found = try Self.resolvedIdentities().intersection(Self.removedIdentities).sorted()
        #expect(
            found.isEmpty,
            """
            Package.resolved must not hold the Router package -- nothing in this package \
            resolves a live Router any more; found: \(found)
            """
        )
    }

    /// Proves that no shipped file names the removed Router package.
    ///
    /// `Package.resolved` says what the resolver does. This case says what the
    /// package *claims*, because a reader believes the prose. While the Router
    /// was in the graph, the manifest and the documentation gave it as the
    /// reason for the macOS 27 floor and for the absence of iOS support. Both
    /// reasons are different now, thus no shipped file may name the Router.
    ///
    /// The walk reads ``prosePaths``, and nothing else. `Tests/` is
    /// deliberately outside it, because `Tests/` may name the Router in a
    /// disclosure note. This suite does so in the comments above. A walk over
    /// `Tests/` would report those notes, and would report itself.
    @Test("no source, manifest, or documentation file names the removed Router package")
    func namesNoRemovedRouterPackage() {
        let root = FixtureLibrary.packageRoot()
        let offenders = Self.prosePaths.flatMap {
            Self.linesNaming(
                Self.removedPackageName, under: root.appendingPathComponent($0), in: root)
        }
        #expect(
            offenders.isEmpty,
            """
            No file under Sources/ or docs/, and not Package.swift, may name \
            \(Self.removedPackageName): nothing in this package depends on it any more, thus the \
            macOS 27 floor and the iOS posture both have another reason now; found: \
            \(offenders.joined(separator: ", "))
            """
        )
    }

    /// Proves that the manifest takes the marketplace from
    /// `FoundationModelsExtras`, and links no git package of its own.
    ///
    /// The marketplace implementation lives in the `Marketplace` product of
    /// `FoundationModelsExtras` now. Thus the manifest must name that product,
    /// and it must name `swift-libgit2` no more: the `Marketplace` product
    /// links libgit2 itself, thus no entry of this manifest names a git
    /// package.
    @Test("the manifest names the Marketplace product and no git package")
    func manifestTakesTheMarketplaceFromExtras() throws {
        let manifest = try FixtureLibrary.readText(relativePath: Self.manifestFileName)
        #expect(
            !manifest.contains(Self.removedGitPackageName),
            """
            Package.swift must not name \(Self.removedGitPackageName): the marketplace, and with \
            it every git call, belongs to the Marketplace product of FoundationModelsExtras now.
            """
        )
        #expect(
            manifest.contains(Self.marketplaceProductDeclaration),
            """
            Package.swift must declare \(Self.marketplaceProductDeclaration): that product gives \
            this package MarketplaceStore, MarketplaceSource and the rest of the marketplace \
            types.
            """
        )
    }

    /// Proves that no file under `Sources/` declares a marketplace type that
    /// `FoundationModelsExtras` owns, and that none imports libgit2.
    ///
    /// `SeamReexports.swift` re-exports the `Marketplace` module, thus every
    /// name of that module is visible here under its own spelling. A second
    /// declaration of one of those names would make each use of the name
    /// ambiguous, and a reader could not tell the two apart.
    @Test("no source file declares a marketplace type of FoundationModelsExtras")
    func declaresNoMarketplaceTypeOfExtras() {
        let root = FixtureLibrary.packageRoot()
        let sources = root.appendingPathComponent(Self.sourcesPath)
        let offenders = Self.extrasOwnedTypeNames.flatMap { name in
            Self.linesNaming(name, under: sources, in: root, where: { Self.declares(name, $0) })
        }
        #expect(
            offenders.isEmpty,
            """
            No file under Sources/ may declare one of \
            \(Self.extrasOwnedTypeNames.joined(separator: ", ")): the Marketplace product of \
            FoundationModelsExtras owns each of them, and SeamReexports.swift makes each name \
            visible here; found: \(offenders.joined(separator: ", "))
            """
        )
        let gitImports = Self.linesNaming(Self.removedGitModuleImport, under: sources, in: root)
        #expect(
            gitImports.isEmpty,
            """
            No file under Sources/ may write "\(Self.removedGitModuleImport)": every git call of \
            the marketplace belongs to the Marketplace product of FoundationModelsExtras, thus no \
            file of this package calls libgit2; found: \(gitImports.joined(separator: ", "))
            """
        )
    }

    /// Whether one line opens the declaration of a type of one name.
    ///
    /// The reading is by keyword: a line that holds `struct <name>`, or one of
    /// the other five keywords before the name, declares that type. A line
    /// that only calls the type, or that names it in prose, holds no such
    /// keyword.
    ///
    /// - Parameters:
    ///   - name: The type name to look for.
    ///   - line: The line to read.
    /// - Returns: `true` when the line declares a type of that name.
    private static func declares(_ name: String, _ line: String) -> Bool {
        typeDeclarationKeywords.contains { line.contains("\($0) \(name)") }
    }

    /// Proves that the catalog fixtures of the marketplace are gone from this
    /// package.
    ///
    /// The `Marketplace` product of `FoundationModelsExtras` owns the
    /// marketplace, and it holds its own copy of the catalog fixtures. No
    /// test of this package reads a catalog now. A folder that stays behind
    /// reads to the next author as a fixture that some suite still needs, and
    /// it would grow stale beside the copy that the tests really read.
    @Test("the marketplace catalog fixtures are gone from Examples/")
    func holdsNoMarketplaceCatalogFixtures() {
        let folder = FixtureLibrary.packageRoot()
            .appendingPathComponent(Self.examplesPath, isDirectory: true)
            .appendingPathComponent(Self.deletedFixtureFolderName, isDirectory: true)
        #expect(
            !FileManager.default.fileExists(atPath: folder.path),
            """
            \(Self.examplesPath)/\(Self.deletedFixtureFolderName)/ must be gone: the Marketplace \
            product of FoundationModelsExtras holds the catalog fixtures now, and no test of this \
            package reads them.
            """
        )
    }

    /// Proves that no file of this package names the deleted catalog fixtures
    /// or the fixture helper that read them.
    ///
    /// The case above reads the folder, and this one reads the text. A path
    /// that names a folder which is gone fails only when a test runs it, thus
    /// such a path can stand for a long time unread. The walk finds it at
    /// once.
    ///
    /// The walk reads `Tests/` as well, which the Router walk above cannot
    /// do. Nothing keeps a disclosure note about the catalog fixtures, thus
    /// there is no note to pass over, and the two names join from parts at
    /// run time thus this file holds neither of them whole.
    @Test("no file under Sources, Tests or Examples names the deleted marketplace fixtures")
    func namesNoDeletedMarketplaceFixture() {
        let root = FixtureLibrary.packageRoot()
        let offenders = Self.fixtureWalkPaths.flatMap { path in
            Self.deletedFixtureNames.flatMap {
                Self.linesNaming($0, under: root.appendingPathComponent(path), in: root)
            }
        }
        #expect(
            offenders.isEmpty,
            """
            No file under \(Self.fixtureWalkPaths.joined(separator: "/, "))/ may name \
            \(Self.deletedFixtureFolderName) or \(Self.deletedFixtureHelperCall): the catalog \
            fixtures and the helper that read them are deleted, and the Marketplace product of \
            FoundationModelsExtras holds its own copy of the fixtures; found: \
            \(offenders.joined(separator: ", "))
            """
        )
    }

    /// Proves that no documentation line gives the retired operation-tool
    /// repository as a dependency that exists now.
    ///
    /// `Package.swift` says the repository is retired, and the `Operations`
    /// and `OperationsCLI` modules resolve from `FoundationModelsExtras`. A
    /// documentation sentence in the present tense disagrees with the
    /// manifest, and a reader believes the documentation.
    ///
    /// History stays. One word tells the two kinds of sentence apart: a line
    /// may name the repository when the same line also names its retirement.
    /// Thus a sentence that records what happened passes, and a sentence that
    /// gives the repository as a live dependency fails. This is a rule about
    /// one line, not about the file, thus a new present-tense sentence
    /// somewhere else in `docs/` fails even while the historical note stands.
    ///
    /// One consequence for a writer: keep the name and the word "retired" on
    /// the SAME line. A sentence that wraps between the two fails, because
    /// the line that holds the name then holds no retirement word. That is
    /// the price of the per-line rule, and the failure message says what to
    /// do.
    @Test("no documentation line gives the retired operation-tool repository as a current dependency")
    func namesNoRetiredOperationsRepositoryAsCurrent() {
        let root = FixtureLibrary.packageRoot()
        let offenders = Self.linesNaming(
            Self.retiredOperationsRepository,
            under: root.appendingPathComponent(Self.documentationPath),
            in: root,
            where: { !$0.contains(Self.retirementMarker) })
        #expect(
            offenders.isEmpty,
            """
            No line under docs/ may name \(Self.retiredOperationsRepository) without also naming \
            its retirement: that repository is retired, and the Operations and OperationsCLI \
            modules come from FoundationModelsExtras now. Write the sentence in the past tense, \
            or name FoundationModelsExtras instead; found: \(offenders.joined(separator: ", "))
            """
        )
    }

    /// Proves that the README usage block and the copy the test target
    /// compiles are the same text.
    ///
    /// `ReadmeExampleTests` holds a copy of the block, thus the block is
    /// known to compile. That alone does not keep the two equal: an edit to
    /// `README.md` alone leaves the suite green, because the compiled copy
    /// still compiles. A reader would then copy code that nothing checks.
    ///
    /// This case closes that gap. It reads the README's first Swift fence and
    /// the lines between the two markers in the test file, and compares them.
    /// Together the two cases give the whole promise: the block compiles, and
    /// the block a reader sees is the block that compiled.
    ///
    /// The two copies differ in two ways that carry no meaning, thus the
    /// comparison removes both: the README block opens with its `import`
    /// lines, which a Swift file writes at its top instead, and the compiled
    /// copy is indented, because it sits inside a function.
    @Test("the README usage block and the copy the tests compile are the same text")
    func readmeUsageBlockMatchesItsCompiledCopy() throws {
        let published = try Self.readmeUsageBlock()
        let compiled = try Self.compiledUsageBlockCopy()
        #expect(
            published == compiled,
            """
            The README usage block and the copy in \(Self.usageBlockCopyPath) must be the same \
            text. One of the two changed alone. Make the same edit in both, thus the block a \
            reader copies stays the block the test target compiles.

            README:
            \(published)

            compiled copy:
            \(compiled)
            """
        )
    }

    /// Reads the README's first Swift code fence, without its `import` lines.
    ///
    /// - Returns: The block, one line for each line of the fence.
    /// - Throws: ``MissingBlockError`` when the README holds no Swift fence,
    ///   or an error when the README cannot be read. An absent block is a
    ///   failure, and never an empty string: two empty strings are equal, and
    ///   a case that compared them would prove nothing.
    private static func readmeUsageBlock() throws -> String {
        let readme = try FixtureLibrary.readText(relativePath: Self.readmeFileName)
        let lines = readme.components(separatedBy: .newlines)
        guard let open = lines.firstIndex(where: { $0.hasPrefix(Self.swiftFenceOpen) }) else {
            throw MissingBlockError(what: "a \(Self.swiftFenceOpen) fence", file: Self.readmeFileName)
        }
        let body = lines[lines.index(after: open)...]
        let close = body.firstIndex { $0.hasPrefix(Self.fenceClose) } ?? body.endIndex
        return Self.dedented(body[..<close].filter { !$0.hasPrefix(Self.importLinePrefix) })
    }

    /// Reads the copy of the usage block that the test target compiles.
    ///
    /// The copy sits between ``usageBlockStartMarker`` and
    /// ``usageBlockEndMarker`` inside a test function, thus the marker lines
    /// themselves are left out and the body is dedented.
    ///
    /// - Returns: The copy, one line for each line between the markers.
    /// - Throws: ``MissingBlockError`` when either marker is absent, or an
    ///   error when the file cannot be read.
    private static func compiledUsageBlockCopy() throws -> String {
        let lines = try FixtureLibrary.readText(relativePath: Self.usageBlockCopyPath)
            .components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.contains(Self.usageBlockStartMarker) }) else {
            throw MissingBlockError(what: "the start marker", file: Self.usageBlockCopyPath)
        }
        let body = lines[lines.index(after: start)...]
        guard let end = body.firstIndex(where: { $0.contains(Self.usageBlockEndMarker) }) else {
            throw MissingBlockError(what: "the end marker", file: Self.usageBlockCopyPath)
        }
        return Self.dedented(body[..<end])
    }

    /// Removes the indent that every line of `lines` shares, and the blank
    /// lines at each end.
    ///
    /// One copy of the block sits inside a function and the other sits in a
    /// Markdown fence, thus the two carry different indents. The indent is
    /// the only difference that carries no meaning, thus it comes off before
    /// the comparison. A blank line inside the block keeps its place.
    ///
    /// - Parameter lines: The lines to align.
    /// - Returns: The lines, joined by a newline.
    private static func dedented(_ lines: some Sequence<String>) -> String {
        var kept = Array(lines)
        while kept.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { kept.removeFirst() }
        while kept.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { kept.removeLast() }
        let indents = kept
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix { $0 == " " }.count }
        let common = indents.min() ?? 0
        return kept.map { String($0.dropFirst(min(common, $0.prefix { $0 == " " }.count))) }
            .joined(separator: "\n")
    }

    /// Thrown when a block this suite compares is absent.
    private struct MissingBlockError: Error, CustomStringConvertible {
        /// What the reader looked for.
        let what: String

        /// The file it looked in, relative to the package root.
        let file: String

        /// Names what is absent and where, thus the failure says what to fix.
        var description: String {
            "\(file) holds no \(what), thus the two copies cannot be compared."
        }
    }

    /// Reads every line at or under `base` that holds `name`.
    ///
    /// A file that does not decode as UTF-8 text is passed over, because no
    /// such file carries prose.
    ///
    /// - Parameters:
    ///   - name: The string that no line may hold.
    ///   - base: The file or directory to read.
    ///   - root: The package root, which each reported path is relative to.
    ///   - isOffending: Which of the lines that hold `name` to report. The
    ///     default reports every one of them. A caller that permits `name` in
    ///     one kind of sentence gives a test that rejects the other kind.
    /// - Returns: One `<path>:<line>` entry for each reported line.
    ///   `enumerated()` counts from zero and an editor counts from one, thus
    ///   each reported line number is one more than the offset.
    private static func linesNaming(
        _ name: String,
        under base: URL,
        in root: URL,
        where isOffending: (String) -> Bool = { _ in true }
    ) -> [String] {
        var offenders: [String] = []
        for file in Self.files(under: base) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (offset, line) in text.components(separatedBy: .newlines).enumerated()
            where line.contains(name) && isOffending(line) {
                offenders.append("\(Self.path(of: file, in: root)):\(offset + 1)")
            }
        }
        return offenders
    }

    /// Lists every regular file at or under `base`.
    ///
    /// - Parameter base: One file, which stands for itself, or a directory,
    ///   which is read to its full depth.
    /// - Returns: The regular files found. An absent or unreadable `base`
    ///   gives none, and is recorded as an issue, because a walk that reads
    ///   nothing proves nothing.
    private static func files(under base: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory) else {
            Issue.record("\(base.path) is absent, thus the walk cannot read it.")
            return []
        }
        guard isDirectory.boolValue else { return [base] }
        guard
            let walk = FileManager.default.enumerator(
                at: base, includingPropertiesForKeys: [.isRegularFileKey])
        else {
            Issue.record("Cannot walk \(base.path).")
            return []
        }
        return walk.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    /// Spells `file` relative to the package root, thus a failure message
    /// names a path that a reader can open.
    ///
    /// - Parameters:
    ///   - file: The file to spell.
    ///   - root: The package root.
    /// - Returns: The path of `file` relative to `root`, or the full path when
    ///   `file` does not lie under `root`.
    private static func path(of file: URL, in root: URL) -> String {
        let prefix = root.path + "/"
        guard file.path.hasPrefix(prefix) else { return file.path }
        return String(file.path.dropFirst(prefix.count))
    }

    /// Reads the identity of every pin in `Package.resolved`.
    ///
    /// An absent file makes `Data(contentsOf:)` throw, thus the test fails.
    /// The read is deliberately unguarded: a guard could only turn that
    /// failure into a skip, and a tripwire that skips itself rots.
    ///
    /// - Returns: the identity of each resolved package.
    /// - Throws: an error when `Package.resolved` cannot be read or decoded.
    private static func resolvedIdentities() throws -> Set<String> {
        let file = FixtureLibrary.packageRoot().appendingPathComponent(Self.resolutionFileName)
        let contents = try Data(contentsOf: file)
        let resolution = try JSONDecoder().decode(Resolution.self, from: contents)
        return Set(resolution.pins.map(\.identity))
    }

    /// The part of the `Package.resolved` JSON this suite reads.
    private struct Resolution: Decodable {
        /// One resolved package.
        struct Pin: Decodable {
            /// The package identity SwiftPM resolved, in lower case.
            let identity: String
        }

        /// Every resolved package, in the order the file holds them.
        let pins: [Pin]
    }
}
