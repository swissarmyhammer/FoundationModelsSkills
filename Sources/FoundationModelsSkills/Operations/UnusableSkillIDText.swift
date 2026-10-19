/// Builds the corrective that `use skill` and each resource operation give
/// for a skill id that is not usable: unknown, stale, or not visible on the
/// surface of the call.
///
/// The `id` field of the schema of the `skills` tool is a plain string, thus
/// a model can guess an id. The corrective names the closest usable ids and
/// gives the exact `search skill` call, thus the model can try again.
///
/// The measure of closeness is the edit distance: the fewest one-character
/// insertions, deletions, and substitutions that turn the given id into a
/// usable id. The comparison is case-sensitive, as the lookup of an id is.
/// Ids at the same distance are in id order. Thus the same catalog and the
/// same id always give the same text.
///
/// `UseSkill` and `ResourceIDLookup` each read this one builder, thus the
/// operations cannot differ on the wording.
internal enum UnusableSkillIDText {
    /// The most usable ids that the corrective names.
    private static let closestIDLimit = 5

    /// The query placeholder of the `search skill` call: the kind of work, as
    /// the description of `search skill` asks for.
    private static let searchQueryPlaceholder = "<the kind of work>"

    /// The last sentence of a corrective that names usable ids: the exact
    /// `search skill` call.
    private static let searchSentence =
        "To find a skill, "
        + SkillCatalogText.callTheTool(with: SkillCatalogText.searchCall(query: searchQueryPlaceholder)) + "."

    /// Gives the corrective for `id`.
    ///
    /// - Parameters:
    ///   - id: The id that could not be used.
    ///   - catalog: The catalog to take the usable ids from.
    ///   - visibilityPredicate: Which catalog entries are usable on the
    ///     surface of the call.
    /// - Returns: The corrective: the closest usable ids and the
    ///   `search skill` call, or the sentence that no skill is usable.
    internal static func message(
        id: String, catalog: [SkillMetadata], visibilityPredicate: (SkillMetadata) -> Bool
    ) -> String {
        let prefix = "The skill id `\(id)` is not currently usable"
        let usableIDs = catalog.filter(visibilityPredicate).map(\.id)
        guard !usableIDs.isEmpty else {
            return "\(prefix), and no skills are currently usable."
        }
        let closest = closestIDs(to: id, in: usableIDs).joined(separator: ", ")
        return "\(prefix). Closest usable ids: \(closest). \(searchSentence)"
    }

    /// Gives at most `closestIDLimit` ids of `usableIDs`, by edit distance to
    /// `id` and then by id.
    ///
    /// - Parameters:
    ///   - id: The id that could not be used.
    ///   - usableIDs: The usable ids.
    /// - Returns: The closest ids, closest first.
    private static func closestIDs(to id: String, in usableIDs: [String]) -> [String] {
        let ranked = usableIDs.map { (distance: editDistance(from: id, to: $0), id: $0) }
            .sorted { ($0.distance, $0.id) < ($1.distance, $1.id) }
        return ranked.prefix(closestIDLimit).map(\.id)
    }

    /// Gives the edit distance between two texts: the fewest one-character
    /// insertions, deletions, and substitutions that turn `source` into
    /// `target`.
    ///
    /// Each row holds the distance from a prefix of `source` to each prefix
    /// of `target`. The last value of the last row is the answer.
    ///
    /// - Parameters:
    ///   - source: The text to start from.
    ///   - target: The text to end at.
    /// - Returns: The edit distance.
    private static func editDistance(from source: String, to target: String) -> Int {
        let targetCharacters = Array(target)
        let firstRow = Array(0...targetCharacters.count)
        let lastRow = source.enumerated().reduce(firstRow) { previousRow, sourceStep in
            targetCharacters.enumerated().reduce(into: [sourceStep.offset + 1]) { row, targetStep in
                let substitutionCost = sourceStep.element == targetStep.element ? 0 : 1
                row.append(
                    min(
                        previousRow[targetStep.offset] + substitutionCost,
                        previousRow[targetStep.offset + 1] + 1,
                        row[targetStep.offset] + 1))
            }
        }
        return lastRow[targetCharacters.count]
    }
}
