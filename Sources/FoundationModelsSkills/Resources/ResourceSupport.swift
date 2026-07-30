import Foundation

/// The shared noun both resource operations (`ListResource`, `ReadResource`)
/// act on.
internal let resourceOperationNoun = "resource"

/// The directory `RunScript` and `ScriptGate`'s bare-`Script` grant both
/// confine execution to.
internal let scriptsDirectoryPrefix = "scripts/"

extension StringProtocol {
    /// This text split into lines by `\n`, without counting a final
    /// trailing newline as an extra, phantom empty line.
    ///
    /// Shared by `ReadResource` (over a decoded `String`) and
    /// `ScriptProcessRunner` (over captured process output), so the two
    /// can never drift on what counts as a line.
    internal var splitIntoLines: [SubSequence] {
        var lines = split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }
}

/// Shared "resolve `id` against the calling context's visible catalog"
/// lookup and corrective-message logic for `ListResource`, `ReadResource`,
/// and `RunScript` (plan.md §7.3, decision #22).
///
/// Resolves plan.md's own internal tension between §7.3 ("resource
/// operations see only the model-visible catalog") and §7.2 ("the CLI
/// respects the same visibility rules as the user surface -- it is a user,
/// not a model") the same way `UseSkill`/`ListSkill`/`SearchSkill` already
/// do: visibility comes from `context.visibilityPredicate`, not a hardcoded
/// `isModelVisible` check. A host's model-facing context still defaults
/// `visibilityPredicate` to `isModelVisible` (`SkillsToolContext`'s own
/// default), so nothing changes there; only a surface that supplies a
/// different predicate (e.g. `SkillsCLI`'s user-surface one) sees resource
/// ops honor it too, instead of the CLI inverting visibility relative to
/// `commandListing()`.
internal enum ResourceIDLookup {
    /// The outcome of resolving an id: its directory on disk, or the
    /// corrective message to return in its place.
    ///
    /// Named to match `CorrectiveOutcome`'s own `.success`/`.corrective`
    /// vocabulary, even though this type isn't itself `Encodable` -- callers
    /// switch on it once and build their own typed `CorrectiveOutcome` from
    /// whichever case they land in.
    internal enum Resolution {
        /// The id resolved to this directory.
        case success(URL)

        /// The id did not resolve; this is the corrective message to
        /// return.
        case corrective(String)
    }

    /// Resolves `id` against `context`'s visible catalog
    /// (`context.visibilityPredicate`'s subset) to its directory on disk, or
    /// the corrective message for an unusable id (decision #22) -- the
    /// single place `ListResource` and `ReadResource` share this
    /// id-resolution step, so neither repeats the visibility check, the
    /// directory lookup, and the message construction as its own inline
    /// guard.
    ///
    /// - Parameters:
    ///   - id: The skill id to resolve.
    ///   - context: The shared context supplying the registry and which
    ///     entries `context.visibilityPredicate` accepts.
    /// - Returns: `.success(_:)` carrying the matching entry's directory, or
    ///   `.corrective(_:)` when `id` is unknown, stale, or not visible on
    ///   this surface.
    internal static func resolve(id: String, context: SkillsToolContext) -> Resolution {
        guard
            context.registry.metadata().contains(where: { $0.id == id && context.visibilityPredicate($0) }),
            let skillDirectory = context.registry.skillDirectory(id: id)
        else {
            return .corrective(Self.unusableIDMessage(id: id, context: context))
        }
        return .success(skillDirectory)
    }

    /// Resolves `id`, then runs `whenGranted` with the resolved directory --
    /// the single place `ListResource`, `ReadResource`, and `RunScript`
    /// share this "resolve, then continue" shape, so none of the three
    /// repeats `resolve(id:context:)`'s switch as its own inline guard.
    ///
    /// - Parameters:
    ///   - id: The skill id to resolve.
    ///   - context: The shared context supplying the registry.
    ///   - whenGranted: Runs with the resolved directory once `id` resolves;
    ///     never runs at all when it doesn't.
    /// - Returns: `whenGranted`'s result, or the corrective message for an
    ///   id that didn't resolve.
    internal static func withResolvedDirectory<Success: Encodable & Sendable & Equatable>(
        id: String, context: SkillsToolContext, whenGranted: (URL) async -> CorrectiveOutcome<Success>
    ) async -> CorrectiveOutcome<Success> {
        switch Self.resolve(id: id, context: context) {
        case .corrective(let message):
            return .corrective(message)
        case .success(let skillDirectory):
            return await whenGranted(skillDirectory)
        }
    }

    /// The corrective message for an id that is unknown, stale, or not
    /// visible on this surface, carrying the current usable id list
    /// (decision #22).
    ///
    /// - Parameters:
    ///   - id: The id that could not be resolved.
    ///   - context: The shared context supplying the registry and which
    ///     entries `context.visibilityPredicate` accepts.
    /// - Returns: The corrective message.
    private static func unusableIDMessage(id: String, context: SkillsToolContext) -> String {
        let prefix = "The skill id `\(id)` is not currently usable"
        let validIDs = context.registry.metadata().filter(context.visibilityPredicate).map(\.id).sorted()
        guard !validIDs.isEmpty else {
            return "\(prefix), and no skills are currently usable."
        }
        return "\(prefix). Currently usable ids: \(validIDs.joined(separator: ", "))."
    }
}
