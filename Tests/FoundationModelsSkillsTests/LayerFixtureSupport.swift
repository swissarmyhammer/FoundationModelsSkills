import Foundation

/// Shared fixture helpers for the tests that make layer directories on real
/// disk and put files in them -- `PathConfinementTests`, `SkillOverlayTests`
/// and `SkillDiscoveryTests`. The three need the same helpers, thus the
/// helpers are in this one file.
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
        let url = try preparedFileURL(at: relativePath, in: directory)
        try "Text of \(relativePath) in \(directory.lastPathComponent).\n"
            .write(to: url, atomically: true, encoding: .utf8)
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

    /// The first eight bytes of a PNG file, which are not UTF-8 text: the
    /// byte `0x89` can start no UTF-8 sequence.
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

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
