import Foundation

/// Shared fixture helpers for the tests that make layer directories on real
/// disk and put files in them -- `PathConfinementTests`, `SkillOverlayTests`,
/// `SkillDiscoveryTests` and `ResourceOpsTests`. Each needs the same helpers,
/// thus the helpers are in this one file.
///
/// `WatcherTestSupport` gives the temporary directory, thus this file makes
/// none of its own.
enum LayerFixtureSupport {
    /// Makes `count` fresh, empty temporary directories, one for each layer.
    ///
    /// - Parameter count: How many directories to make.
    /// - Returns: The new directories, in the order they were made.
    /// - Throws: Whatever `WatcherTestSupport.makeTempDirectory()` throws.
    static func makeLayerDirectories(count: Int) throws -> [URL] {
        try (0..<count).map { _ in try WatcherTestSupport.makeTempDirectory() }
    }

    /// Removes each directory of `directories`, for the cleanup of a test that
    /// made one directory or more.
    ///
    /// - Parameter directories: The directories to remove.
    static func removeDirectories(_ directories: [URL]) {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Writes a small text file at `relativePath` in `directory`, and makes
    /// the directories above the file first.
    ///
    /// The text names the directory, thus two copies of one path in two
    /// layer directories hold different text.
    ///
    /// - Parameters:
    ///   - relativePath: The path of the file, relative to `directory`.
    ///   - directory: The layer directory to write in.
    /// - Returns: The URL of the file.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    @discardableResult
    static func writeTextFile(at relativePath: String, in directory: URL) throws -> URL {
        try writeTextFile(
            "Text of \(relativePath) in \(directory.lastPathComponent).\n", at: relativePath, in: directory)
    }

    /// Writes `text` at `relativePath` in `directory`, and makes the
    /// directories above the file first.
    ///
    /// A test that needs two copies of one path to differ in length gives the
    /// text of each copy itself; `writeTextFile(at:in:)` gives text that names
    /// the directory instead.
    ///
    /// - Parameters:
    ///   - text: The whole text of the file.
    ///   - relativePath: The path of the file, relative to `directory`.
    ///   - directory: The layer directory to write in.
    /// - Returns: The URL of the file.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    @discardableResult
    static func writeTextFile(_ text: String, at relativePath: String, in directory: URL) throws -> URL {
        let url = try preparedFileURL(at: relativePath, in: directory)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Writes a small file of bytes that are not UTF-8 text at `relativePath`
    /// in `directory`, and makes the directories above the file first.
    ///
    /// A reader that decodes the file as UTF-8 text gets nothing, thus a test
    /// writes such a file to prove that a view of the layer directories holds
    /// a file that only holds bytes.
    ///
    /// - Parameters:
    ///   - relativePath: The path of the file, relative to `directory`.
    ///   - directory: The layer directory to write in.
    /// - Returns: The URL of the file.
    /// - Throws: Whatever `FileManager.createDirectory` or `Data.write`
    ///   throws.
    @discardableResult
    static func writeBytesFile(at relativePath: String, in directory: URL) throws -> URL {
        let url = try preparedFileURL(at: relativePath, in: directory)
        try Data(pngSignature).write(to: url, options: .atomic)
        return url
    }

    /// The path of `url` with each symbolic link resolved, which is the form
    /// `PathConfinement` gives back.
    ///
    /// - Parameter url: The URL of a file that exists.
    /// - Returns: The resolved, standardized path.
    static func resolvedPath(of url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// The byte that starts a PNG file. Its high bit is set, thus it can start
    /// no UTF-8 sequence, and it makes the file bytes and not text.
    private static let pngLeadByte: UInt8 = 0x89

    /// The bytes of the letters `PNG`, which come after the lead byte.
    private static let pngNameBytes: [UInt8] = Array("PNG".utf8)

    /// The carriage return byte of the PNG signature.
    private static let carriageReturnByte: UInt8 = 0x0D

    /// The line feed byte of the PNG signature.
    private static let lineFeedByte: UInt8 = 0x0A

    /// The end-of-file byte of the PNG signature. It stops the listing of the
    /// file on a DOS terminal.
    private static let endOfFileByte: UInt8 = 0x1A

    /// The first eight bytes of a PNG file, which are not UTF-8 text.
    private static let pngSignature: [UInt8] =
        [pngLeadByte] + pngNameBytes
        + [carriageReturnByte, lineFeedByte, endOfFileByte, lineFeedByte]

    /// The URL of `relativePath` in `directory`, with the directories above
    /// the file made, for a helper that then writes the file.
    ///
    /// - Parameters:
    ///   - relativePath: The path of the file, relative to `directory`.
    ///   - directory: The layer directory to write in.
    /// - Returns: The URL of the file, which does not exist yet.
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    private static func preparedFileURL(at relativePath: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }
}
