import FoundationModelsExtras

/// One skill on disk, as `SkillsRegistry.records()` gives it to a host view:
/// its id, its rendered description, its parameter placeholders, the layer
/// and the marketplace it comes from, and whether it is on.
///
/// A record exists for each skill that loads, also for a skill that its
/// `enabled` key turns off. That is the difference to `SkillMetadata`, which
/// a model surface reads: the catalog of the model never holds a skill that
/// is off. A host view, for example the `skills` GraphQL endpoint, shows the
/// skills that are off too, so that a person can turn them on again.
public struct SkillRecord: Sendable, Equatable {
    /// The canonical id -- the directory name.
    public var id: String

    /// The rendered `description:`, or an empty string when the skill's
    /// frontmatter carries none.
    public var description: String

    /// Placeholder summaries of this skill's parameters, e.g. `"<message>"`,
    /// `"[env]"`.
    public var parameters: [String]

    /// The layer of the dotfolder stack that gives the winning `SKILL.md`.
    public var layer: DotfolderStack.Source

    /// The marketplace this skill came from, for example
    /// `swissarmyhammer-skills@1a2b3c4`, or `nil` for a local skill.
    public var marketplace: String?

    /// Whether the skill is on: `false` when its `enabled` key turns it off,
    /// or when that key holds a value that is not a bool.
    public var isEnabled: Bool
}
