import Foundation
import FoundationModelsSkills
import Testing

/// Tests for `SkillDiagnostic`'s single-line rendering and provenance
/// carriage (M7, `^h9p1t54`): every severity renders consistently, and
/// provenance is present even for a diagnostic raised before a skill ever
/// decoded.
struct DiagnosticsRenderingTests {
    private static let provenance = SkillDiagnostic.Provenance(
        rootIndex: 1, root: URL(fileURLWithPath: "/repo/.skills", isDirectory: true))

    @Test(
        "each severity renders as \"[severity] id (root): message\"",
        arguments: [
            SkillDiagnostic.Severity.advisory,
            SkillDiagnostic.Severity.warning,
            SkillDiagnostic.Severity.skip,
        ])
    func severityRendersInOneLine(severity: SkillDiagnostic.Severity) {
        let diagnostic = SkillDiagnostic(
            severity: severity, skillID: "deploy", provenance: Self.provenance, message: "example message")

        #expect(diagnostic.description == "[\(severity.rawValue)] deploy (/repo/.skills): example message")
    }

    @Test func renderingCarriesTheWinningRootsPathNotJustItsIndex() {
        let diagnostic = SkillDiagnostic(
            severity: .warning, skillID: "lint",
            provenance: SkillDiagnostic.Provenance(
                rootIndex: 2, root: URL(fileURLWithPath: "/Users/example/.config/skills", isDirectory: true)),
            message: "missing description")

        #expect(diagnostic.description.contains("/Users/example/.config/skills"))
    }

    // MARK: - Provenance present even for an unparseable-YAML skip diagnostic

    @Test func skipDiagnosticForUnparseableYAMLStillCarriesProvenance() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticsRenderingTests-\(UUID().uuidString)", isDirectory: true)
        let skillDirectory = root.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "---\nname: [unterminated\n---\nBody.\n".write(
            to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let registry = SkillsRegistry(roots: [root])

        let skipDiagnostic = try #require(registry.diagnostics.first { $0.severity == .skip })
        #expect(skipDiagnostic.skillID == "broken")
        #expect(skipDiagnostic.provenance.root == root)
        #expect(skipDiagnostic.description.hasPrefix("[skip] broken (\(root.path)):"))
    }
}
