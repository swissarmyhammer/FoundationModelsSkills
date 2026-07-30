import Foundation
import FoundationModelsMetadataRegistry
import FoundationModelsSkills

/// Shared skill-fixture helpers for `ResourceOpsTests` and `RunScriptTests`
/// -- both write a minimal, always-valid `SKILL.md` under a temp root and
/// both build a `SkillsToolContext` the identical way; `RunScriptTests`'
/// `allowed-tools:`/`policy` variants fold in as optional parameters, since
/// the two were otherwise byte-identical (review findings, 2026-07-29
/// 22:27 and 22:36).
enum ResourceTestSupport {
    /// Builds a `SkillsToolContext` over `roots`, under `policy`.
    ///
    /// Wraps a real, GPU-free `.retrieval`-mode `MetadataSearcher` standing
    /// in for the stub-searcher context the resource/run-script op tests
    /// use -- neither dispatches through it, but `SkillsToolContext` still
    /// requires one.
    ///
    /// - Parameters:
    ///   - roots: The registry roots to build over.
    ///   - policy: The render policy the registry is constructed with.
    ///     Defaults to the permissive `RenderPolicy()`.
    /// - Returns: The assembled context.
    static func makeContext(roots: [URL], policy: RenderPolicy = RenderPolicy()) -> SkillsToolContext {
        let registry = SkillsRegistry(roots: roots, policy: policy)
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        return SkillsToolContext(registry: registry, searchAgent: SkillSearchAgent(searcher: searcher))
    }

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
