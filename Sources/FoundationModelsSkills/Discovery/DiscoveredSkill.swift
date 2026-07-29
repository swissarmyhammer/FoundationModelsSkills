import Foundation

/// One skill directory `SkillDiscovery` found while walking its host-supplied
/// layer roots (plan.md §3, §4).
///
/// Purely structural: `id` is the directory name, taken verbatim with no
/// agentskills.io/Claude validation applied -- that judgment belongs to the
/// downstream `SkillsRegistry`. `shadowedCandidates` carries every
/// lower-precedence directory of the same id that a later root's copy
/// replaced (decision #3's full-replace rule), so a diagnostic surface can
/// still report what shadowing happened even though only the winner's
/// `SKILL.md` is ever read.
public struct DiscoveredSkill: Sendable, Equatable {
    /// One lower-precedence root a shadowed copy of a skill's directory was
    /// found under.
    ///
    /// Carries the same root-provenance shape `DiscoveredSkill` itself uses
    /// for its winning root, so a shadowing advisory can name every losing
    /// candidate the same way it names the winner.
    public struct ShadowedCandidate: Sendable, Equatable {
        /// The shadowed candidate's position in the roots list `SkillDiscovery`
        /// was given, lowest precedence first.
        public var rootIndex: Int
        /// The shadowed candidate's layer root.
        public var root: URL
        /// The shadowed candidate's own skill directory, `root/<id>/`.
        public var skillDirectory: URL

        /// Creates a `ShadowedCandidate`.
        ///
        /// - Parameters:
        ///   - rootIndex: The shadowed candidate's position in the roots list,
        ///     lowest precedence first.
        ///   - root: The shadowed candidate's layer root.
        ///   - skillDirectory: The shadowed candidate's own skill directory.
        public init(rootIndex: Int, root: URL, skillDirectory: URL) {
            self.rootIndex = rootIndex
            self.root = root
            self.skillDirectory = skillDirectory
        }
    }

    /// The canonical id: the skill directory's name, verbatim.
    ///
    /// Never the frontmatter `name` -- discovery does no YAML parsing at all
    /// (plan.md §4).
    public var id: String

    /// The winning skill's own directory, `root/<id>/`.
    public var skillDirectory: URL

    /// The winning skill's `SKILL.md` file, `skillDirectory/SKILL.md`.
    public var skillFileURL: URL

    /// The winning root's position in the roots list `SkillDiscovery` was
    /// given, lowest precedence first.
    ///
    /// The provenance a diagnostic surface names when reporting where a
    /// skill was loaded from.
    public var rootIndex: Int

    /// The winning root itself.
    public var root: URL

    /// Every lower-precedence directory of this id that the winning copy
    /// replaced, in the order they were shadowed (lowest precedence first).
    ///
    /// Empty when no lower-precedence root also carried this id. Populated
    /// only for the shadowing advisory (plan.md §4) -- none of these
    /// candidates' `SKILL.md` files are ever read.
    public var shadowedCandidates: [ShadowedCandidate]

    /// Creates a `DiscoveredSkill`.
    ///
    /// - Parameters:
    ///   - id: The canonical id: the skill directory's name, verbatim.
    ///   - skillDirectory: The winning skill's own directory.
    ///   - skillFileURL: The winning skill's `SKILL.md` file.
    ///   - rootIndex: The winning root's position in the roots list, lowest
    ///     precedence first.
    ///   - root: The winning root itself.
    ///   - shadowedCandidates: Every lower-precedence directory of this id
    ///     the winning copy replaced. Defaults to empty.
    public init(
        id: String,
        skillDirectory: URL,
        skillFileURL: URL,
        rootIndex: Int,
        root: URL,
        shadowedCandidates: [ShadowedCandidate] = []
    ) {
        self.id = id
        self.skillDirectory = skillDirectory
        self.skillFileURL = skillFileURL
        self.rootIndex = rootIndex
        self.root = root
        self.shadowedCandidates = shadowedCandidates
    }
}
