/// The answer of one `SkillSearchAgent` search: the matches, and whether the
/// selection tier chose them.
///
/// `search skill` reads `isSelection` to decide if it loads the body of the
/// first match. A choice of the selection model is a strong signal that the
/// skill applies. A retrieval rank is only a keyword and vector score, thus
/// the model gets the list and the instruction to load a skill, not a body.
public struct SkillSearchAnswer: Sendable, Equatable {
    /// The matching skills' metadata, best first.
    public let matches: [SkillMetadata]

    /// Whether the selection tier chose `matches`.
    ///
    /// `false` for a rank of a searcher in `.retrieval` mode, for a rank of
    /// the retrieval fallback, and for an answer with no match.
    public let isSelection: Bool

    /// Creates an answer by directly assigning every field.
    ///
    /// - Parameters:
    ///   - matches: The matching skills' metadata, best first.
    ///   - isSelection: Whether the selection tier chose `matches`.
    public init(matches: [SkillMetadata], isSelection: Bool) {
        self.matches = matches
        self.isSelection = isSelection
    }
}
