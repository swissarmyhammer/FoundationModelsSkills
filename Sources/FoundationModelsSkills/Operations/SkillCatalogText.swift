/// Builds the plain text that tells the model which skills exist and how to
/// load one.
///
/// `search skill`, `list skill`, and the description of the fused `skills`
/// tool give the model the same line for each skill, `- <id>: <description>`,
/// and name the same load call, `{"op": "use skill", "id": "<id>"}`. This type
/// is the one place that writes them, thus the three texts cannot drift.
///
/// The text holds no tag, marker, or wrapper.
internal enum SkillCatalogText {
    /// The text between two lines.
    internal static let lineBreak = "\n"

    /// The text between the parts of an answer: a blank line.
    internal static let partBreak = lineBreak + lineBreak

    /// The id placeholder in the general form of the load call.
    private static let idPlaceholder = "<id>"

    /// The answer of `search skill` and `list skill` when the calling
    /// context's visibility predicate accepts no skill.
    internal static let emptyCatalogMessage = "No skills are available."

    /// Gives the line of one skill: `- <id>: <description>`, or `- <id>` when
    /// the description is empty.
    ///
    /// - Parameters:
    ///   - id: The skill id.
    ///   - description: The description, already on one line.
    /// - Returns: The line.
    internal static func line(id: String, description: String) -> String {
        description.isEmpty ? "- \(id)" : "- \(id): \(description)"
    }

    /// Gives one line for each skill of `catalog`, in the order of `catalog`.
    ///
    /// - Parameter catalog: The skills. Each description goes on one line.
    /// - Returns: The lines, joined with line breaks.
    private static func lines(for catalog: [SkillMetadata]) -> String {
        catalog.map { line(id: $0.id, description: oneLine($0.description)) }.joined(separator: lineBreak)
    }

    /// Gives the heading and a blank line when there is a heading, then the
    /// lines of `catalog`, a blank line, and the load instruction.
    ///
    /// The example of the instruction loads the first skill of `catalog`. An
    /// empty `catalog` has no skill to load, thus it gives `emptyMessage`
    /// alone: no heading and no instruction.
    ///
    /// - Parameters:
    ///   - catalog: The skills, in the order the answer gives them.
    ///   - heading: The line before the skill lines, or `nil` for no line.
    ///   - emptyMessage: The one line to give when `catalog` is empty.
    /// - Returns: The heading, the lines, and the instruction, or
    ///   `emptyMessage`.
    internal static func listing(_ catalog: [SkillMetadata], heading: String?, emptyMessage: String) -> String {
        guard let first = catalog.first else {
            return emptyMessage
        }
        let body = lines(for: catalog) + partBreak + loadInstruction(exampleID: first.id)
        guard let heading else {
            return body
        }
        return heading + partBreak + body
    }

    /// Gives the four lines that tell the model how to load a skill and what
    /// to do with it.
    ///
    /// - Parameter exampleID: The id that the example call loads.
    /// - Returns: The instruction.
    private static func loadInstruction(exampleID: String) -> String {
        [
            "To load a skill, call the `\(SkillsTool.toolName)` tool with \(useCall(id: idPlaceholder)).",
            "For example: \(useCall(id: exampleID))",
            "The answer is the text of the skill: the steps of the work and the tools to use.",
            "If a skill in this list fits your task, load it now, and do the work the way it says.",
        ].joined(separator: lineBreak)
    }

    /// The rule of the tool description, on one line: load a skill that
    /// matches the task, with the exact call.
    internal static let descriptionUseRule =
        "When a task matches a skill below, load it: call this tool with \(useCall(id: idPlaceholder)). "
        + "The answer is the text of the skill. Do the work the way it says."

    /// Gives the arguments of the `skills` call that loads `id`, as the model
    /// writes them.
    ///
    /// - Parameter id: The id of the skill, or the id placeholder.
    /// - Returns: The call, for example `{"op": "use skill", "id": "explore"}`.
    private static func useCall(id: String) -> String {
        #"{"op": "\#(UseSkill.opString)", "id": "\#(id)"}"#
    }

    /// Puts `text` on one line: each run of white space, line breaks too,
    /// becomes one space.
    ///
    /// - Parameter text: A skill description.
    /// - Returns: The description on one line.
    internal static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
