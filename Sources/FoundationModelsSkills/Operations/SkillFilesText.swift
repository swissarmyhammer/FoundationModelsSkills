/// Builds the plain text that follows the body in the answer of `use skill`:
/// the list of the files of the skill, and the calls that read a file or run
/// a script.
///
/// The rows come from `ListResource.listedRows(in:)`, thus this list and the
/// answer of `list resource` show the same files, in the same order, with the
/// same kind. The calls come from `SkillCatalogText.call(op:id:path:)` and
/// the op of each operation, thus no name of an operation is written here.
///
/// The text holds no tag, marker, or wrapper. A model reads plain text, and
/// we cannot be sure that each model knows a tag that we make.
internal enum SkillFilesText {
    /// The first line of the list.
    private static let heading = "Files of this skill:"

    /// The path placeholder of the read call.
    private static let pathPlaceholder = "<path>"

    /// The path placeholder of the run call: a file under `scripts/`.
    private static let scriptPathPlaceholder = scriptsDirectoryPrefix + "<name>"

    /// The sentence after the read call: the model gives the path as the list
    /// gives it, not a path that it makes.
    private static let readInstructionLastSentence = "Give the path as it is in this list."

    /// Gives the list of the files of the skill and the calls that read them,
    /// or `nil` when the skill has no file other than `SKILL.md`.
    ///
    /// The list gives the first `ListResource.rowCap` rows. When the skill has
    /// more files, a line gives their count and the `list resource` call that
    /// shows them. The `run script` call follows the read call only when a row
    /// of the skill is a script and the host policy permits scripts. The check
    /// reads each row, also a row after the row limit.
    ///
    /// - Parameters:
    ///   - id: The skill id, which each call names.
    ///   - rows: Each row of `ListResource.listedRows(in:)`, in path order,
    ///     with no row limit.
    ///   - isScriptExecutionDisabled: The `run script` kill switch of the host
    ///     policy.
    /// - Returns: The list, a blank line, and the calls; or `nil` for no row.
    internal static func text(id: String, rows: [ResourceRow], isScriptExecutionDisabled: Bool) -> String? {
        guard !rows.isEmpty else {
            return nil
        }
        let hasScript = rows.contains { $0.kind == ListResource.scriptKind }
        let permitsRun = hasScript && !isScriptExecutionDisabled
        let callLines = [readInstruction(id: id)] + (permitsRun ? [runInstruction(id: id)] : [])
        return list(id: id, rows: rows) + SkillCatalogText.partBreak
            + callLines.joined(separator: SkillCatalogText.lineBreak)
    }

    /// Puts `filesText` after `body`, with one blank line between them.
    ///
    /// A body that ends with a line break gets one more line break, and a body
    /// with no line break at its end gets two. The body itself does not change.
    ///
    /// - Parameters:
    ///   - filesText: The text of `text(id:rows:isScriptExecutionDisabled:)`,
    ///     or `nil` for a skill with no file other than `SKILL.md`.
    ///   - body: The rendered body of the skill.
    /// - Returns: The body, then the files text; or `body` with no change when
    ///   `filesText` is `nil`.
    internal static func appending(_ filesText: String?, to body: String) -> String {
        guard let filesText else {
            return body
        }
        let endsWithLineBreak = body.hasSuffix(SkillCatalogText.lineBreak)
        let separator = endsWithLineBreak ? SkillCatalogText.lineBreak : SkillCatalogText.partBreak
        return body + separator + filesText
    }

    /// Gives the heading, one line for each of the first
    /// `ListResource.rowCap` rows, and the count of the other rows when there
    /// are more.
    ///
    /// - Parameters:
    ///   - id: The skill id, which the `list resource` call names.
    ///   - rows: Each row of the skill, in path order.
    /// - Returns: The lines of the list, joined with line breaks.
    private static func list(id: String, rows: [ResourceRow]) -> String {
        let listedRows = rows.prefix(ListResource.rowCap)
        let unlistedCount = rows.count - listedRows.count
        let moreLines = unlistedCount > 0 ? [moreFilesLine(id: id, count: unlistedCount)] : []
        return ([heading] + listedRows.map(line(for:)) + moreLines).joined(separator: SkillCatalogText.lineBreak)
    }

    /// Gives the line of one file: `- <path> (<kind>)`.
    ///
    /// - Parameter row: The row of the file.
    /// - Returns: The line.
    private static func line(for row: ResourceRow) -> String {
        "- \(row.path) (\(row.kind))"
    }

    /// Gives the line that counts the files after the row limit and names the
    /// call that shows them.
    ///
    /// - Parameters:
    ///   - id: The skill id, which the `list resource` call names.
    ///   - count: The number of files that the list does not give.
    /// - Returns: The line.
    private static func moreFilesLine(id: String, count: Int) -> String {
        let call = SkillCatalogText.call(op: ListResource.opString, id: id)
        return "\(count) more files are not listed. See them with \(call)."
    }

    /// Gives the line that tells the model how to read a file of the skill.
    ///
    /// - Parameter id: The skill id, which the call names.
    /// - Returns: The line.
    private static func readInstruction(id: String) -> String {
        let call = SkillCatalogText.call(op: ReadResource.opString, id: id, path: pathPlaceholder)
        return "To read a file, \(SkillCatalogText.callTheTool(with: call)). \(readInstructionLastSentence)"
    }

    /// Gives the line that tells the model how to run a script of the skill.
    ///
    /// - Parameter id: The skill id, which the call names.
    /// - Returns: The line.
    private static func runInstruction(id: String) -> String {
        let call = SkillCatalogText.call(op: RunScript.opString, id: id, path: scriptPathPlaceholder)
        return "To run a script, \(SkillCatalogText.callTheTool(with: call))."
    }
}
