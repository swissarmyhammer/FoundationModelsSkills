/// Reads the skill ids back out of the plain text of a `search skill` or
/// `list skill` answer.
///
/// Each skill of an answer is on one line: `- <id>: <description>`, or
/// `- <id>` when the description is empty. No other line of an answer starts
/// with `- `. Thus the ids of those lines, in line order, are the ids of the
/// answer in rank or catalog order.
///
/// This file imports nothing, thus a suite that reads an answer needs no
/// `Foundation` for it.
enum SkillLineReader {
    /// The start of each skill line.
    private static let linePrefix = "- "

    /// The text between the id and the description on a skill line.
    private static let descriptionSeparator = ": "

    /// Gives the id of each skill line of `answer`, in line order.
    ///
    /// - Parameter answer: The plain text of one `search skill` or
    ///   `list skill` answer.
    /// - Returns: The skill ids, in the order the answer gives them. Empty
    ///   for an answer with no skill line.
    static func ids(in answer: String) -> [String] {
        answer.split(separator: "\n").compactMap(id(onLine:))
    }

    /// Gives the id of one skill line.
    ///
    /// - Parameter line: One line of an answer.
    /// - Returns: The id, or `nil` when `line` is not a skill line.
    private static func id(onLine line: Substring) -> String? {
        guard line.hasPrefix(linePrefix) else { return nil }
        let rest = line.dropFirst(linePrefix.count)
        guard let separator = rest.firstRange(of: descriptionSeparator) else { return String(rest) }
        return String(rest[..<separator.lowerBound])
    }
}
