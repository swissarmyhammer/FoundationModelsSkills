import Foundation

/// Shared fixture helpers for the tests of the combined view of one skill --
/// `PathConfinementTests` and `SkillOverlayTests`. Both make more than one
/// layer directory on real disk and put files in them, thus the two need the
/// same helpers.
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
    /// made more than one of them.
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
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Text of \(relativePath) in \(directory.lastPathComponent).\n"
            .write(to: url, atomically: true, encoding: .utf8)
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
}
