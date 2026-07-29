/// One row of the `SkillsRegistry.commandListing()` user `/` menu surface
/// (plan.md §6.1) -- structured, parsed parameters (via `ParameterInference`)
/// rather than the raw frontmatter strings `SkillFrontmatter` carries.
///
/// Autocomplete, fuzzy search, and input validation are the UI's job, out of
/// scope here -- this type is data only.
public struct SkillListing: Sendable, Equatable {
    /// The directory name -- the canonical id and the `/command` key (plan.md
    /// §4), never the frontmatter `name`.
    public var id: String

    /// The frontmatter `name:` -- optional because Claude-style inputs (a
    /// `.claude/commands/foo.md`, or a `SKILL.md` without `name:`) may omit
    /// it (plan.md §4); agentskills.io-conforming skills always have one,
    /// validated against `id` by the downstream `SkillsRegistry`.
    public var displayName: String?

    /// The frontmatter `description:`, unrendered at this layer -- §5
    /// passes 1+3 rendering is the registry/render-pipeline's job, not this
    /// data model's.
    public var description: String?

    /// The frontmatter `license:` -- free text, data only (plan.md §4).
    public var license: String?

    /// The frontmatter `compatibility:` -- free text, data only (plan.md
    /// §4).
    public var compatibility: String?

    /// Parsed positional parameters, merged from up to three sources by
    /// `ParameterInference` (plan.md §6.1).
    public var parameters: [SkillParameter]

    /// Whether the skill body references `$ARGUMENTS` -- a meaningful
    /// free-form tail the UI should prompt for.
    ///
    /// `true` only on an actual `$ARGUMENTS` reference; the §5 auto-append
    /// fallback (`ARGUMENTS: <value>` when `$ARGUMENTS` is absent) never sets
    /// this.
    public var acceptsTrailingArguments: Bool

    /// Creates a `SkillListing` by directly assigning every field --
    /// primarily for tests and callers building a listing row by hand.
    ///
    /// Use `init(id:frontmatter:body:)` or `init(id:decodedSkill:)` to derive
    /// `parameters`/`acceptsTrailingArguments` from a skill's decoded
    /// frontmatter and body instead of supplying them directly.
    ///
    /// - Parameters:
    ///   - id: The directory name -- the canonical id (plan.md §4).
    ///   - displayName: The frontmatter `name:`, or `nil`.
    ///   - description: The frontmatter `description:`, unrendered.
    ///   - license: The frontmatter `license:`, or `nil`.
    ///   - compatibility: The frontmatter `compatibility:`, or `nil`.
    ///   - parameters: Parsed positional parameters.
    ///   - acceptsTrailingArguments: Whether the body references
    ///     `$ARGUMENTS`.
    public init(
        id: String,
        displayName: String? = nil,
        description: String? = nil,
        license: String? = nil,
        compatibility: String? = nil,
        parameters: [SkillParameter] = [],
        acceptsTrailingArguments: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.license = license
        self.compatibility = compatibility
        self.parameters = parameters
        self.acceptsTrailingArguments = acceptsTrailingArguments
    }

    /// Builds a listing row for one decoded skill: the spec fields copy
    /// straight from `frontmatter`; `parameters` and
    /// `acceptsTrailingArguments` are derived by
    /// `ParameterInference.infer(frontmatter:body:)` over `frontmatter` and
    /// `body` (plan.md §6.1).
    ///
    /// Inference diagnostics (source-mismatch notes) are not carried on this
    /// type -- callers that need them call `ParameterInference.infer`
    /// directly; the downstream `SkillsRegistry` (M3) folds them into its own
    /// diagnostic surface alongside `SkillFrontmatter.notes`.
    ///
    /// - Parameters:
    ///   - id: The directory name -- the canonical id (plan.md §4).
    ///   - frontmatter: The skill's decoded frontmatter.
    ///   - body: The skill's render-pipeline body (`DecodedSkill.body`).
    public init(id: String, frontmatter: SkillFrontmatter, body: String) {
        let inference = ParameterInference.infer(frontmatter: frontmatter, body: body)
        self.init(
            id: id,
            displayName: frontmatter.name,
            description: frontmatter.description,
            license: frontmatter.license,
            compatibility: frontmatter.compatibility,
            parameters: inference.parameters,
            acceptsTrailingArguments: inference.acceptsTrailingArguments)
    }

    /// Convenience over `init(id:frontmatter:body:)` for a `DecodedSkill`
    /// (`FrontmatterDecoder`'s `.decoded` payload).
    ///
    /// - Parameters:
    ///   - id: The directory name -- the canonical id (plan.md §4).
    ///   - decodedSkill: The `FrontmatterDecoder.decode(text:)` result's
    ///     decoded payload.
    public init(id: String, decodedSkill: DecodedSkill) {
        self.init(id: id, frontmatter: decodedSkill.frontmatter, body: decodedSkill.body)
    }
}
