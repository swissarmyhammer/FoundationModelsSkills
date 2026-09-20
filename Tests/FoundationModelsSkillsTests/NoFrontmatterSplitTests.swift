import Testing

/// Guards the loading boundary of this package: the registry opens no file,
/// and the split of a document into its frontmatter and its body belongs to
/// `FoundationModelsExtras`.
///
/// The suite gives `SwiftSourceScan` the test of a line below, and that reader
/// walks every Swift file under `Sources/`. `FrontmatterDocumentStack` does
/// each read and each split for the registry; this package keeps the Yams
/// decode, the quoting-fallback retry and the notes, because those are the
/// schema of the skill format.
///
/// `Marketplace/` is the one folder that a line of the split may still name.
/// A marketplace repository comes through a `CatalogFileSource`, which can be
/// a git tree and thus no dotfolder stack. The card that gives the
/// marketplace to Extras deletes that folder, and this exception with it.
@Suite("No frontmatter split")
struct NoFrontmatterSplitTests {
    /// The source directory, relative to the package root.
    private static let sourcesPath = "Sources"

    /// The directory of the registry, relative to the package root.
    private static let registryDirectory = "Sources/FoundationModelsSkills/Registry"

    /// The prefix of the path of each file that may still name the split.
    private static let marketplacePath = "Sources/FoundationModelsSkills/Marketplace/"

    /// The text of a line that splits a document itself.
    private static let splitMarker = "FrontmatterDocument.split"

    /// The text of a line that reads a file into a string itself.
    private static let stringReadMarker = "String(contentsOf"

    @Test func aLineThatSplitsADocumentIsReported() {
        #expect(Self.splitsADocument("let parts = FrontmatterDocument.split(text: text)"))
    }

    @Test func aLineThatOnlyNamesTheDocumentTypeIsNotReported() {
        #expect(!Self.splitsADocument("func item() -> FrontmatterDocument<Metadata> { document }"))
    }

    @Test func noFileUnderSourcesOutsideTheMarketplaceSplitsADocument() throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.sourcesPath, matching: Self.splitsADocument
        ).filter { !$0.hasPrefix(Self.marketplacePath) }

        #expect(
            offenders.isEmpty,
            """
            No file under Sources/, outside Marketplace/, may split a document itself. \
            FrontmatterDocumentStack gives the split; found: \(offenders.joined(separator: ", "))
            """)
    }

    @Test func theRegistryReadsNoFileItself() throws {
        let offenders = try SwiftSourceScan.reportedLines(inDirectory: Self.registryDirectory) {
            $0.contains(Self.stringReadMarker)
        }

        #expect(
            offenders.isEmpty,
            """
            SkillsRegistry must open no file: the layer stack reads every SKILL.md; \
            found: \(offenders.joined(separator: ", "))
            """)
    }

    /// Tells whether `line` splits a document itself.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line calls the split of Extras.
    private static func splitsADocument(_ line: String) -> Bool {
        line.contains(splitMarker)
    }
}
