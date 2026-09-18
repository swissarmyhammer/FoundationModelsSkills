/// One catalog row shared by `search skill` and `list skill` (plan.md §7).
///
/// Carries a skill's id, rendered description, and parameter placeholder
/// summaries -- exactly the display shape both operations need, so neither
/// duplicates the other's row-building logic.
public struct SkillRow: Encodable, Sendable, Equatable {
    /// The skill's canonical id -- the `use skill` / `/command` key.
    public let id: String

    /// The skill's rendered `description:` (plan.md §5 passes 1+3).
    public let description: String

    /// Placeholder summaries of the skill's parameters, e.g. `"<message>"`,
    /// `"[env]"` (plan.md §6.1).
    public let parameters: [String]

    /// The marketplace this skill came from, for example
    /// `swissarmyhammer-skills@1.2.0`, or `nil` for a local skill
    /// (marketplace.md §9.1).
    ///
    /// A `nil` value writes no key at all, thus a local row keeps the shape
    /// it had before marketplaces existed. The text names the marketplace
    /// and the snapshot, never the URL, thus it can never show a
    /// credential.
    public let source: String?

    /// The exact `skills` call that loads this skill, or `nil` when the row
    /// carries none.
    ///
    /// A `search skill` row always carries it, thus the model can copy the
    /// call and need not build it. A `list skill` row carries none. A `nil`
    /// value writes no key at all.
    public let use: SkillUseCall?

    /// Creates a `SkillRow` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - id: The skill's canonical id.
    ///   - description: The skill's rendered `description:`.
    ///   - parameters: Placeholder summaries of the skill's parameters.
    ///   - source: The marketplace the skill came from. Defaults to `nil`,
    ///     a local skill.
    ///   - use: The `skills` call that loads the skill. Defaults to `nil`,
    ///     no call.
    public init(
        id: String, description: String, parameters: [String], source: String? = nil, use: SkillUseCall? = nil
    ) {
        self.id = id
        self.description = description
        self.parameters = parameters
        self.source = source
        self.use = use
    }

    /// Builds a row with no `use` call from one catalog entry's rendered
    /// metadata, as `list skill` shows it.
    ///
    /// - Parameter metadata: The catalog entry to summarize as a row.
    internal init(metadata: SkillMetadata) {
        self.init(metadata: metadata, use: nil)
    }

    /// Builds a row from one catalog entry's rendered metadata.
    ///
    /// - Parameters:
    ///   - metadata: The catalog entry to summarize as a row.
    ///   - use: The `skills` call that loads the skill, or `nil` for no
    ///     call.
    internal init(metadata: SkillMetadata, use: SkillUseCall?) {
        self.init(
            id: metadata.id, description: metadata.description, parameters: metadata.parameters,
            source: metadata.source, use: use)
    }
}

/// The arguments of the `skills` call that loads one skill:
/// `{"op": "use skill", "id": "<id>"}`.
///
/// A model that reads a `search skill` row can send this object back to the
/// `skills` tool as it is.
public struct SkillUseCall: Encodable, Sendable, Equatable {
    /// The op of the call: `UseSkill.opString`, `"use skill"`.
    public let op: String

    /// The id of the skill the call loads.
    public let id: String

    /// Creates the call that loads the skill `id`.
    ///
    /// - Parameter id: The id of the skill to load.
    public init(id: String) {
        self.op = UseSkill.opString
        self.id = id
    }
}

/// The successful result of a `search skill` operation: ranked matches, their
/// total count, the instruction for the model, and, when the selection tier
/// chose the first match, the rendered body of that match (plan.md §7).
///
/// Structurally close to `ListSkillResult` (both pair a `[SkillRow]` with a
/// `total: Int`) but kept as a distinct type rather than a shared generic:
/// plan.md §7 names the two operations' result fields differently
/// (`matches` here, `skills` there) as part of the model-facing JSON
/// contract, and that field-name distinction is the point. A search result
/// also carries `next` and `skill`, which a list result does not have.
public struct SearchSkillResult: Encodable, Sendable, Equatable {
    /// The ranked matches, best first, capped at the requested `limit`.
    public let matches: [SkillRow]

