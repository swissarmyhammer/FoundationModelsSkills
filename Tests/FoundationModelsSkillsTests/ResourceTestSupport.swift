import Foundation
import FoundationModelsMetadataRegistry
import FoundationModelsSkills

/// Shared skill-fixture helpers for `ResourceOpsTests`, `RunScriptTests` and
/// `ScriptGateTests` -- each writes a minimal, always-valid `SKILL.md` under
/// a temp root and each builds a `SkillsToolContext` the identical way;
/// `RunScriptTests`' `allowed-tools:`/`policy` variants fold in as optional
/// parameters, since the two were otherwise byte-identical (review findings,
/// 2026-07-29 22:27 and 22:36).
///
/// The readers of one `run script` outcome are here for the same reason: two
/// test files unwrap a `RunScriptOutput`, thus neither keeps a copy of that
/// reader.
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
        makeContext(registry: SkillsRegistry(roots: roots, policy: policy))
    }

    /// Builds a `SkillsToolContext` over an already-built registry -- what a
    /// test that needs a registry shape `makeContext(roots:policy:)` cannot
    /// build (a marketplace-backed one, e.g.) calls.
    ///
    /// - Parameter registry: The registry the context dispatches against.
    /// - Returns: The assembled context.
    static func makeContext(registry: SkillsRegistry) -> SkillsToolContext {
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        return SkillsToolContext(registry: registry, searchAgent: SkillSearchAgent(searcher: searcher))
    }

    /// The `allowed-tools:` value that pre-approves every script of a skill.
    static let everyScriptGrant = "Script(scripts/*)"

    /// The result of a success outcome of `run script`, or `nil` for a
    /// corrective outcome.
    ///
    /// A test unwraps the value with `#require`, thus a corrective outcome
    /// fails the test instead of ending it before its assertions.
    ///
    /// - Parameter output: The outcome of one `run script` call.
    /// - Returns: The result, or `nil`.
    static func successResult(of output: RunScriptOutput) -> RunScriptResult? {
        if case .success(let result) = output {
            return result
        }
        return nil
    }

    /// The message of a corrective outcome of `run script`, or `nil` for a
    /// success outcome.
    ///
    /// The counterpart of `successResult(of:)`, for a test that holds the
    /// operation to a corrective message.
    ///
    /// - Parameter output: The outcome of one `run script` call.
    /// - Returns: The corrective message, or `nil`.
    static func correctiveMessage(of output: RunScriptOutput) -> String? {
        if case .corrective(let message) = output {
            return message
        }
        return nil
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

    /// The `scripts/` subdirectory under `id`'s skill directory, created if
    /// it does not already exist.
    ///
    /// - Parameters:
    ///   - id: The owning skill id.
    ///   - directory: The root the skill lives under.
    /// - Returns: The `scripts/` directory.
    /// - Throws: `UnsafeFixtureInput` if `id` is not a plain name; otherwise
    ///   whatever `FileManager.createDirectory` throws.
    static func scriptsDirectory(inSkillID id: String, under directory: URL) throws -> URL {
        guard !id.contains("/"), !id.contains("..") else { throw UnsafeFixtureInput() }
        let scriptsDirectory = directory.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        return scriptsDirectory
    }

    /// Writes an executable, shebang-carrying script named `name` under
    /// `id`'s `scripts/` directory.
    ///
    /// `RunScriptTests` needs a script that passes the direct-exec
    /// eligibility check, and the helper stands beside the other
    /// skill-fixture writers of this file.
    ///
    /// - Parameters:
    ///   - name: The script's file name -- a plain name with no path
    ///     separators or `..` components.
    ///   - id: The owning skill id.
    ///   - directory: The root the skill lives under.
    ///   - contents: The script's full text, shebang included. Defaults to
    ///     a minimal `echo hi` script.
    /// - Returns: The written script's URL, for a test that runs it
    ///   directly rather than through `RunScript`.
    /// - Throws: `UnsafeFixtureInput` if `name` is not a plain file name;
    ///   otherwise whatever `FileManager.createDirectory`, `String.write`,
    ///   or `LayerFixtureSupport.makeExecutable(_:)` throws.
    @discardableResult
    static func writeExecutableShebangScript(
        named name: String, inSkillID id: String, under directory: URL, contents: String = "#!/bin/sh\necho hi\n"
    ) throws -> URL {
        guard !name.contains("/"), !name.contains("..") else { throw UnsafeFixtureInput() }
        let scriptURL = try Self.scriptsDirectory(inSkillID: id, under: directory).appendingPathComponent(name)
        try contents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try LayerFixtureSupport.makeExecutable(scriptURL)
        return scriptURL
    }
}
