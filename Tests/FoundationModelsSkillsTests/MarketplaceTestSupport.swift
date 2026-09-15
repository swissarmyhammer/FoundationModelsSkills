import Foundation

@testable import FoundationModelsSkills

/// Records each URL that a credential provider gets.
///
/// `CredentialGateTests` and `GitTransportTests` both prove that a credential
/// provider is asked one time, and with which URL. Thus the recorder is here,
/// and not in one of the two suites.
actor CredentialRequestRecorder {
    /// The URL of each request, in order.
    private(set) var requestedURLs: [URL] = []

    /// Records one request.
    ///
    /// - Parameter url: The URL that the provider got.
    func record(url: URL) {
        requestedURLs.append(url)
    }

    /// Makes a provider that records each request and gives `credential`.
    ///
    /// - Parameter credential: The credential that the provider gives.
    /// - Returns: The provider.
    nonisolated func provider(giving credential: MarketplaceCredential) -> @Sendable (URL) async -> MarketplaceCredential? {
        { url in
            await self.record(url: url)
            return credential
        }
    }
}

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
