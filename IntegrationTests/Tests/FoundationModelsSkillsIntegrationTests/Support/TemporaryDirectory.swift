import Foundation

/// The fixture-directory helper of the integration tests.
///
/// The unit test target has the same helper (`HotReloadTestSupport`), but a
/// test target of this package cannot link a test target of the root package.
/// Thus this package keeps its own copy.
enum TemporaryDirectory {
    /// Makes a new, empty temporary directory for a test root. Thus the
    /// file system changes of one test are never visible to a different test.
    ///
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    /// - Returns: The URL of the new directory.
    static func make() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
