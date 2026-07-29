import Foundation

/// Shared fixture-directory helper for `HotReloadTests` and
/// `HotReloadLiveTests` -- both drive a real, watched temp `.skills` root and
/// need an identical way to create one.
enum HotReloadTestSupport {
    /// Creates a fresh, empty temporary directory for a test root, so one
    /// test's filesystem activity can never be observed by another.
    ///
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    /// - Returns: The new directory's URL.
    static func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
