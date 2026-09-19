import Foundation

/// Reads the Swift source of this package for a suite that guards a rule of
/// the code.
///
/// Two suites guard a rule this way: `NoGitProcessTests`, which holds the
/// package to libgit2, and `NoStandardOutWriteTests`, which holds it to one
/// line writer. Each one gives a test of a line, and this file does the two
/// steps under it -- it counts the lines of a text, and it walks the Swift
/// files of a directory. Thus neither suite keeps a copy of those steps.
enum SwiftSourceScan {
    /// The number of the first line of a file.
    private static let firstLineNumber = 1

    /// The suffix of a Swift source file.
    private static let swiftFileSuffix = ".swift"

    /// What stops a walk over a directory.
    enum ScanError: Error, CustomStringConvertible {
        /// The directory holds no Swift file, thus the walk proves nothing.
        case noSwiftFile(directory: String)

        /// The text of the error.
        var description: String {
            switch self {
            case .noSwiftFile(let directory):
                "the walk found no Swift file under \(directory), thus it proves nothing"
            }
        }
    }

    /// Finds each line of `text` that `isReported` reports.
    ///
    /// - Parameters:
    ///   - text: The source text to read.
    ///   - isReported: Tells whether one line breaks the rule.
    /// - Returns: The number of each reported line. The first line is 1.
    static func lineNumbers(in text: String, matching isReported: (String) -> Bool) -> [Int] {
        text.components(separatedBy: .newlines).enumerated()
            .filter { isReported($0.element) }
            .map { $0.offset + firstLineNumber }
    }

    /// Finds each reported line of each Swift file under `directory`.
    ///
    /// - Parameters:
    ///   - directory: A directory path relative to the package root, such as
    ///     `"Sources"`.
    ///   - isReported: Tells whether one line breaks the rule.
    /// - Returns: One text for each reported line, in the form
    ///   `<directory>/<relative path>:<line number>`.
    /// - Throws: ``ScanError/noSwiftFile(directory:)`` when the directory
    ///   holds no Swift file, because a walk that reads no file proves
    ///   nothing. Also an error when the directory or a file of it is
    ///   unreadable, or when a file is not UTF-8 text.
    static func reportedLines(
        inDirectory directory: String, matching isReported: (String) -> Bool
    ) throws -> [String] {
        let root = FixtureLibrary.packageRoot().appendingPathComponent(directory, isDirectory: true)
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(swiftFileSuffix) }
        guard !files.isEmpty else { throw ScanError.noSwiftFile(directory: directory) }

        return try files.flatMap { relativePath in
            let text = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
            return lineNumbers(in: text, matching: isReported).map { "\(directory)/\(relativePath):\($0)" }
        }
    }
}
