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
@Suite("Dependency graph")
struct DependencyGraphTests {
    /// The package identities the live-Router path pulled in, which the
    /// resolved graph must no longer hold.
    ///
    /// SwiftPM writes each identity in lower case, thus each entry is spelled
    /// that way. `FoundationModelsRouter` supplied the routing types.
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
        "foundationmodelsrouter",
        "mlx-swift",
        "mlx-swift-lm",
        "swift-huggingface",
        "swift-transformers",
    ]

    /// The resolution file, relative to the package root.
    private static let resolutionFileName = "Package.resolved"

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

    /// Reads the identity of every pin in `Package.resolved`.
    ///
    /// An absent file makes `Data(contentsOf:)` throw, thus the test fails.
    /// The read is deliberately unguarded: a guard could only turn that
    /// failure into a skip, and a tripwire that skips itself rots.
    ///
    /// - Returns: the identity of each resolved package.
    /// - Throws: an error when `Package.resolved` cannot be read or decoded.
    private static func resolvedIdentities() throws -> Set<String> {
        let file = FixtureLibrary.packageRoot().appendingPathComponent(resolutionFileName)
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
