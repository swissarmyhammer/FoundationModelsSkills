/// Builds the description that the fused `skills` tool gives the model.
///
/// A model reads the description of a tool before it plans, thus the
/// description is where the model learns which skills exist. The text has
/// two fixed sentences: what a skill is, and the rule to load a skill that
/// matches the task. A list of the visible skills follows them, one skill on
/// each line with its description.
///
/// The list has a character limit. The builder tries four steps in order
/// and stops at the first one that fits the limit:
///
/// 1. Each skill with its full description.
/// 2. Each description shortened with `SkillsRegistry.truncatedForMenu`,
///    the same truncation as the user `/` menu.
/// 3. The ids only, on one comma-separated line.
/// 4. As many ids as fit, then a line with the count of the ids that are
///    not listed, and the tip to find them with `search skill`.
///
/// The fixed sentences are never cut. The text holds no tag, XML, or other
/// wrapper.
internal enum SkillsToolDescription {
    /// The first fixed sentence: what a skill is.
    private static let purpose = "Skills are procedures for kinds of work."

    /// The second fixed sentence: what a skill gives the model.
    private static let guidance = "Each one tells you how to do the work and which tools to use."

    /// The rule that tells the model to load a skill that matches its task.
    private static let useRule =
        "When a task matches a skill below, you must load that skill with `use skill` "
        + "and follow its instructions before you do the work."

    /// The line that replaces the list when no skill is visible.
    private static let noSkillsLine = "No skills are installed now."

    /// The words after the count on the last line of step 4.
    private static let notListedNote = "more skills are not listed. Find them with `search skill`."

    /// The text between two ids on the id line of steps 3 and 4.
    private static let idSeparator = ", "

    /// The text between two lines of the description.
    private static let lineBreak = "\n"

    /// Builds the description for `catalog`.
    ///
    /// - Parameters:
    ///   - catalog: The skills the tool shows, in the order the list gives
    ///     them. The caller filters it to the visible skills.
    ///   - characterLimit: The most characters the list may have. The fixed
    ///     sentences do not count against it.
    /// - Returns: The fixed sentences and the list. For an empty `catalog`,
    ///   the first sentence and the no-skills line.
    internal static func make(catalog: [SkillMetadata], characterLimit: Int) -> String {
        guard !catalog.isEmpty else {
            return purpose + lineBreak + noSkillsLine
        }
        let header = "\(purpose) \(guidance)" + lineBreak + useRule + lineBreak + lineBreak
        return header + list(for: catalog, characterLimit: characterLimit)
    }

    /// Gives the list of the first step that fits `characterLimit`.
    ///
    /// - Parameters:
    ///   - catalog: The skills the list gives. It is not empty.
    ///   - characterLimit: The most characters the list may have.
    /// - Returns: The list.
    private static func list(for catalog: [SkillMetadata], characterLimit: Int) -> String {
        let entries = catalog.map { (id: $0.id, description: oneLine($0.description)) }
        let ids = entries.map(\.id)
        let fullList = describedList(entries)
        let shortenedList = describedList(
            entries.map { (id: $0.id, description: SkillsRegistry.truncatedForMenu($0.description)) })
        let idLine = ids.joined(separator: idSeparator)
        let fitting = [fullList, shortenedList, idLine].first { $0.count <= characterLimit }
        return fitting ?? partialIDList(ids, characterLimit: characterLimit)
    }

    /// Gives one line for each entry: `- <id>: <description>`, or `- <id>`
    /// when the description is empty.
    ///
    /// - Parameter entries: The ids and the descriptions, each on one line.
    /// - Returns: The lines, joined with line breaks.
    private static func describedList(_ entries: [(id: String, description: String)]) -> String {
        entries.map { entry in
            entry.description.isEmpty ? "- \(entry.id)" : "- \(entry.id): \(entry.description)"
        }.joined(separator: lineBreak)
    }

    /// Gives as many ids as fit `characterLimit` on one line, then the line
    /// that counts the ids that are not listed.
    ///
    /// The count line always shows, thus the model always learns that the
    /// list is not complete. When not even one id fits beside it, the count
    /// line is the whole list.
    ///
    /// - Parameters:
    ///   - ids: Every id, in list order.
    ///   - characterLimit: The most characters the list may have.
    /// - Returns: The ids that fit and the count line.
    private static func partialIDList(_ ids: [String], characterLimit: Int) -> String {
        var shown: [String] = []
        var idLineLength = 0
        for id in ids {
            let separatorLength = shown.isEmpty ? 0 : idSeparator.count
            let lengthWithID = idLineLength + separatorLength + id.count
            let countLine = notListedLine(count: ids.count - shown.count - 1)
            guard lengthWithID + lineBreak.count + countLine.count <= characterLimit else { break }
            shown.append(id)
            idLineLength = lengthWithID
        }
        let countLine = notListedLine(count: ids.count - shown.count)
        return shown.isEmpty ? countLine : shown.joined(separator: idSeparator) + lineBreak + countLine
    }

    /// Gives the line that counts the ids that are not listed.
    ///
    /// - Parameter count: The number of ids that are not listed.
    /// - Returns: The count line.
    private static func notListedLine(count: Int) -> String {
        "\(count) \(notListedNote)"
    }

    /// Puts `text` on one line: each run of white space, line breaks too,
    /// becomes one space.
    ///
    /// - Parameter text: A skill description.
    /// - Returns: The description on one line.
    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
