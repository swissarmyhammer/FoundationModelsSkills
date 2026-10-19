import Operations

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
            "To load a skill, \(callTheTool(with: useCall(id: idPlaceholder))).",
            "For example: \(useCall(id: exampleID))",
            "The answer is the text of the skill: the steps of the work and the tools to use.",
            loadInstructionLastLine,
        ].joined(separator: lineBreak)
    }

    /// The last line of the load instruction: load each skill that helps with
    /// the task, and search again when the work changes.
    ///
    /// A skill does not match a task; a skill helps with a task. More than one
    /// skill can help with one task, thus the line asks for each of them. The
    /// work of a task changes, thus the line asks the model to search again.
    private static let loadInstructionLastLine =
        "If a skill in this list helps with any part of your task, load it now, and do the work "
        + "the way it says. Load each skill that helps. More than one can apply. Search again "
        + "when the work changes."

    /// The rule of the tool description, on one line: read the skills, load
    /// each skill that helps with the task, with the exact call, and read the
    /// list again when the work changes.
    internal static let descriptionUseRule =
        "Read the skills below before you start. If a skill helps with any part of your task, "
        + "load it now: call this tool with \(useCall(id: idPlaceholder)). "
        + "Load each skill that helps. More than one can apply. "
        + "The answer is the text of the skill. Do the work the way it says. "
        + "Read this list again when the work changes."

    /// The path placeholder of the read call in the tool description: a path
    /// relative to the skill.
    private static let relativePathPlaceholder = "<path relative to the skill>"

    /// The sentence of the tool description, on one line, that follows the
    /// use rule: a skill can have files, the exact `read resource` call that
    /// reads one, and the answer that lists them.
    ///
    /// The op names come from the operation types, thus the sentence cannot
    /// name an op that the tool does not have.
    internal static let descriptionFilesRule =
        "A skill can have files, such as \(ResourcePathRules.examplePath). To read one, "
        + callTheTool(with: call(op: ReadResource.opString, id: idPlaceholder, path: relativePathPlaceholder))
        + ". The answer of `\(UseSkill.opString)` lists the files of the skill."

    /// Gives the arguments of the `skills` call that loads `id`, as the model
    /// writes them.
    ///
    /// - Parameter id: The id of the skill, or the id placeholder.
    /// - Returns: The call, for example `{"op": "use skill", "id": "explore"}`.
    private static func useCall(id: String) -> String {
        call(op: UseSkill.opString, id: id)
    }

    /// The name of the `id` field of a call.
    private static let idFieldName = "id"

    /// The name of the `path` field of a call.
    private static let pathFieldName = "path"

    /// The name of the `query` field of a `search skill` call.
    private static let queryFieldName = "query"

    /// Gives the arguments of one `skills` call that names a skill, as the
    /// model writes them.
    ///
    /// The load call of this type and the calls of `SkillFilesText` each come
    /// from here, thus the texts cannot differ on the shape of a call.
    ///
    /// - Parameters:
    ///   - op: The op of the operation, for example `ReadResource.opString`.
    ///   - id: The id of the skill, or the id placeholder.
    ///   - path: The path of a file of the skill, or a placeholder for it.
    ///     `nil` gives a call with no `path` field.
    /// - Returns: The call, for example
    ///   `{"op": "read resource", "id": "release-notes", "path": "<path>"}`.
    internal static func call(op: String, id: String, path: String? = nil) -> String {
        let pathFields = path.map { [(name: pathFieldName, value: $0)] } ?? []
        return call(op: op, fields: [(name: idFieldName, value: id)] + pathFields)
    }

    /// Gives the arguments of the `search skill` call, as the model writes
    /// them.
    ///
    /// - Parameter query: The query of the search, or a placeholder for it.
    /// - Returns: The call, for example
    ///   `{"op": "search skill", "query": "<the kind of work>"}`.
    internal static func searchCall(query: String) -> String {
        call(op: SearchSkill.opString, fields: [(name: queryFieldName, value: query)])
    }

    /// Gives the arguments of one `skills` call: the `op` field, then each
    /// field of `fields` in order.
    ///
    /// Each call of this type comes from here, thus no two calls can differ
    /// on the shape of a field.
    ///
    /// - Parameters:
    ///   - op: The op of the operation.
    ///   - fields: The other fields of the call, in the order to write them.
    /// - Returns: The call, for example `{"op": "use skill", "id": "explore"}`.
    private static func call(op: String, fields: [(name: String, value: String)]) -> String {
        let allFields = [(name: OperationKeys.opFieldName, value: op)] + fields
        return "{" + allFields.map { #""\#($0.name)": "\#($0.value)""# }.joined(separator: ", ") + "}"
    }

    /// Gives the words that tell the model to call the `skills` tool with
    /// `call`.
    ///
    /// - Parameter call: The arguments of the call, from
    ///   `call(op:id:path:)` or `searchCall(query:)`.
    /// - Returns: The words. For the load call, the words are: call the
    ///   `skills` tool with `{"op": "use skill", "id": "<id>"}`.
    internal static func callTheTool(with call: String) -> String {
        "call the `\(SkillsTool.toolName)` tool with \(call)"
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
