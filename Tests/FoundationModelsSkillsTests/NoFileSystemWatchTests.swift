import Testing

/// Guards the loading boundary of the reload path (plan.md §3, §7): this
/// package watches its layer roots with `DotfolderWatcher` of
/// `FoundationModelsExtras`, thus no file under `Sources/` opens a watch of
/// its own.
///
/// A watch of the file system is raw file work: it opens a descriptor with
/// `O_EVTONLY` and it makes a `DispatchSource` for each directory and each
/// file. That work belongs beside the stack, in Extras, where one type holds
/// the debounce, the arming of a root that is not there yet, and the cancel
/// of a source that a later scan replaces. A second watcher beside that one
/// can answer differently for one root, and it can miss a change the stack
/// reports.
///
/// The suite gives `SwiftSourceScan` the test of a line below, and that
/// reader walks every Swift file under `Sources/`. A line opens a watch of
/// its own when it names one of the three markers of the retired local
/// watcher.
@Suite("No file system watch")
struct NoFileSystemWatchTests {
    /// The names that no line under `Sources/` may hold: the two pieces of a
    /// hand-written watch, and the name of the retired local watcher.
    private static let watchNames = ["DispatchSource", "O_EVTONLY", "SkillWatcher"]

    /// The source directory, relative to the package root.
    private static let sourcesPath = "Sources"

    @Test(arguments: [
        "let descriptor = open(url.path, O_EVTONLY)",
        "let source = DispatchSource.makeFileSystemObjectSource(",
        "private let watcher: SkillWatcher?",
        "/// With `watch: true`, a `SkillWatcher` observes every layer root.",
    ])
    func aLineThatWatchesTheFileSystemIsReported(line: String) {
        #expect(Self.watchesTheFileSystem(line))
    }

    @Test(arguments: [
        "watcher = watchedRoots.map { DotfolderWatcher(roots: $0, onChange: rebuild) }",
        "/// Owns the `DotfolderWatcher` and the `onReload` continuation.",
        "private let watcher: DotfolderWatcher?",
    ])
    func aLineThatAsksExtrasIsNotReported(line: String) {
        #expect(!Self.watchesTheFileSystem(line))
    }

    @Test func noFileUnderSourcesWatchesTheFileSystem() throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.sourcesPath, matching: Self.watchesTheFileSystem)

        #expect(
            offenders.isEmpty,
            """
            No file under \(Self.sourcesPath) may watch the file system itself. Use \
            DotfolderWatcher of FoundationModelsExtras; found: \(offenders.joined(separator: ", "))
            """)
    }

    /// Tells whether `line` opens a watch of the file system of its own.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line holds one of `watchNames`.
    private static func watchesTheFileSystem(_ line: String) -> Bool {
        watchNames.contains { line.contains($0) }
    }
}
