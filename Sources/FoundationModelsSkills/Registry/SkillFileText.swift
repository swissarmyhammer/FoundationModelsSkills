import Yams

/// Makes and changes the text of a `SKILL.md` from its parts: the
/// description and the body.
///
/// The `skills` GraphQL endpoint (D190) edits a skill by its fields, not by
/// the full text of the file. This type turns the fields into the full text,
/// and `SkillWriter` then checks and writes that text, the same as for the
/// `add skill` and `edit skill` operations of the `skills` tool.
enum SkillFileText {
    /// The fence line that opens and closes the frontmatter block.
    private static let fence = "---"

    /// The frontmatter key of the name.
    private static let nameKey = "name"

    /// The frontmatter key of the description.
    private static let descriptionKey = "description"

    /// The text of a new `SKILL.md`: a frontmatter block with the name and
    /// the description, and then the body.
    ///
    /// - Parameters:
    ///   - name: The name of the skill: the name of its folder.
    ///   - description: The description of the skill.
    ///   - body: The Markdown body of the skill.
    /// - Returns: The full text of the file.
    /// - Throws: An error of the YAML emitter.
    static func make(name: String, description: String, body: String) throws -> String {
        let mapping = Node.Mapping([
            (Node(nameKey), quoted(name)),
            (Node(descriptionKey), quoted(description)),
        ])
        return try joined(frontmatter: Yams.serialize(node: .mapping(mapping)), body: body)
    }

    /// The text of an existing `SKILL.md` with a new description, a new
    /// body, or the two.
    ///
    /// A description change writes the frontmatter again from its YAML node,
    /// thus the other keys stay, in their order. A body change keeps the
    /// frontmatter text as it is.
    ///
    /// - Parameters:
    ///   - current: The frontmatter text and the body of the current file,
    ///     as `SkillWriter` splits them.
    ///   - description: The new description, or `nil` for no change.
    ///   - body: The new body, or `nil` for no change.
    /// - Returns: The full new text, or `nil` when the frontmatter is not a
    ///   YAML mapping, thus the description cannot change.
    /// - Throws: An error of the YAML emitter.
    static func changed(
        _ current: (frontmatter: String?, body: String), description: String?, body: String?
    ) throws -> String? {
        var frontmatter = current.frontmatter ?? ""
        if let description {
            guard case .mapping(var mapping)? = try? Yams.compose(yaml: frontmatter) ?? .mapping([:]) else {
                return nil
            }
            mapping[descriptionKey] = quoted(description)
            frontmatter = try Yams.serialize(node: .mapping(mapping))
        }
        return joined(frontmatter: frontmatter, body: body ?? current.body)
    }

    /// A scalar node of `text` that the emitter writes in double quotes,
    /// thus each text reads back as the same string.
    ///
    /// - Parameter text: The text.
    /// - Returns: The node.
    private static func quoted(_ text: String) -> Node {
        Node(text, Tag(.str), .doubleQuoted)
    }

    /// The frontmatter block and the body as one text.
    ///
    /// - Parameters:
    ///   - frontmatter: The YAML text between the fences, which ends in a
    ///     newline or is empty.
    ///   - body: The body.
    /// - Returns: The full text of the file.
    private static func joined(frontmatter: String, body: String) -> String {
        let block = frontmatter.isEmpty || frontmatter.hasSuffix("\n") ? frontmatter : frontmatter + "\n"
        let text = body.isEmpty || body.hasSuffix("\n") ? body : body + "\n"
        return "\(fence)\n\(block)\(fence)\n\(text)"
    }
}
