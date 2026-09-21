import Testing

/// Guards the loading boundary of the resource operations (plan.md §3, §7.3):
/// each file of `Sources/FoundationModelsSkills/Resources` reaches a file of a
/// skill through the stack of `FoundationModelsExtras`, thus no file of that
/// directory names a reader of the file system of its own.
///
/// `SkillOverlay` gives the combined view of one skill, and the stack under it
/// opens each directory and each file: it gives the union of the paths, the
/// size of a file, the bytes of a file and the execute bit of a file. A second
/// reader beside that one can answer differently for one path -- it can name
/// another copy, and it can read a file the stack denies.
///
/// The suite gives `SwiftSourceScan` the test of a line below, and that reader
/// walks every Swift file of the directory. A line reads the file system when
/// it names one of the three readers of the standard library.
@Suite("No resource file read")
struct NoResourceFileReadTests {
    /// The names of the readers of the file system that no line may hold.
    private static let readerNames = ["FileManager", "FileHandle", "resourceValues"]

    /// The directory of the resource operations, relative to the package root.
    private static let resourcesPath = "Sources/FoundationModelsSkills/Resources"

    @Test(arguments: [
        "guard let handle = try? FileHandle(forReadingFrom: url) else { return false }",
        "if !FileManager.default.isExecutableFile(atPath: resolved.path) {",
        "(try? url.resourceValues(forKeys: [.isExecutableKey]))?.isExecutable ?? false",
    ])
    func aLineThatReadsTheFileSystemIsReported(line: String) {
        #expect(Self.readsTheFileSystem(line))
    }

    @Test(arguments: [
        "if !overlay.isExecutable(path) {",
        "overlay.data(relativePath, in: offset..<(offset + chunkByteSize))",
        "/// The stack reads the size, thus a caller opens no file of its own.",
    ])
    func aLineThatAsksTheStackIsNotReported(line: String) {
        #expect(!Self.readsTheFileSystem(line))
    }

    @Test func noFileOfTheResourceOperationsReadsTheFileSystem() throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.resourcesPath, matching: Self.readsTheFileSystem)

        #expect(
            offenders.isEmpty,
            """
            No file of \(Self.resourcesPath) may read the file system itself. Ask the overlay, \
            which asks the stack of FoundationModelsExtras; found: \(offenders.joined(separator: ", "))
            """)
    }

    /// Tells whether `line` names a reader of the file system.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line holds one of `readerNames`.
    private static func readsTheFileSystem(_ line: String) -> Bool {
        readerNames.contains { line.contains($0) }
    }
}
