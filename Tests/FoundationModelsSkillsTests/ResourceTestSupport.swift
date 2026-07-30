import Foundation

/// Shared skill-fixture helper for `ResourceOpsTests` and `RunScriptTests`
/// -- both write a minimal, always-valid `SKILL.md` under a temp root;
/// `RunScriptTests`' `allowed-tools:` variant folds in as an optional
/// parameter, since the two were otherwise byte-identical (review findings,
/// 2026-07-29 22:27).
enum ResourceTestSupport {
    /// Writes a minimal, always-valid `id/SKILL.md` under `directory`,
    /// creating the skill's own subdirectory first.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and the
    ///     frontmatter's `name:` field.
    ///   - directory: The root to write under.
    ///   - allowedTools: The raw `allowed-tools:` frontmatter value to
    ///     write, or `nil` (the default) to omit the field entirely.
    /// - Returns: The created skill directory.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    @discardableResult
    static func writeMinimalSkillFile(id: String, in directory: URL, allowedTools: String? = nil) throws -> URL {
        let skillDirectory = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let allowedToolsLine = allowedTools.map { "allowed-tools: \"\($0)\"\n" } ?? ""
        try "---\nname: \(id)\ndescription: resource fixture.\n\(allowedToolsLine)---\nBody text for \(id).\n"
            .write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return skillDirectory
    }
}
