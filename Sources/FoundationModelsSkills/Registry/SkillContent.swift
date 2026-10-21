/// The content of one skill that loads, as `SkillsRegistry.skillContents()`
/// gives it: what a host sees of the skill, and the `SKILL.md` it comes from.
///
/// Two values are equal when the skill did not change between two catalog
/// generations. The `changes` subscription of the `skills` endpoint compares
/// them, thus an edit of any part of the `SKILL.md` — a frontmatter key that
/// no record shows, the body, or the `enabled` key — changes the skill.
struct SkillContent: Sendable, Equatable {
    /// The record of the skill, the skills that are off included.
    let record: SkillRecord

    /// The parsed frontmatter of the winning `SKILL.md`.
    ///
    /// Read by the synthesized `Equatable` conformance; periphery sees no caller.
    // periphery:ignore
    let frontmatter: SkillFrontmatter

    /// The body of the winning `SKILL.md`, not rendered.
    ///
    /// Read by the synthesized `Equatable` conformance; periphery sees no caller.
    // periphery:ignore
    let body: String
}
