import Testing

/// Guards marketplace.md decision 10: the package never starts the `git`
/// binary. Git work goes through libgit2 behind `GitTransport`.
///
/// The suite gives `SwiftSourceScan` the test of a line below, and that reader
/// walks every Swift file under `Sources/`. A line starts a process when it
/// sets `executableURL` or `launchPath`, or when it builds a `Process`. A line
/// names `git` when one of its words, split at each character that is not a
/// letter or a digit, is `git`. Thus `/usr/bin/git` and `"git"` are reported,
/// and `libgit2` and `GitTransport` are not.
@Suite("No git process")
struct NoGitProcessTests {
    /// The text that marks a line that starts a process: it sets the
    /// executable of a `Process`, or it builds one.
    private static let processMarkers = ["executableURL", "launchPath", "Process("]

    /// The executable that no process line may name.
    private static let gitExecutableName = "git"

    /// The source directory, relative to the package root.
    private static let sourcesPath = "Sources"

    @Test(arguments: [
        #"process.executableURL = URL(fileURLWithPath: "/usr/bin/git")"#,
        #"process.launchPath = "/usr/bin/git""#,
        "let git = Process()",
    ])
    func aProcessLineThatNamesGitIsReported(line: String) {
        #expect(Self.startsAGitProcess(line))
    }

    @Test(arguments: [
        #"process.executableURL = URL(fileURLWithPath: "/bin/sh")"#,
        "import libgit2",
        "let transport: any GitTransport = LibGit2Transport()",
        #"let note = "the package does not start git""#,
    ])
    func aLineThatDoesNotStartGitIsNotReported(line: String) {
        #expect(!Self.startsAGitProcess(line))
    }

    @Test func noFileUnderSourcesStartsAGitProcess() throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.sourcesPath, matching: Self.startsAGitProcess)

        #expect(
            offenders.isEmpty,
            """
            No file under Sources/ may start the git binary (marketplace.md decision 10). Use \
            GitTransport, which calls libgit2; found: \(offenders.joined(separator: ", "))
            """)
    }

    /// Tells whether `line` starts a process that names `git`.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line both starts a process and names `git`.
    private static func startsAGitProcess(_ line: String) -> Bool {
        startsAProcess(line) && namesGit(line)
    }

    /// Tells whether `line` sets the executable of a process or builds one.
    private static func startsAProcess(_ line: String) -> Bool {
        processMarkers.contains { line.contains($0) }
    }

    /// Tells whether one word of `line` is `git`, in any letter case.
    private static func namesGit(_ line: String) -> Bool {
        line.split { !$0.isLetter && !$0.isNumber }.contains { $0.lowercased() == gitExecutableName }
    }
}
