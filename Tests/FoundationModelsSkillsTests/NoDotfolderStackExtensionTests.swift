import Foundation
import Testing

/// Guards the layer-list initializer of `DotfolderStack`: `FoundationModelsExtras`
/// gives `public init(layers:)`, thus this package adds nothing to that type.
///
/// This package carried a shim, `Discovery/DotfolderStack+Layers.swift`, while
/// Extras had no such initializer. A local extension that declares the same
/// signature again gives each call site two initializers of one signature, and
/// the build can then stop with an ambiguous use error.
///
/// The suite gives `SwiftSourceScan` the test of a line below, and that reader
/// walks every Swift file under `Sources/`. A line declares the extension when
/// it holds the text `extension DotfolderStack` and the character after that
/// text is not a letter or a digit. Thus `extension DotfolderStackFixture` is
/// not reported, and neither is a call of the initializer.
@Suite("No DotfolderStack extension")
struct NoDotfolderStackExtensionTests {
    /// The text that opens an extension of the layer stack.
    private static let extensionMarker = "extension DotfolderStack"

    /// The source directory, relative to the package root.
    private static let sourcesPath = "Sources"

    @Test(arguments: [
        "extension DotfolderStack {",
        "internal extension DotfolderStack.Layer {",
    ])
    func aLineThatOpensTheExtensionIsReported(line: String) {
        #expect(Self.declaresADotfolderStackExtension(line))
    }

    @Test(arguments: [
        "let stack = DotfolderStack(layers: layers)",
        "extension DotfolderStackFixture {",
        "extension SkillOverlay {",
    ])
    func aLineThatOpensNoSuchExtensionIsNotReported(line: String) {
        #expect(!Self.declaresADotfolderStackExtension(line))
    }

    @Test func noFileUnderSourcesExtendsTheLayerStack() throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.sourcesPath, matching: Self.declaresADotfolderStackExtension)

        #expect(
            offenders.isEmpty,
            """
            No file under Sources/ may extend DotfolderStack. Extras gives \
            public init(layers:); found: \(offenders.joined(separator: ", "))
            """)
    }

    /// Tells whether `line` opens an extension of `DotfolderStack` itself.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line holds the marker, and no letter and no
    ///   digit comes after the marker.
    private static func declaresADotfolderStackExtension(_ line: String) -> Bool {
        line.components(separatedBy: extensionMarker).dropFirst().contains { textAfterMarker in
            guard let next = textAfterMarker.first else { return true }
            return !next.isLetter && !next.isNumber
        }
    }
}
