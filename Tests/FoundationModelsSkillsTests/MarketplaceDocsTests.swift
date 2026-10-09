import Foundation
import Operations
import Testing

@testable import FoundationModelsSkills

/// One text, and the documentation file that a suite reads it against.
///
/// A suite walks a table of these rows, thus one read-and-assert body serves
/// every document and every name. A suite decides what the row means: a claim
/// the document must make, or a wording the document must not hold.
struct DocumentClaim: Sendable {
    /// The path of the document, from the package root.
    let document: String

    /// The text that the document must hold.
    let text: String
}

/// Holds the marketplace documentation to the behavior that shipped
/// (marketplace.md §10).
///
/// The suite reads the documentation files from the disk, found from this
/// file's `#filePath`, and asserts that each one names what a host must know.
/// Every name of the host guide comes from the code: the environment
/// variables are the constants that the cache and the policy read. Thus a new
/// environment variable makes this suite fail until the host guide describes
/// it.
@Suite("Marketplace docs")
struct MarketplaceDocsTests {
    /// The host guide of the marketplaces, relative to the package root.
    private static let hostGuidePath = "docs/marketplaces.md"

    /// The security document, relative to the package root.
    private static let securityPath = "docs/security.md"

    /// The README of the package, relative to the package root.
    private static let readmePath = "README.md"

    /// The design record of the marketplaces, relative to the package root.
    private static let designRecordPath = "marketplace.md"

    /// The package that holds the marketplace: the store, the cache, the
    /// transport, the catalog read, the snapshot writer and the
    /// configuration file. A host document must name it, so that a reader
    /// knows which repository a change of the behavior goes to.
    private static let marketplacePackageName = "FoundationModelsExtras"

    /// The fixtures product of that package, which only the test bundle
    /// links. The design record names it, thus a reader knows that the
    /// library links no libgit2.
    private static let fixturesProductName = "MarketplaceFixtures"

    /// The date of the decision that gave the whole marketplace to
    /// ``marketplacePackageName`` (marketplace.md decision 19).
    private static let marketplaceDecisionDate = "2026-09-19"

    /// The name of the layout type that the store initializer needs, taken
    /// from the type itself. Thus a rename makes this suite fail until the
    /// design record names the new type.
    private static let layoutTypeName = String(describing: MarketplaceLayout.self)

    /// Every document that states where the marketplace is implemented.
    private static let implementationDocuments = [
        designRecordPath, hostGuidePath, securityPath,
    ]

    /// The wording that puts an implementation in this repository.
    private static let localHomeWording = "in this package"

    /// The parts of the marketplace that ``marketplacePackageName`` owns. A
    /// line that names one of these, and ``localHomeWording`` beside it,
    /// gives the reader the wrong home.
    private static let movedPartNouns = ["store", "cache", "transport"]

    /// The name of the type that carried the per-marketplace grants. The
    /// host `RenderPolicy` gates every layer now, thus no document may name
    /// that type any more.
    private static let removedGrantsTypeName = "MarketplaceGrants"

    /// Every document that describes the marketplaces to a reader.
    private static let marketplaceDocuments = [
        hostGuidePath, securityPath, readmePath, designRecordPath,
    ]

    /// The heading of the marketplace section of the security document.
    private static let securityHeading = "## Marketplaces"

    /// The environment variables that a host can set. Each value is the
    /// constant that the code reads, thus the list can never go stale.
    private static let environmentVariables = [
        MarketplaceStore.cacheDirectoryVariable,
        MarketplaceStore.seedDirectoryVariable,
        MarketplacePolicy.automaticUpdateVariable,
    ]

    /// The libgit2 message that an SSH URL gives. `swift-libgit2` builds no
    /// SSH transport, thus the host guide must tell the user this diagnostic.
    private static let sshDiagnostic = "unsupported URL protocol"

    /// The start of an scp-like SSH URL, for example
    /// `git@github.com:owner/repo.git`.
    private static let sshURLPrefix = "git@"

    /// Every claim that the documentation must make: the host guide names
    /// each environment variable, the security document has its marketplace
    /// section, the README points to the host guide, and each document names
    /// the package that holds the marketplace now.
    private static let claims =
        environmentVariables.map { DocumentClaim(document: hostGuidePath, text: $0) }
        + [
            DocumentClaim(document: hostGuidePath, text: sshDiagnostic),
            DocumentClaim(document: securityPath, text: securityHeading),
            DocumentClaim(document: readmePath, text: hostGuidePath),
            DocumentClaim(document: hostGuidePath, text: marketplacePackageName),
            DocumentClaim(document: securityPath, text: marketplacePackageName),
            DocumentClaim(document: securityPath, text: fixturesProductName),
            DocumentClaim(document: designRecordPath, text: marketplacePackageName),
            DocumentClaim(document: designRecordPath, text: fixturesProductName),
            DocumentClaim(document: designRecordPath, text: marketplaceDecisionDate),
            DocumentClaim(document: designRecordPath, text: layoutTypeName),
        ]

    @Test(arguments: claims)
    func theDocumentationMakesEveryClaim(claim: DocumentClaim) throws {
        let text = try FixtureLibrary.readText(relativePath: claim.document)

        #expect(
            text.contains(claim.text),
            "\(claim.document) must name \"\(claim.text)\"")
    }

    @Test(arguments: marketplaceDocuments)
    func noDocumentNamesTheRemovedGrantsType(document: String) throws {
        let text = try FixtureLibrary.readText(relativePath: document)

        #expect(
            !text.contains(Self.removedGrantsTypeName),
            "\(document) must not name \"\(Self.removedGrantsTypeName)\"")
    }

    @Test(arguments: implementationDocuments)
    func noDocumentPutsAMovedPartInThisPackage(document: String) throws {
        let text = try FixtureLibrary.readText(relativePath: document)

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let sentence = line.lowercased()
            guard sentence.contains(Self.localHomeWording) else { continue }
            let named = Self.movedPartNouns.filter { sentence.contains($0) }
            #expect(
                named.isEmpty,
                """
                \(document) says the \(named.joined(separator: ", ")) is \
                "\(Self.localHomeWording)": \(line)
                """)
        }
    }

    @Test func theHostGuideGivesNoSSHURLAsAnExample() throws {
        let text = try FixtureLibrary.readText(relativePath: Self.hostGuidePath)

        #expect(
            !text.contains(Self.sshURLPrefix),
            "\(Self.hostGuidePath) must give each example URL in the HTTPS form")
    }
}
