import Testing

/// Holds `SwiftSourceScan`, the source reader that the two rule guards share,
/// to its contract: it counts the lines of a text from 1, it walks the Swift
/// files of a directory, and it stops a walk that finds no Swift file.
///
/// `NoGitProcessTests` and `NoStandardOutWriteTests` each give the reader one
/// test of a line. This suite holds the steps under that test, thus neither
/// guard keeps a case for them.
@Suite("Swift source scan")
struct SwiftSourceScanTests {
    /// The directory of the demonstration example, relative to the package
    /// root. Each source file of it is a Swift file.
    private static let exampleDirectory = "Examples/skills-demo"

    /// A directory of the package that holds files and no Swift file.
    private static let directoryWithNoSwiftFile = "Examples/skill-library"

    /// The text that opens the import line of a Swift file.
    private static let importMarker = "import "

    /// The text that stands between a path and a line number.
    private static let lineNumberMarker = ".swift:"

    @Test func theReportedLineNumberCountsFromOne() {
        let text = """
            let first = "alpha"
            let second = "bravo"
            let third = "charlie"
            """

        #expect(SwiftSourceScan.lineNumbers(in: text) { $0.contains("charlie") } == [3])
    }

    @Test func aTextWithNoReportedLineGivesNoNumber() {
        #expect(SwiftSourceScan.lineNumbers(in: "one line") { _ in false }.isEmpty)
    }

    @Test func theWalkNamesTheDirectoryThePathAndTheLineNumber() throws {
        let reported = try SwiftSourceScan.reportedLines(inDirectory: Self.exampleDirectory) {
            $0.hasPrefix(Self.importMarker)
        }

        #expect(!reported.isEmpty, "each file of the example imports, or this case proves nothing")
        #expect(
            reported.allSatisfy {
                $0.hasPrefix("\(Self.exampleDirectory)/") && $0.contains(Self.lineNumberMarker)
            })
    }

    @Test func aWalkThatFindsNoSwiftFileStops() {
        #expect(throws: SwiftSourceScan.ScanError.self) {
            try SwiftSourceScan.reportedLines(inDirectory: Self.directoryWithNoSwiftFile) { _ in true }
        }
    }
}
