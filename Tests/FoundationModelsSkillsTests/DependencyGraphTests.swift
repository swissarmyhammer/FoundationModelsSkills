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

    /// Reads every line at or under `base` that holds `name`.
    ///
    /// A file that does not decode as UTF-8 text is passed over, because no
    /// such file carries prose.
    ///
    /// - Parameters:
    ///   - name: The string that no line may hold.
    ///   - base: The file or directory to read.
    ///   - root: The package root, which each reported path is relative to.
    /// - Returns: One `<path>:<line>` entry for each line that holds `name`.
    ///   `enumerated()` counts from zero and an editor counts from one, thus
    ///   each reported line number is one more than the offset.
    private static func linesNaming(_ name: String, under base: URL, in root: URL) -> [String] {
        var offenders: [String] = []
        for file in Self.files(under: base) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (offset, line) in text.components(separatedBy: .newlines).enumerated()
            where line.contains(name) {
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
