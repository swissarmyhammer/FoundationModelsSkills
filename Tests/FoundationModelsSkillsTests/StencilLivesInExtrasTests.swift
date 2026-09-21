import Foundation
import Testing

/// Guards the home of the Stencil work: `FoundationModelsExtras` holds it,
/// and this package holds none of it.
///
/// The stenciled stack of Extras renders each text. It builds the context of
/// a render, it takes the trust from the layer, it scopes the partials, and
/// it gives each quarantined span to Stencil as a value. The names below are
/// the names of that machinery, thus a file of `Sources/` that holds one of
/// them has taken a copy of work that Extras already does.
///
/// The reader walks each Swift file under `Sources/`, and it reports a line
/// that holds one of the names. The error of a render holds the text
/// `TemplateEngine` in its own name, thus the same check keeps that error
/// out of this package as well: the error travels out of the call of the
/// stack, and no file of this package names it.
@Suite("Stencil lives in Extras")
struct StencilLivesInExtrasTests {
    /// The names of the Stencil machinery of Extras.
    private static let stencilNames = [
        "TemplateEngine", "TemplateContext", "TemplateValue", "WellKnownValues",
    ]

    /// The source directory, relative to the package root.
    private static let sourcesPath = "Sources"

    /// The directory of the render passes, relative to the package root.
    private static let renderPath = "Sources/FoundationModelsSkills/Render"

    /// The name of the file reader of Foundation. A render pass opens no
    /// file: the stack of Extras reads each partial that an `{% include %}`
    /// names, and it reads the working directory of a render.
    private static let fileReaderName = "FileManager"

    @Test(arguments: StencilLivesInExtrasTests.stencilNames)
    func noFileUnderSourcesNamesTheStencilMachinery(name: String) throws {
        let offenders = try SwiftSourceScan.reportedLines(inDirectory: Self.sourcesPath) { $0.contains(name) }

        #expect(
            offenders.isEmpty,
            """
            No file under \(Self.sourcesPath)/ may name \(name). The stenciled \
            stack of FoundationModelsExtras holds the Stencil work; found: \
            \(offenders.joined(separator: ", "))
            """)
    }

    @Test func noRenderPassNamesTheFileReader() throws {
        let offenders = try SwiftSourceScan.reportedLines(inDirectory: Self.renderPath) {
            $0.contains(Self.fileReaderName)
        }

        #expect(
            offenders.isEmpty,
            """
            No file under \(Self.renderPath)/ may name \(Self.fileReaderName). \
            A render pass opens no file; found: \(offenders.joined(separator: ", "))
            """)
    }
}