    /// The real number of matches found, before the `limit` cap -- lets the
    /// model know to raise `limit` when it wants to see more. Can exceed
    /// `matches.count`.
    public let total: Int

    /// The instruction that tells the model what to do with `matches`, or
    /// `nil` when `matches` is empty.
    ///
    /// A result with no match has no instruction, thus it never tells the
    /// model to load a skill that is not there. A `nil` value writes no key
    /// at all.
    public let next: String?

    /// The rendered body of the first match, when the selection tier chose
    /// it and `use skill` renders it with no argument; otherwise `nil`.
    ///
    /// The body comes from the same render path as `use skill`. Only the
    /// first match gets a body, to keep the result small. A `nil` value
    /// writes no key at all.
    public let skill: UseSkillResult?

    /// The `next` text of a result with matches and no loaded body.
    public static let useInstruction =
        "If a skill in this list applies to your task, you must use it. Load it now with its `use` call, "
        + "and follow its instructions before you continue with the task."

    /// The `next` text of a result that carries the body of its first match.
    public static let loadedInstruction =
        "The first skill is loaded below. If it applies to your task, you must follow it. "
        + "If a different skill applies, load it with its `use` call."

    /// Creates a `SearchSkillResult`, and derives `next` from `matches` and
    /// `skill`.
    ///
    /// - Parameters:
    ///   - matches: The ranked matches, best first.
    ///   - total: The real number of matches found, before the `limit` cap.
    ///   - skill: The rendered body of the first match. Defaults to `nil`,
    ///     no body.
    public init(matches: [SkillRow], total: Int, skill: UseSkillResult? = nil) {
        self.matches = matches
        self.total = total
        self.skill = skill
        self.next = Self.nextInstruction(hasMatches: !matches.isEmpty, hasBody: skill != nil)
    }

    /// The `next` text for a result of this shape.
    ///
    /// - Parameters:
    ///   - hasMatches: Whether the result has at least one match.
    ///   - hasBody: Whether the result carries the body of its first match.
    /// - Returns: `nil` with no match, `loadedInstruction` with a body, and
    ///   `useInstruction` otherwise.
    private static func nextInstruction(hasMatches: Bool, hasBody: Bool) -> String? {
        guard hasMatches else { return nil }
        return hasBody ? loadedInstruction : useInstruction
    }
}

/// The result of a `list skill` operation: every catalog row matching the
/// optional filter, in catalog order (plan.md §7).
///
/// Always a success -- a `filter` matching nothing yields an empty `skills`
/// array with `total: 0`, never a corrective message.
///
/// See `SearchSkillResult`'s doc comment for why this isn't generalized
/// with it despite the structural overlap.
public struct ListSkillResult: Encodable, Sendable, Equatable {
    /// The matching rows, in catalog (id-sorted) order.
    public let skills: [SkillRow]

    /// The number of rows returned.
    public let total: Int

    /// Creates a `ListSkillResult` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - skills: The matching rows, in catalog order.
    ///   - total: The number of rows returned.
    public init(skills: [SkillRow], total: Int) {
        self.skills = skills
        self.total = total
    }
}

/// The successful result of a `use skill` operation: the skill's fully
/// rendered body (plan.md §5, §7).
public struct UseSkillResult: Encodable, Sendable, Equatable {
    /// The used skill's canonical id.
    public let id: String

    /// The skill's body, rendered through all three §5 passes with the
    /// supplied arguments.
    public let body: String

    /// Creates a `UseSkillResult` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - id: The used skill's canonical id.
    ///   - body: The skill's rendered body.
    public init(id: String, body: String) {
        self.id = id
        self.body = body
    }
}
