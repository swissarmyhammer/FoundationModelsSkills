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

    /// Creates a `SkillRow` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - id: The skill's canonical id.
    ///   - description: The skill's rendered `description:`.
    ///   - parameters: Placeholder summaries of the skill's parameters.
    public init(id: String, description: String, parameters: [String]) {
        self.id = id
        self.description = description
        self.parameters = parameters
    }

    /// Builds a row from one catalog entry's rendered metadata.
    ///
    /// - Parameter metadata: The catalog entry to summarize as a row.
    internal init(metadata: SkillMetadata) {
        self.init(id: metadata.id, description: metadata.description, parameters: metadata.parameters)
    }
}

/// The successful result of a `search skill` operation: ranked matches plus
/// their total count (plan.md §7).
///
/// Structurally close to `ListSkillResult` (both pair a `[SkillRow]` with a
/// `total: Int`) but kept as a distinct type rather than a shared generic:
/// plan.md §7 names the two operations' result fields differently
/// (`matches` here, `skills` there) as part of the model-facing JSON
/// contract, and that field-name distinction is the point -- a generic
/// `struct Page<T> { let items: [T]; let total: Int }` would either lose it
/// or need a phantom type parameter to recover it, disproportionate to two
/// four-property structs whose only literal duplication is their
/// three-line memberwise `init`.
public struct SearchSkillResult: Encodable, Sendable, Equatable {
    /// The ranked matches, best first, capped at the requested `limit`.
    public let matches: [SkillRow]

    /// The number of matches returned -- lets the model know to raise
    /// `limit` when it wants to see more.
    public let total: Int

    /// Creates a `SearchSkillResult` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - matches: The ranked matches, best first.
    ///   - total: The number of matches returned.
    public init(matches: [SkillRow], total: Int) {
        self.matches = matches
        self.total = total
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
