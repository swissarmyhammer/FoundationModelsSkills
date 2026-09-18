import Operations
import Testing

@testable import FoundationModelsSkills

/// One claim that a documentation file must make.
///
/// The suite below walks a table of these rows, thus one read-and-assert body
/// serves every document and every name.
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
/// variables are the constants that the cache and the policy read, and the
/// subcommand names are the names in the `MarketplaceCLI` configuration. Thus
/// a new environment variable, or a new subcommand, makes this suite fail
/// until the host guide describes it.
@Suite("Marketplace docs")
struct MarketplaceDocsTests {
    /// The host guide of the marketplaces, relative to the package root.
    private static let hostGuidePath = "docs/marketplaces.md"

    /// The security document, relative to the package root.
    private static let securityPath = "docs/security.md"

    /// The README of the package, relative to the package root.
    private static let readmePath = "README.md"

    /// The heading of the marketplace section of the security document.
    private static let securityHeading = "## Marketplaces"

    /// The environment variables that a host can set. Each value is the
    /// constant that the code reads, thus the list can never go stale.
    private static let environmentVariables = [
        MarketplaceCache.cacheVariable,
        MarketplaceCache.seedVariable,
        MarketplacePolicy.automaticUpdateVariable,
    ]

    /// The libgit2 message that an SSH URL gives. `swift-libgit2` builds no
    /// SSH transport, thus the host guide must tell the user this diagnostic.
    private static let sshDiagnostic = "unsupported URL protocol"

    /// The start of an scp-like SSH URL, for example
    /// `git@github.com:owner/repo.git`.
    private static let sshURLPrefix = "git@"

    /// Each text that recommends a URL form to the user: the message of a URL
    /// that is not a supported form, and the help of the `add` command.
    private static let urlFormAdvice = [
        MarketplaceSourceError.unsupportedForm.description,
        MarketplaceCLI.Add.helpMessage(),
    ]

    /// The name of each subcommand of the `marketplace` command group, taken
    /// from the configuration of the group itself.
    private static let subcommandNames = MarketplaceCLI.configuration.subcommands
        .compactMap { $0.configuration.commandName }

    /// Every claim that the documentation must make: the host guide names
    /// each environment variable and each subcommand, the security document
    /// has its marketplace section, and the README points to the host guide.
    private static let claims =
        environmentVariables.map { DocumentClaim(document: hostGuidePath, text: $0) }
        + subcommandNames.map {
            DocumentClaim(
                document: hostGuidePath, text: "\(MarketplaceCLI.commandName) \($0)")
        }
        + [
            DocumentClaim(document: hostGuidePath, text: sshDiagnostic),
            DocumentClaim(document: securityPath, text: securityHeading),
            DocumentClaim(document: readmePath, text: hostGuidePath),
        ]

    @Test(arguments: claims)
    func theDocumentationMakesEveryClaim(claim: DocumentClaim) throws {
        let text = try FixtureLibrary.readText(relativePath: claim.document)

        #expect(
            text.contains(claim.text),
            "\(claim.document) must name \"\(claim.text)\"")
    }

    @Test func theHostGuideGivesNoSSHURLAsAnExample() throws {
        let text = try FixtureLibrary.readText(relativePath: Self.hostGuidePath)

        #expect(
            !text.contains(Self.sshURLPrefix),
            "\(Self.hostGuidePath) must give each example URL in the HTTPS form")
    }

    @Test(arguments: urlFormAdvice)
    func theURLFormAdviceNamesNoSSHForm(advice: String) {
        #expect(!advice.isEmpty)
        #expect(
            !advice.contains(Self.sshURLPrefix),
            "The advice must not recommend an SSH URL: \(advice)")
    }

    @Test func theCommandGroupGivesItsSubcommandNames() {
        #expect(
            !Self.subcommandNames.isEmpty,
            """
            The marketplace command group named no subcommand, thus the test of the host guide \
            proves nothing
            """)
    }
}
