import Foundation

/// The shared noun both resource operations (`ListResource`, `ReadResource`)
/// act on.
internal let resourceOperationNoun = "resource"

/// The directory `RunScript` and `ScriptGate`'s bare-`Script` grant both
/// confine execution to.
internal let scriptsDirectoryPrefix = "scripts/"

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
    /// Resolves `id`, then runs `whenGranted` with the combined view of the
    /// layer directories of the skill -- the single place `ListResource`,
    /// `ReadResource` and `RunScript` share this "resolve, then continue"
    /// shape, so none of the three repeats the visibility check, the
    /// directory lookup and the message construction as its own inline guard.
    ///
    /// Each of the three calls this one time, in its own `execute(in:)`:
    /// `ListResource.execute(in:)` takes the paths of its rows from
    /// `SkillOverlay.entries()`, and `ReadResource.execute(in:)` and
    /// `RunScript.execute(in:)` each find one file with
    /// `SkillOverlay.resolve(_:)`. No operation makes a URL of its own.
    ///
    /// The unit of override is the file, thus an operation that reads a file
    /// of a skill reads it through this overlay: a file that only a lower
    /// layer holds stays visible, and the copy of the highest layer wins.
    ///
    /// Two values stay outside the overlay, because the stack of
    /// `FoundationModelsExtras` gives neither one yet: the execute bit of a
    /// row of `ListResource`, and the execute bit with the shebang bytes of
    /// `RunScript`. Card `^00nmjzg` of the `FoundationModelsExtras` board adds
    /// both to the stack, and card `^yraq5xe` of this board then takes them up
    /// here.
    ///
    /// - Parameters:
    ///   - id: The skill id to resolve.
    ///   - context: The shared context supplying the registry.
    ///   - whenGranted: Runs with the overlay of the skill once `id`
    ///     resolves; never runs at all when it does not.
    /// - Returns: `whenGranted`'s result, or the corrective message for an
    ///   id that did not resolve.
    internal static func withResolvedOverlay<Success: Encodable & Sendable & Equatable>(
        id: String, context: SkillsToolContext, whenGranted: (SkillOverlay) async -> CorrectiveOutcome<Success>
    ) async -> CorrectiveOutcome<Success> {
        guard Self.isUsable(id: id, context: context) else {
            return .corrective(Self.unusableIDMessage(id: id, context: context))
        }
        return await whenGranted(Self.overlay(id: id, context: context))
    }

    /// Whether `id` names a skill of the catalog that
    /// `context.visibilityPredicate` accepts, and that the registry still
    /// holds a directory for.
    ///
    /// - Parameters:
    ///   - id: The skill id to check.
    ///   - context: The shared context supplying the registry and which
    ///     entries `context.visibilityPredicate` accepts.
    /// - Returns: Whether an operation of this surface may use `id`.
    private static func isUsable(id: String, context: SkillsToolContext) -> Bool {
        context.registry.metadata().contains { $0.id == id && context.visibilityPredicate($0) }
            && context.registry.skillDirectory(id: id) != nil
    }

    /// The combined view of the layer directories of `id`.
    ///
    /// Every catalog entry carries a minimum of one contributing directory --
    /// the directory that gives its `SKILL.md` -- thus the overlay of an id
    /// that resolved holds a minimum of one directory.
    ///
    /// - Parameters:
    ///   - id: The skill id, already resolved.
    ///   - context: The shared context supplying the registry.
    /// - Returns: The overlay over the layer directories of the skill.
    private static func overlay(id: String, context: SkillsToolContext) -> SkillOverlay {
        SkillOverlay(directories: context.registry.contributingDirectories(id: id).map(\.directory))
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
