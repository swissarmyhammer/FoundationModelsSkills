import Foundation

/// The shared file helpers of the marketplace tests. `MarketplaceCatalogTests`
/// and `MarketplaceConfigTests` both write text files into a temporary folder.
enum MarketplaceTestSupport {
    /// Makes a new temporary folder and writes a tree of text files into it.
    ///
    /// - Parameter files: The text of each file, keyed by its path in the
    ///   folder. The default is no file.
    /// - Returns: The new folder.
    /// - Throws: The error of a folder or file write.
    static func makeTempDirectory(withFiles files: [String: String] = [:]) throws -> URL {
        let root = try WatcherTestSupport.makeTempDirectory()
        for (path, text) in files {
            try writeFile(text: text, to: root.appendingPathComponent(path))
        }
        return root
    }

    /// Writes text to a file, and makes the folder of the file first.
    ///
    /// - Parameters:
    ///   - text: The text of the file.
    ///   - file: The file to write.
    /// - Throws: The error of the folder or the file write.
    static func writeFile(text: String, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}
