import Foundation
import FoundationModels
import Operations

/// The outcome of a `run script` operation: either the process's result or
/// a corrective message (plan.md §7.3.1).
///
/// An unknown/stale/model-hidden `id`, a path confinement violation, a path
/// not under `scripts/`, a triple-gate refusal, or a missing executable
/// bit/shebang are the conditions `RunScript.execute(in:)` fails
/// correctively on.
public typealias RunScriptOutput = CorrectiveOutcome<RunScriptResult>

/// The noun `run script` acts on -- distinct from `resourceOperationNoun`
/// (`"resource"`, shared by `list resource`/`read resource`): plan.md §7.3
/// names this op's canonical spelling `run script`, not `run resource`.
internal let scriptOperationNoun = "script"

/// Exec's a skill's script file directly, under the triple gate (plan.md
/// §7.3.1), in its own process group, capturing merged stdout+stderr.
///
/// Sees only the model-visible catalog, like `ListResource`/`ReadResource`.
/// Never guesses an interpreter: the target file must already carry both
/// the executable bit and a shebang line, or the run is refused with a
/// corrective naming the fix.
public struct RunScript: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: the process's outcome, or a corrective
    /// message.
    public typealias Output = RunScriptOutput

    /// The skill id owning the script.
    public var id: String

    /// The script's path, relative to the skill directory, under `scripts/`.
    public var path: String

    /// Positional arguments to pass to the script.
    public var arguments: [String]?

    /// Seconds to allow before killing the script's process group; `nil`
    /// defaults to `defaultTimeoutSeconds`.
    public var timeout: Int?

    /// Creates a `RunScript` operation by directly assigning its
    /// parameters, bypassing `GeneratedContent` decoding.
    ///
    /// - Parameters:
    ///   - id: The skill id owning the script.
    ///   - path: The script's path, relative to the skill directory.
    ///   - arguments: Positional arguments to pass to the script.
    ///   - timeout: Seconds to allow before killing the script's process
    ///     group; `nil` defaults to `defaultTimeoutSeconds`.
    public init(id: String, path: String, arguments: [String]? = nil, timeout: Int? = nil) {
        self.id = id
        self.path = path
        self.arguments = arguments
        self.timeout = timeout
    }

    /// The action this operation performs: `"run"`.
    public static let verb = "run"

    /// The resource this operation acts on: `"script"`.
    public static let noun = scriptOperationNoun

    /// A human- and model-facing summary of what this operation does.
    public static let operationDescription =
        "Execute a skill's script file directly, under the triple gate, capturing merged stdout+stderr."

    /// This operation's parameters, as the resolver and schema fusion need
    /// them: `id`/`path` (required), `arguments`/`timeout` (optional).
    public static let parameterMetadata: [ParamMeta] = [
        ParamMeta(name: idKey, type: .string, required: true, description: "The skill id owning the script."),
        ParamMeta(
            name: pathKey, type: .string, required: true,
            description: "The script's path, relative to the skill directory, under \(scriptsDirectoryPrefix)."),
        ParamMeta(
            name: argumentsKey, type: .array(of: .string), required: false,
            description: "Positional arguments to pass to the script."),
        ParamMeta(
            name: timeoutKey, type: .integer, required: false,
            description: "Seconds to allow before killing the script's process group. Defaults to \(Self.defaultTimeoutSeconds)."
        ),
    ]

    /// The `GeneratedContent` property name for `id`.
    private static let idKey = "id"

    /// The `GeneratedContent` property name for `path`.
    private static let pathKey = "path"

    /// The `GeneratedContent` property name for `arguments`.
    private static let argumentsKey = "arguments"

    /// The `GeneratedContent` property name for `timeout`.
    private static let timeoutKey = "timeout"

    /// Decodes a `RunScript` from a resolved `GeneratedContent` payload.
    ///
    /// - Parameter content: The payload to decode, already resolved to this
    ///   operation's canonical parameter names.
    /// - Throws: Whatever `content.value(_:forProperty:)` throws for a
    ///   missing or mistyped `id`/`path`.
    public init(_ content: GeneratedContent) throws {
        id = try content.value(String.self, forProperty: Self.idKey)
        path = try content.value(String.self, forProperty: Self.pathKey)
        arguments = try? content.value([String].self, forProperty: Self.argumentsKey)
        timeout = try content.value(Int?.self, forProperty: Self.timeoutKey)
    }

    /// This operation's parameters re-encoded as `GeneratedContent`, e.g. for
    /// the CLI driver's round trip back to the model-facing payload shape.
    public var generatedContent: GeneratedContent {
        GeneratedContentBuilder.make(
            required: [(Self.idKey, id), (Self.pathKey, path)],
            optional: [(Self.argumentsKey, arguments), (Self.timeoutKey, timeout)])
    }

    /// The `timeout` used when the caller omits one.
    public static let defaultTimeoutSeconds = 60

    /// Runs `path` under `id`'s directory, or returns a corrective message.
    ///
    /// Evaluates gate 1 (host policy) first, before any id lookup or path
    /// resolution (plan.md §7.3.1: "triple-gated, every check at dispatch"):
    /// a script-disabled registry returns the identical policy corrective
    /// for any `path` -- valid, unknown-id, or confinement-escaping alike --
    /// never a path-shaped corrective ahead of the policy check.
    ///
    /// - Parameter context: The shared context supplying the model-visible
    ///   registry.
    /// - Returns: `.success(_:)` carrying the process's outcome;
    ///   `.corrective(_:)` for a disabled host policy, an unusable id, a
    ///   confinement/scripts-prefix violation, a gate refusal, or a missing
    ///   executable bit/shebang.
    /// - Throws: Nothing; the signature carries `throws` to satisfy the
    ///   `OperationDefinition` protocol requirement.
    public func execute(in context: SkillsToolContext) async throws -> RunScriptOutput {
        let hostPolicyResult = ScriptGate.evaluateHostPolicy(
            isScriptExecutionDisabled: context.registry.policy.isScriptExecutionDisabled)
        if case .corrective(let message) = hostPolicyResult {
            return .corrective(message)
        }

        return await ResourceIDLookup.withResolvedDirectory(id: id, context: context) { skillDirectory in
            guard path.hasPrefix(scriptsDirectoryPrefix) else {
                return .corrective(Self.notUnderScriptsMessage(path: path))
            }
            guard let resolved = PathConfinement.resolvedURL(relativePath: path, in: skillDirectory) else {
                return .corrective(PathConfinement.deniedMessage(path: path))
            }

            let allowedTools = context.registry.allowedTools(id: id) ?? []
            if case .corrective(let message) = ScriptGate.evaluateGrant(path: path, allowedTools: allowedTools) {
                return .corrective(message)
            }

            if let issue = Self.executabilityIssue(path: path, at: resolved) {
                return .corrective(issue)
            }

            let outcome = await ScriptProcessRunner.run(
                executableURL: resolved, arguments: arguments ?? [], workingDirectory: skillDirectory,
                timeout: TimeInterval(timeout ?? Self.defaultTimeoutSeconds))

            return .success(
                RunScriptResult(
                    id: id, path: path, status: outcome.status.rawValue, exitCode: outcome.exitCode.map(Int.init),
                    durationMs: outcome.durationMs, lines: outcome.lines, output: outcome.output))
        }
    }

    // MARK: - "must be under scripts/" corrective

    /// The corrective message for a `path` not under `scriptsDirectoryPrefix`.
    ///
    /// - Parameter path: The path that was rejected.
    /// - Returns: The corrective message.
    private static func notUnderScriptsMessage(path: String) -> String {
        "The path `\(path)` is not runnable: `run script` only executes files under `\(scriptsDirectoryPrefix)`."
    }

    // MARK: - Direct-exec eligibility (executable bit + shebang)

    /// The first two bytes a shebang line starts with.
    private static let shebangPrefix = Data("#!".utf8)

    /// The fix for a missing executable bit, as it reads inside "must
    /// {requirement}.".
    private static let executableBitRequirement = "have the executable bit set (e.g. `chmod +x`)"

    /// The fix for a missing shebang line, as it reads inside "must
    /// {requirement}.".
    private static let shebangRequirement = "start with a shebang line (e.g. `#!/bin/sh`)"

    /// Whichever direct-exec requirement(s) `resolved` fails, or `nil` when
    /// all are satisfied.
    ///
    /// - Parameters:
    ///   - path: The script's path, relative to the skill directory,
    ///     carried into the corrective message.
    ///   - resolved: The script's resolved, confined URL.
    /// - Returns: A corrective message naming the missing requirement(s),
    ///   or `nil` when the file has both the executable bit and a shebang.
    private static func executabilityIssue(path: String, at resolved: URL) -> String? {
        var unmet: [String] = []
        if !FileManager.default.isExecutableFile(atPath: resolved.path) {
            unmet.append(Self.executableBitRequirement)
        }
        if !Self.hasShebang(at: resolved) {
            unmet.append(Self.shebangRequirement)
        }
        guard !unmet.isEmpty else { return nil }
        return "The script `\(path)` must \(unmet.joined(separator: " and "))."
    }

    /// Whether the file at `url` starts with `shebangPrefix`.
    ///
    /// - Parameter url: The file to check.
    /// - Returns: `true` when the file's first two bytes are `"#!"`.
    private static func hasShebang(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return handle.readData(ofLength: Self.shebangPrefix.count) == Self.shebangPrefix
    }
}
