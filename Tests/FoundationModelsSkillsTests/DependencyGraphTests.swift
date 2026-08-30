import Foundation
import Testing

/// Guards the resolved dependency graph against the packages the live-Router
/// path pulled into this package.
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
///
/// Two more cases guard `plan.md`, which that walk deliberately passes over.
/// The walk cannot read the decision record, because the record keeps the
/// Router in the decisions that named it when they were taken. Thus
/// ``planRecordsTheRouterFreeDecision()`` and
/// ``apiSketchShowsTheInjectedSessionFactory()`` read the record themselves,
/// and pin what it must say now.
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

    /// The package identities the live-Router path pulled in, which the
    /// resolved graph must no longer hold.
    ///
    /// SwiftPM writes each identity in lower case, thus each entry is spelled
    /// that way. ``removedPackageName`` supplied the routing types.
    /// `mlx-swift`, `mlx-swift-lm`, `swift-huggingface`, and
    /// `swift-transformers` supplied the live model loader below it.
    ///
    /// `swift-jinja` is deliberately absent from the list. The sibling
    /// manifest kept that pin to hold `swift-transformers` away from a release
    /// it cannot compile against, and only a sibling *test* target linked it.
    /// Whether SwiftPM prunes such a pin from this package's graph is the
    /// resolver's business, not this package's contract, thus this suite makes
    /// no claim about it.
    private static let removedIdentities: Set<String> = [
        removedPackageName.lowercased(),
        "mlx-swift",
        "mlx-swift-lm",
        "swift-huggingface",
        "swift-transformers",
    ]

    /// What the prose walk reads, relative to the package root: the shipped
    /// sources, the package manifest, and the documentation. An entry may name
    /// a directory, which is read to its full depth, or one file.
    private static let prosePaths = ["Sources", "Package.swift", "docs"]

    /// The resolution file, relative to the package root.
    private static let resolutionFileName = "Package.resolved"

    /// The decision record, relative to the package root.
    ///
    /// ``prosePaths`` deliberately leaves this file out, because the record
    /// keeps the Router in the decisions that named it when they were taken.
    /// The two cases below read the file instead, and pin what it must say
    /// now.
    private static let planFileName = "plan.md"

    /// The heading of the decision that records the Router removal.
    ///
    /// An edit that drops the decision, renumbers it, or gives it another name
    /// fails ``planRecordsTheRouterFreeDecision()``.
    private static let routerFreeDecisionHeading =
        "30. **Router-free package; the host injects the selection session.**"

    /// The text the public API sketch's heading line begins with.
    private static let apiSketchHeading = "## 10. Public API sketch"

    /// The one-call factory the public API sketch must show.
    private static let injectedSessionFactory = "SkillsTool.make(registry:session:)"

    /// The Router-era embedder wrapper the public API sketch must not show.
    ///
    /// The wrapper adapted a routed embedding model. No such model is in this
    /// package's graph, thus a reader who copied the sketch could not build
    /// the wrapper.
    private static let removedEmbedderAdapterName = "RoutedEmbedderAdapter"

    /// The prefix of a top-level section heading in the decision record.
    private static let sectionHeadingPrefix = "## "

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

    @Test("Package.resolved holds none of the live-Router packages")
    func resolvesNoneOfTheLiveRouterPackages() throws {
        let found = try Self.resolvedIdentities().intersection(Self.removedIdentities).sorted()
        #expect(
            found.isEmpty,
            """
            Package.resolved must hold none of the packages the live-Router path pulled in -- \
            nothing in this package resolves a live Router any more; found: \(found)
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
    /// The walk reads ``prosePaths``, and nothing else. Two parts of the
    /// package are deliberately outside it:
    ///
    /// - `plan.md` keeps the historical decision record. A decision that named
    ///   the Router when it was taken must keep that name, or the record stops
    ///   being a record.
    /// - `Tests/` may name the Router in a disclosure note. This suite does so
    ///   in the comments above, and `HotReloadLiveTests` states that it never
    ///   imports the Router. A walk over `Tests/` would report those notes, and
    ///   would report itself.
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
        let root = FixtureLibrary.packageRoot()
        let published = try Self.readmeUsageBlock(under: root)
        let compiled = try Self.compiledUsageBlockCopy(under: root)
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

    /// Proves that the decision record holds the decision that records the
    /// Router removal.
    ///
    /// The record amends decision 17 and decision 26 in place, and an
    /// amendment alone says only that something changed. The dated decision
    /// says what changed and why. A later edit that removes it would leave two
    /// amendments that point at nothing, thus this case pins the heading.
    @Test("plan.md holds the dated decision that records the Router removal")
    func planRecordsTheRouterFreeDecision() throws {
        let plan = try Self.planText()
        #expect(
            plan.contains(Self.routerFreeDecisionHeading),
            """
            plan.md must hold the decision that records the Router removal, spelled \
            "\(Self.routerFreeDecisionHeading)". Decision 17 and decision 26 both point at it.
            """
        )
    }

    /// Proves that the public API sketch shows the factory a host calls today.
    ///
    /// The sketch is the first code most readers copy. While the Router was in
    /// the graph, it built the search context by hand, gave the selection tier
    /// a routed model, and wrapped a routed embedding model. None of those
    /// three compile now. The sketch must show the one-call factory that takes
    /// the host's own session instead.
    @Test("the public API sketch shows the injected-session factory")
    func apiSketchShowsTheInjectedSessionFactory() throws {
        let sketch = try Self.planSection(startingWith: Self.apiSketchHeading)
        #expect(
            sketch.contains(Self.injectedSessionFactory),
            """
            the public API sketch must show \(Self.injectedSessionFactory), the factory that takes \
            the selection session from the host
            """
        )
        #expect(
            !sketch.contains(Self.removedEmbedderAdapterName),
            """
            the public API sketch must not show \(Self.removedEmbedderAdapterName): it is a \
            Router-era type, thus a reader who copied the sketch could not build it
            """
        )
    }

    /// Reads `plan.md` from the package root.
    ///
    /// The read is deliberately unguarded, for the same reason as
    /// ``resolvedIdentities()``: an absent record must fail the case, and
    /// never make it pass on an empty string.
    ///
    /// - Returns: The whole decision record.
    /// - Throws: An error when `plan.md` cannot be read.
    private static func planText() throws -> String {
        let plan = FixtureLibrary.packageRoot().appendingPathComponent(Self.planFileName)
        return try String(contentsOf: plan, encoding: .utf8)
    }

    /// Reads the one section of `plan.md` whose heading line begins with
    /// `heading`.
    ///
    /// A section runs from its own heading line to the next top-level heading,
    /// or to the end of the record. One section is read, and not the whole
    /// file, because a "must not name" expectation over the whole record would
    /// pass on text that lies somewhere else in it.
    ///
    /// - Parameter heading: The text the section's heading line begins with.
    /// - Returns: The section, its heading line included.
    /// - Throws: ``MissingSectionError`` when no heading line begins with
    ///   `heading`, or an error when `plan.md` cannot be read.
    private static func planSection(startingWith heading: String) throws -> String {
        let lines = try Self.planText().components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.hasPrefix(heading) }) else {
            throw MissingSectionError(heading: heading)
        }
        let body = lines[lines.index(after: start)...]
        let end = body.firstIndex { $0.hasPrefix(Self.sectionHeadingPrefix) } ?? body.endIndex
        return lines[start..<end].joined(separator: "\n")
    }

    /// Thrown when ``planSection(startingWith:)`` finds no matching heading.
    ///
    /// An absent heading is a failure, and never an empty section: a case that
    /// read nothing would pass its "must not name" expectation and prove
    /// nothing.
    private struct MissingSectionError: Error, CustomStringConvertible {
        /// The heading text that no line began with.
        let heading: String

        /// Names the absent heading, thus the failure message says which
        /// section the record no longer holds.
        var description: String {
            "plan.md holds no heading line that begins with \"\(heading)\"."
        }
    }

    /// Reads the README's first Swift code fence, without its `import` lines.
    ///
    /// - Parameter root: The package root.
    /// - Returns: The block, one line for each line of the fence.
    /// - Throws: ``MissingBlockError`` when the README holds no Swift fence,
    ///   or an error when the README cannot be read. An absent block is a
    ///   failure, and never an empty string: two empty strings are equal, and
    ///   a case that compared them would prove nothing.
    private static func readmeUsageBlock(under root: URL) throws -> String {
        let readme = try String(
            contentsOf: root.appendingPathComponent(Self.readmeFileName), encoding: .utf8)
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
    /// - Parameter root: The package root.
    /// - Returns: The copy, one line for each line between the markers.
    /// - Throws: ``MissingBlockError`` when either marker is absent, or an
    ///   error when the file cannot be read.
    private static func compiledUsageBlockCopy(under root: URL) throws -> String {
        let file = root.appendingPathComponent(Self.usageBlockCopyPath)
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
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
