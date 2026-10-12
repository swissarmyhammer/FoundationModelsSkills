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

    /// The text that the document must hold, or must not hold.
    let text: String
}

extension DocumentClaim {
    /// Records an issue when the document does not hold ``text``.
    ///
    /// This is the one check of a claim that a document must make. Each
    /// suite gives its rows. The read, the comparison and the message are
    /// only here, thus a change to the check is one change.
    ///
    /// The comparison is exact, because a claim names a heading, a path or a
    /// name of the code as the code spells it.
    ///
    /// - Parameter sourceLocation: The test line that the issue points to.
    /// - Throws: An error when the document is not there, or is not UTF-8
    ///   text.
    func expectPresent(sourceLocation: SourceLocation = #_sourceLocation) throws {
        let documentText = try FixtureLibrary.readText(relativePath: document)

        #expect(
            documentText.contains(text),
            "\(document) must hold \"\(text)\"",
            sourceLocation: sourceLocation)
    }

    /// Tells whether a document text holds ``text`` in any case.
    ///
    /// This is the comparison of the absence check. It reads no file, thus a
    /// test can give it a text and assert the result.
    ///
    /// - Parameter documentText: The text of a document.
    /// - Returns: `true` when `documentText` holds ``text``, in any case.
    func isHeld(in documentText: String) -> Bool {
        documentText.lowercased().contains(text.lowercased())
    }

    /// Records an issue when the document holds ``text``.
    ///
    /// This is the one check of a removed wording. Each suite gives its rows
    /// and the reason. The read, the comparison and the message are only
    /// here, thus a change to the check is one change.
    ///
    /// The comparison is ``isHeld(in:)``, which ignores case. A removed
    /// wording is false in each case.
    ///
    /// - Parameters:
    ///   - reason: Why the wording is false now. The issue gives it to the
    ///     reader.
    ///   - sourceLocation: The test line that the issue points to.
    /// - Throws: An error when the document is not there, or is not UTF-8
    ///   text.
    func expectAbsent(
        because reason: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let documentText = try FixtureLibrary.readText(relativePath: document)

        #expect(
            !isHeld(in: documentText),
            "\(document) must not hold \"\(text)\": \(reason)",
            sourceLocation: sourceLocation)
    }
}

/// Holds the marketplace documentation to the behavior that shipped.
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

    /// The package that holds the marketplace: the store, the cache, the
    /// transport, the folder scan, the snapshot writer and the
    /// configuration file. A host document must name it, so that a reader
    /// knows which repository a change of the behavior goes to.
    private static let marketplacePackageName = "FoundationModelsExtras"

    /// The fixtures product of that package, which only the test bundle
    /// links. The security document names it, thus a reader knows that the
    /// library links no libgit2.
    private static let fixturesProductName = "MarketplaceFixtures"

    /// The name of the layout type that the store initializer needs, taken
    /// from the type itself. Thus a rename makes this suite fail until the
    /// host guide names the new type.
    private static let layoutTypeName = String(describing: MarketplaceLayout.self)

    /// Every document that states where the marketplace is implemented.
    private static let implementationDocuments = [
        hostGuidePath, securityPath,
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
        hostGuidePath, securityPath, readmePath,
    ]

    /// Every document of the package: the README and each file of `docs/`.
    private static let packageDocuments = [
        readmePath, hostGuidePath, securityPath, "docs/operations.md", "docs/development.md",
    ]

    /// The wordings of the catalog read that Extras removed. A marketplace is
    /// only a folder now: the store scans the tree and reads no catalog file,
    /// and a selection names skills only. Thus no document may name the
    /// catalog file or the plugin selection.
    private static let removedCatalogWordings = ["marketplace.json", ".plugins("]

    /// One row for each document and each removed catalog wording.
    private static let removedCatalogRows: [DocumentClaim] = packageDocuments.flatMap { document in
        removedCatalogWordings.map { DocumentClaim(document: document, text: $0) }
    }

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
            DocumentClaim(document: hostGuidePath, text: layoutTypeName),
        ]

    @Test(arguments: claims)
    func theDocumentationMakesEveryClaim(claim: DocumentClaim) throws {
        try claim.expectPresent()
    }

    /// The absence check finds a wording in a text that holds it in a
    /// different case. A check that does not find it here would let each
    /// removed wording through.
    @Test(arguments: [
        "See DOCS/MARKETPLACES.MD for the host guide.",
        "See docs/marketplaces.md for the host guide.",
        "See Docs/Marketplaces.md for the host guide.",
    ])
    func theAbsenceCheckFindsAWordingInAnyCase(documentText: String) {
        let wording = DocumentClaim(document: Self.readmePath, text: Self.hostGuidePath)

        #expect(wording.isHeld(in: documentText))
    }

    /// The absence check finds no wording in a text that does not hold it.
    /// A check that finds it here would fail on each document.
    @Test func theAbsenceCheckFindsNoWordingThatTheTextDoesNotHold() {
        let wording = DocumentClaim(document: Self.readmePath, text: Self.hostGuidePath)

        #expect(!wording.isHeld(in: "See docs/security.md for the security posture."))
    }

    @Test(arguments: marketplaceDocuments)
    func noDocumentNamesTheRemovedGrantsType(document: String) throws {
        try DocumentClaim(document: document, text: Self.removedGrantsTypeName)
            .expectAbsent(because: "the host RenderPolicy gates every layer")
    }

    @Test(arguments: removedCatalogRows)
    func noDocumentSaysTheStoreReadsACatalogFile(row: DocumentClaim) throws {
        try row.expectAbsent(
            because: "the store scans the folder of a marketplace and reads no catalog file")
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
        try DocumentClaim(document: Self.hostGuidePath, text: Self.sshURLPrefix)
            .expectAbsent(because: "each example URL must have the HTTPS form")
    }
}
