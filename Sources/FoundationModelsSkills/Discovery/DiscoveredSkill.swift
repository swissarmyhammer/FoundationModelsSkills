import Foundation

/// One skill of the combined view `SkillDiscovery` reads over its layers.
///
/// Purely structural: `id` is the directory name, taken verbatim with no
/// agentskills.io/Claude validation applied -- that judgment belongs to the
/// downstream `SkillsRegistry`.
///
/// The unit of override is the file. `contributingDirectories` carries every
/// layer directory of the id, lowest precedence first, because each of them
/// gives the files that no higher layer holds. `skillDirectory`, `root` and
/// `rootIndex` name the one layer that gives the winning `SKILL.md`.
public struct DiscoveredSkill: Sendable, Equatable {
    /// One layer directory of a skill: `root/<id>/`, in a layer that holds it.
    ///
    /// A contributing directory gives each of its files that no higher layer
    /// holds, thus a layer that holds no `SKILL.md` of its own still
    /// contributes.
    public struct ContributingDirectory: Sendable, Equatable {
        /// This directory's layer position in the layer list `SkillDiscovery`
        /// was given, lowest precedence first.
        public var rootIndex: Int
        /// This directory's layer root.
        public var root: URL
        /// This directory itself, `root/<id>/`.
        public var skillDirectory: URL

        /// Creates a `ContributingDirectory`.
        ///
        /// - Parameters:
        ///   - rootIndex: This directory's layer position in the layer list,
        ///     lowest precedence first.
        ///   - root: This directory's layer root.
        ///   - skillDirectory: This directory itself.
        public init(rootIndex: Int, root: URL, skillDirectory: URL) {
            self.rootIndex = rootIndex
            self.root = root
            self.skillDirectory = skillDirectory
        }
    }

    /// The canonical id: the skill directory's name, verbatim.
    ///
    /// Never the frontmatter `name` -- discovery does no YAML parsing at all.
    public var id: String

    /// The directory of the winning `SKILL.md`, `root/<id>/`.
    public var skillDirectory: URL

    /// The winning `SKILL.md` file, `skillDirectory/SKILL.md`.
    public var skillFileURL: URL

    /// The winning `SKILL.md`'s layer position in the layer list
    /// `SkillDiscovery` was given, lowest precedence first.
    ///
    /// The provenance a diagnostic surface names when reporting where a
    /// skill was loaded from.
    public var rootIndex: Int

    /// The winning `SKILL.md`'s layer root.
    public var root: URL

    /// Every layer directory of this id, lowest precedence first.
    ///
    /// Holds a minimum of the directory of the winning `SKILL.md`, and holds
    /// a layer directory that gives no `SKILL.md` of its own as well: the
    /// files of that directory stay in the combined view of the skill.
    public var contributingDirectories: [ContributingDirectory]

    /// Creates a `DiscoveredSkill`.
    ///
    /// - Parameters:
    ///   - id: The canonical id: the skill directory's name, verbatim.
    ///   - skillDirectory: The directory of the winning `SKILL.md`.
    ///   - skillFileURL: The winning `SKILL.md` file.
    ///   - rootIndex: The winning `SKILL.md`'s layer position in the layer
    ///     list, lowest precedence first.
    ///   - root: The winning `SKILL.md`'s layer root.
    ///   - contributingDirectories: Every layer directory of this id, lowest
    ///     precedence first. Defaults to empty.
    public init(
        id: String,
        skillDirectory: URL,
        skillFileURL: URL,
        rootIndex: Int,
        root: URL,
        contributingDirectories: [ContributingDirectory] = []
    ) {
        self.id = id
        self.skillDirectory = skillDirectory
        self.skillFileURL = skillFileURL
        self.rootIndex = rootIndex
        self.root = root
        self.contributingDirectories = contributingDirectories
    }
}
