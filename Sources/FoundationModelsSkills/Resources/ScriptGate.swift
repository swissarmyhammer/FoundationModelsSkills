import Darwin
import Foundation

/// The outcome of evaluating `ScriptGate`'s two code-enforced gates.
internal enum ScriptGateResult {
    /// Both gates passed; the script may run.
    case granted

    /// A gate failed; this is the corrective message to return.
    case corrective(String)
}

/// The triple gate `run script` enforces at dispatch, before ever touching
/// the filesystem for the requested script (plan.md §7.3.1, decision #28):
///
/// 1. **Host policy** -- `RenderPolicy.isScriptExecutionDisabled`, set once
///    at registry construction, so every dispatch path (model, `/command`,
///    CLI) honors the same host-level kill switch.
/// 2. **Per-skill grant** -- the skill's `allowed-tools:` frontmatter must
///    contain a `Script(<glob>)` token whose glob matches the requested
///    path, or a bare `Script` token (grants everything under `scripts/`).
///    A skill without a matching grant has not pre-approved script
///    execution.
/// 3. **Trust posture** -- plan.md §8's guidance that a host should not
///    construct a script-enabled registry over an untrusted project root at
///    all. This is documentation-only: `evaluate(path:allowedTools:
///    isScriptExecutionDisabled:)` has no way to observe how trustworthy
///    its own registry's roots are, so there is no third code path here to
///    enforce it -- a host that needs this guarantee enforces it itself, at
///    the point it decides which roots to construct a registry over.
internal enum ScriptGate {
    /// Evaluates gates 1 and 2 for `path`.
    ///
    /// - Parameters:
    ///   - path: The skill-relative script path being requested.
    ///   - allowedTools: The skill's tokenized `allowed-tools:` frontmatter.
    ///   - isScriptExecutionDisabled: The host policy's kill switch (gate 1).
    /// - Returns: `.granted` when both gates pass; `.corrective(_:)` naming
    ///   whichever gate failed first.
    internal static func evaluate(
        path: String, allowedTools: [String], isScriptExecutionDisabled: Bool
    ) -> ScriptGateResult {
        let hostPolicyResult = Self.evaluateHostPolicy(isScriptExecutionDisabled: isScriptExecutionDisabled)
        guard case .granted = hostPolicyResult else { return hostPolicyResult }
        return Self.evaluateGrant(path: path, allowedTools: allowedTools)
    }

    /// Evaluates gate 1 (host policy) alone, independent of any id/path
    /// resolution.
    ///
    /// Callable before `RunScript.execute(in:)` ever looks up the requested
    /// id or resolves its path, so a script-disabled registry returns the
    /// identical corrective for any path -- valid, bogus, or
    /// confinement-escaping alike -- rather than leaking a path-shaped
    /// corrective ahead of the policy check (plan.md §7.3.1: "triple-gated,
    /// every check at dispatch").
    ///
    /// - Parameter isScriptExecutionDisabled: The host policy's kill switch.
    /// - Returns: `.granted` when script execution is enabled;
    ///   `.corrective(_:)` naming the host policy when it is not.
    internal static func evaluateHostPolicy(isScriptExecutionDisabled: Bool) -> ScriptGateResult {
        isScriptExecutionDisabled ? .corrective(Self.hostPolicyDisabledMessage) : .granted
    }

    /// Evaluates gate 2 (per-skill grant) alone.
    ///
    /// - Parameters:
    ///   - path: The skill-relative script path being requested.
    ///   - allowedTools: The skill's tokenized `allowed-tools:` frontmatter.
    /// - Returns: `.granted` when `path` is covered by a grant;
    ///   `.corrective(_:)` naming the missing grant otherwise.
    internal static func evaluateGrant(path: String, allowedTools: [String]) -> ScriptGateResult {
        Self.isGranted(allowedTools: allowedTools, path: path)
            ? .granted : .corrective(Self.noGrantMessage(path: path))
    }

    /// The corrective message for gate 1: script execution disabled at the
    /// host level.
    private static let hostPolicyDisabledMessage = "Script execution is disabled for this registry."

    /// The corrective message for gate 2: no matching `allowed-tools:` grant.
    ///
    /// - Parameter path: The path that drew no matching grant.
    /// - Returns: The corrective message.
    private static func noGrantMessage(path: String) -> String {
        "This skill has not pre-approved script execution for `\(path)`. "
            + "Add an `allowed-tools: \"Script(\(scriptsDirectoryPrefix)*)\"` grant (or a narrower glob covering this path) "
            + "to its SKILL.md frontmatter."
    }

    /// The `allowed-tools:` token name a script grant is spelled with.
    private static let scriptTokenName = "Script"

    /// Whether `allowedTools` grants execution of `path`.
    ///
    /// - Parameters:
    ///   - allowedTools: The skill's tokenized `allowed-tools:` frontmatter.
    ///   - path: The skill-relative script path being requested.
    /// - Returns: `true` when a bare `Script` token (and `path` is under
    ///   `scripts/`) or a `Script(<glob>)` token whose glob matches `path`
    ///   is present.
    private static func isGranted(allowedTools: [String], path: String) -> Bool {
        allowedTools.contains { token in
            guard token.hasPrefix(Self.scriptTokenName) else { return false }
            let remainder = token.dropFirst(Self.scriptTokenName.count)
            guard !remainder.isEmpty else {
                return path.hasPrefix(scriptsDirectoryPrefix)
            }
            guard remainder.hasPrefix("("), remainder.hasSuffix(")") else { return false }
            let glob = String(remainder.dropFirst().dropLast())
            return Self.matches(glob: glob, path: path)
        }
    }

    /// Whether `path` matches `glob`, via POSIX `fnmatch` with `FNM_PATHNAME`
    /// so `*` never crosses a `/` the way a shell glob wouldn't.
    ///
    /// - Parameters:
    ///   - glob: The glob to match against.
    ///   - path: The skill-relative path being checked.
    /// - Returns: Whether `path` matches `glob`.
    private static func matches(glob: String, path: String) -> Bool {
        fnmatch(glob, path, FNM_PATHNAME) == 0
    }
}
