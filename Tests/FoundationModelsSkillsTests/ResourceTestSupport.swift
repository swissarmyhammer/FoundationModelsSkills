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

    /// Thrown by `writeMinimalSkillFile(id:in:allowedTools:)` when `id` is
    /// not a plain directory name, or `allowedTools` carries a character
    /// that would corrupt the written YAML frontmatter -- a test-authoring
    /// bug, never expected in practice, since every call site names a fixed
    /// literal.
    private struct UnsafeFixtureInput: Error {}

    /// Writes a minimal, always-valid `id/SKILL.md` under `directory`,
    /// creating the skill's own subdirectory first.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and the
    ///     frontmatter's `name:` field. Must be a plain name with no path
    ///     separators or `..` components.
    ///   - directory: The root to write under.
    ///   - allowedTools: The raw `allowed-tools:` frontmatter value to
    ///     write, or `nil` (the default) to omit the field entirely. Must
    ///     not contain a `"` or a newline, either of which would corrupt
    ///     the written YAML frontmatter's structure.
    /// - Returns: The created skill directory.
    /// - Throws: `UnsafeFixtureInput` if `id` is not a plain name or
    ///   `allowedTools` carries a YAML-structural character; otherwise
    ///   whatever `FileManager.createDirectory` or `String.write` throws.
    @discardableResult
    static func writeMinimalSkillFile(id: String, in directory: URL, allowedTools: String? = nil) throws -> URL {
        guard !id.contains("/"), !id.contains("..") else { throw UnsafeFixtureInput() }
        guard allowedTools?.contains("\"") != true, allowedTools?.contains("\n") != true else {
            throw UnsafeFixtureInput()
        }
        let skillDirectory = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let allowedToolsLine = allowedTools.map { "allowed-tools: \"\($0)\"\n" } ?? ""
        try "---\nname: \(id)\ndescription: resource fixture.\n\(allowedToolsLine)---\nBody text for \(id).\n"
            .write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return skillDirectory
    }
}
