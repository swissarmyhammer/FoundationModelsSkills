import Foundation

/// Shared fixture-directory helper for the tests that drive a real temp
/// directory tree -- `SkillWatcherTests` and `SkillsRegistryReloadTests` watch
/// one, `SkillOperationsTests` and `SingleImportTests` only need one -- and
/// all of them need an identical way to create it (mirrors
/// `HotReloadTestSupport`, the same pairing for `HotReloadTests`/
/// `HotReloadLiveTests`).
enum WatcherTestSupport {
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

    /// Makes a fresh, empty temporary directory, gives it to `body`, and
    /// removes the directory when `body` returns or throws.
    ///
    /// A test that needs a temporary directory and no other file operation
    /// calls this instead of `makeTempDirectory()` plus its own removal, so
    /// the test file names no `FileManager` of its own. `SingleImportTests`
    /// needs that, because it proves what one `import FoundationModelsSkills`
    /// makes visible and therefore keeps its import list short.
    ///
    /// - Parameter body: The work to do with the directory.
    /// - Returns: Whatever `body` returns.
    /// - Throws: Whatever `makeTempDirectory()` or `body` throws.
    static func withTempDirectory<Value>(_ body: (URL) throws -> Value) throws -> Value {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }
}
