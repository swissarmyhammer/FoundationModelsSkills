import Foundation

/// The shared noun both resource operations (`ListResource`, `ReadResource`)
/// act on.
internal let resourceOperationNoun = "resource"

/// Shared "resolve `id` against the model-visible catalog" lookup and
/// corrective-message logic for `ListResource` and `ReadResource` (plan.md
/// §7.3, decision #22).
///
/// Resource operations see only the model-visible catalog, unlike
/// `UseSkill`'s surface-dependent `context.visibilityPredicate` -- plan.md
/// §7.3's own words: "All three see only the model-visible catalog."
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

    /// Resolves `id` against `context`'s model-visible catalog to its
    /// directory on disk, or the corrective message for an unusable id
    /// (decision #22) -- the single place `ListResource` and
    /// `ReadResource` share this id-resolution step, so neither repeats the
    /// visibility check, the directory lookup, and the message construction
    /// as its own inline guard.
    ///
    /// - Parameters:
    ///   - id: The skill id to resolve.
    ///   - context: The shared context supplying the registry.
    /// - Returns: `.success(_:)` carrying the matching entry's directory, or
    ///   `.corrective(_:)` when `id` is unknown, stale, or model-hidden.
    internal static func resolve(id: String, context: SkillsToolContext) -> Resolution {
        guard context.registry.metadata().contains(where: { $0.id == id && $0.isModelVisible }),
            let skillDirectory = context.registry.skillDirectory(id: id)
        else {
            return .corrective(Self.unusableIDMessage(id: id, context: context))
        }
        return .success(skillDirectory)
    }

    /// The corrective message for an id that is unknown, stale, or
    /// model-hidden, carrying the current model-visible id list (decision
    /// #22).
    ///
    /// - Parameters:
    ///   - id: The id that could not be resolved.
    ///   - context: The shared context supplying the registry.
    /// - Returns: The corrective message.
    private static func unusableIDMessage(id: String, context: SkillsToolContext) -> String {
        let prefix = "The skill id `\(id)` is not currently usable"
        let validIDs = context.registry.metadata().filter(\.isModelVisible).map(\.id).sorted()
        guard !validIDs.isEmpty else {
            return "\(prefix), and no skills are currently usable."
        }
        return "\(prefix). Currently usable ids: \(validIDs.joined(separator: ", "))."
    }
}
