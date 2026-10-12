import Foundation

/// The shared noun both resource operations (`ListResource`, `ReadResource`)
/// act on.
internal let resourceOperationNoun = "resource"

/// The directory `RunScript` and `ScriptGate`'s bare-`Script` grant both
/// confine execution to.
internal let scriptsDirectoryPrefix = "scripts/"

/// The rules of a skill-relative resource path that open no file: whether the
/// path is well formed, whether it is hidden, and the text a resource
/// operation gives for a path it denies.
///
/// `ReadResource` and `RunScript` each read these, thus the two can never
/// differ on what counts as a relative path, or on the wording of the refusal.
/// The other half of the confinement rule is
/// `PathConfinement.isConfined(_:to:)` of `FoundationModelsExtras`, which each
/// lookup of the stack applies; `SkillOverlay.confines(_:)` puts the two
/// halves together.
internal enum ResourcePathRules {
    /// Whether `path` is not empty, is truly relative, and holds no `..`
    /// component.
    ///
    /// The check reads the text of the path alone, before any file access,
    /// thus `../x` and `/etc/passwd` are refused although nothing stands at
    /// that path. The text check of the Extras stack accepts a leading `~`,
    /// thus this check keeps that case of its own.
    ///
    /// - Parameter path: The candidate path.
    /// - Returns: Whether `path` is well formed.
    internal static func isWellFormedRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: true).contains("..")
    }

    /// The separator of the components of a path relative to a layer
    /// directory.
    private static let pathSeparator: Character = "/"

    /// The text that starts the name of a hidden path component.
    private static let hiddenComponentPrefix = "."

    /// Whether a component of `path` starts with a full stop, which makes the
    /// file itself, or a directory above it, hidden.
    ///
    /// `ListResource` keeps a hidden file out of a listing, and
    /// `SkillFileInclude` keeps an `{% include %}` from a hidden file. Both
    /// read this one rule, thus the two can never differ on what is hidden.
    ///
    /// - Parameter path: A path relative to a layer directory.
    /// - Returns: Whether `path` holds a hidden component.
    internal static func hasHiddenComponent(_ path: String) -> Bool {
        path.split(separator: pathSeparator).contains { $0.hasPrefix(hiddenComponentPrefix) }
    }

    /// The corrective message for a `path` that leaves the skill directory --
    /// shared by every resource operation that applies the confinement rule
    /// (`ReadResource`, `RunScript`), thus they can never differ on its
    /// wording.
    ///
    /// - Parameter path: The path that was refused.
    /// - Returns: The corrective message.
    internal static func deniedMessage(path: String) -> String {
        "The path `\(path)` is not accessible: it must resolve to a location inside the skill directory."
    }

    /// The example of a path relative to the skill directory that the texts
    /// for the model give, thus each text names the same example.
    internal static let examplePath = "references/guide.md"

    /// The description of the `path` parameter of each resource operation
    /// that reads one file of the skill (`ReadResource`, `RunScript`), thus
    /// the two can never differ on it.
    ///
    /// The model can give an absolute path, and `SkillOverlay.relativePath(for:)`
    /// accepts one that is in a layer directory of the skill, thus the text
    /// says so.
    internal static let pathParameterDescription =
        "The path of the file, relative to the skill directory, for example `\(examplePath)`. "
        + "An absolute path in the skill directory also works."
}

/// Shared "resolve `id` against the calling context's visible catalog"
/// lookup and corrective-message logic for `ListResource`, `ReadResource`,
/// and `RunScript`.
///
/// Resolves the conflict between two rules ("resource operations see only
/// the model-visible catalog", and "the CLI respects the same visibility
/// rules as the user surface -- it is a user, not a model") the same way
/// `UseSkill`/`ListSkill`/`SearchSkill` already
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
    /// Each of the three reaches this one time, in its own `execute(in:)`:
    /// `ListResource.execute(in:)` calls it and takes the paths of its rows
    /// from `SkillOverlay.entries()`, and `ReadResource.execute(in:)` and
    /// `RunScript.execute(in:)` each call it through
    /// `withResolvedPath(_:id:context:whenResolved:)` and find one file with
    /// `SkillOverlay.resolve(_:)`. No operation makes a URL of its own.
    ///
    /// The unit of override is the file, thus an operation that reads a file
    /// of a skill reads it through this overlay: a file that only a lower
    /// layer holds stays visible, and the copy of the highest layer wins.
    ///
    /// Two values stay outside the overlay, because the stack of
    /// `FoundationModelsExtras` gives neither one yet: the execute bit of a
    /// row of `ListResource`, and the execute bit with the shebang bytes of
    /// `RunScript`. When the stack of `FoundationModelsExtras` gives both,
    /// this package can take them up here.
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

    /// Resolves `id`, then finds the path of `path` relative to a layer
    /// directory of the skill, then runs `whenResolved` with that relative
    /// path and the overlay of the skill.
    ///
    /// `ReadResource` and `RunScript` each read one file of the skill, and the
    /// model can give the path of that file as an absolute path. This is the
    /// one place where the two find the relative path, thus the two can never
    /// differ on which absolute path they accept, or on the refusal.
    ///
    /// `SkillOverlay.relativePath(for:)` gives the relative path: a path
    /// with no leading `/` comes back with no change, and an absolute path
    /// gives its path relative to the highest layer directory that holds it.
    /// An absolute path that no layer directory of the skill holds gives the
    /// denied corrective, which names `path` as the model gave it.
    ///
    /// - Parameters:
    ///   - path: The path of the file, as the model gave it.
    ///   - id: The skill id to resolve.
    ///   - context: The shared context supplying the registry.
    ///   - whenResolved: Runs with the relative path and the overlay of the
    ///     skill; never runs when `id` does not resolve, or when no layer
    ///     directory of the skill holds an absolute `path`.
    /// - Returns: `whenResolved`'s result, the corrective message for an id
    ///   that did not resolve, or the denied corrective for `path`.
    internal static func withResolvedPath<Success: Encodable & Sendable & Equatable>(
        _ path: String, id: String, context: SkillsToolContext,
        whenResolved: (String, SkillOverlay) async -> CorrectiveOutcome<Success>
    ) async -> CorrectiveOutcome<Success> {
        await withResolvedOverlay(id: id, context: context) { overlay in
            guard let relativePath = overlay.relativePath(for: path) else {
                return .corrective(ResourcePathRules.deniedMessage(path: path))
            }
            return await whenResolved(relativePath, overlay)
        }
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
    /// `UseSkill.execute(in:)` also reads this overlay, after it renders the
    /// body, to list the files of the skill. That operation does its own
    /// visibility check before it renders, thus it does not come through
    /// `withResolvedOverlay(id:context:whenGranted:)`.
    ///
    /// - Parameters:
    ///   - id: The skill id, already resolved.
    ///   - context: The shared context supplying the registry.
    /// - Returns: The overlay over the layer directories of the skill.
    internal static func overlay(id: String, context: SkillsToolContext) -> SkillOverlay {
        SkillOverlay(directories: context.registry.contributingDirectories(id: id).map(\.directory))
    }

    /// The corrective message for an id that is unknown, stale, or not
    /// visible on this surface, carrying the current usable id list
    ///.
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
