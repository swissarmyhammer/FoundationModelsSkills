/// One resource file row `ListResource` returns.
public struct ResourceRow: Encodable, Sendable, Equatable {
    /// The file's path, relative to the skill directory.
    public let path: String

    /// The file's kind, derived from its top-level folder:
    /// `"script"`/`"reference"`/`"asset"` for `scripts/`/`references/`/
    /// `assets/`, `"other"` for anything else.
    public let kind: String

    /// The file's size in bytes.
    public let bytes: Int

    /// Whether the file's executable bit is set.
    public let executable: Bool

    /// Creates a `ResourceRow` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - path: The file's path, relative to the skill directory.
    ///   - kind: The file's kind.
    ///   - bytes: The file's size in bytes.
    ///   - executable: Whether the file's executable bit is set.
    public init(path: String, kind: String, bytes: Int, executable: Bool) {
        self.path = path
        self.kind = kind
        self.bytes = bytes
        self.executable = executable
    }
}

/// The result of a `list resource` operation: every resource row under a
/// skill's directory, up to the 100-row cap.
public struct ListResourceResult: Encodable, Sendable, Equatable {
    /// The listed skill's canonical id.
    public let id: String

    /// The matching rows, sorted by path, capped at 100.
    public let resources: [ResourceRow]

    /// The real count of matching rows, which may exceed
    /// `resources.count` when the 100-row cap truncated the listing.
    public let total: Int

    /// Creates a `ListResourceResult` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - id: The listed skill's canonical id.
    ///   - resources: The matching rows, sorted by path, capped at 100.
    ///   - total: The real count of matching rows.
    public init(id: String, resources: [ResourceRow], total: Int) {
        self.id = id
        self.resources = resources
        self.total = total
    }
}

/// The result of a `read resource` operation: one file's content, sliced by
/// line, or the location and the size of a binary file.
///
/// A file that is not UTF-8 text is binary. The result of a binary file does
/// not show the bytes. It gives the absolute path of the winning copy and the
/// size of the file, thus the model can give that path to a different tool.
public struct ReadResourceResult: Encodable, Sendable, Equatable {
    /// The resource's owning skill id.
    public let id: String

    /// The resource's path, relative to the skill directory.
    public let path: String

    /// For a text file, the verbatim content of lines `start` through `end`,
    /// joined by `\n` -- never passed through the render pipeline. For a
    /// binary file, one sentence that says the file is binary and gives its
    /// absolute path and its size.
    public let content: String

    /// The first line returned (1-based). `0` for a binary file.
    public let start: Int

    /// The last line returned -- fewer than requested when the file ended or
    /// the per-call content byte budget cut the window short; `start - 1`
    /// when no line was returned. Paging continues from `end + 1`. `0` for a
    /// binary file.
    public let end: Int

    /// The file's total line count, for paging via `start`/`end`. `0` for a
    /// binary file.
    public let totalLines: Int

    /// The kind of the file that was read. One value holds the text state or
    /// the binary state, thus the binary fields cannot disagree.
    private let kind: FileKind

    /// Whether the file is binary, that is, not UTF-8 text.
    public var binary: Bool {
        if case .binary = kind { return true }
        return false
    }

    /// The absolute path of the winning copy of a binary file; `nil` for a
    /// text file. The model can give this path to a different tool, or to
    /// `read resource` again.
    public var absolutePath: String? {
        guard case .binary(let absolutePath, _) = kind else { return nil }
        return absolutePath
    }

    /// The size of a binary file in bytes; `nil` for a text file.
    public var byteSize: Int? {
        guard case .binary(_, let byteSize) = kind else { return nil }
        return byteSize
    }

    /// Creates the result of a text read by directly assigning every field.
    ///
    /// - Parameters:
    ///   - id: The resource's owning skill id.
    ///   - path: The resource's path, relative to the skill directory.
    ///   - content: The verbatim content of lines `start` through `end`.
    ///   - start: The first line returned.
    ///   - end: The last line returned.
    ///   - totalLines: The file's total line count.
    public init(id: String, path: String, content: String, start: Int, end: Int, totalLines: Int) {
        self.init(
            id: id, path: path, content: content, start: start, end: end, totalLines: totalLines,
            kind: .text)
    }

    /// Creates the result of a binary read.
    ///
    /// The result gives no bytes of the file. `binary` is `true`,
    /// `absolutePath` and `byteSize` are the given values, `start`, `end` and
    /// `totalLines` are `0`, and `content` is one sentence that gives the
    /// absolute path and the size.
    ///
    /// - Parameters:
    ///   - id: The resource's owning skill id.
    ///   - path: The resource's path, relative to the skill directory.
    ///   - absolutePath: The absolute path of the winning copy.
    ///   - byteSize: The size of the winning copy in bytes.
    /// - Returns: The binary result.
    public static func binaryFile(id: String, path: String, absolutePath: String, byteSize: Int) -> Self {
        Self(
            id: id, path: path, content: binaryContent(absolutePath: absolutePath, byteSize: byteSize),
            start: binaryLineValue, end: binaryLineValue, totalLines: binaryLineValue,
            kind: .binary(absolutePath: absolutePath, byteSize: byteSize))
    }

    /// The one initializer that sets the stored fields. The text initializer
    /// and the binary factory each give it one `FileKind`.
    ///
    /// - Parameters:
    ///   - id: The resource's owning skill id.
    ///   - path: The resource's path, relative to the skill directory.
    ///   - content: The text lines, or the sentence about a binary file.
    ///   - start: The first line returned.
    ///   - end: The last line returned.
    ///   - totalLines: The file's total line count.
    ///   - kind: The kind of the file that was read.
    private init(
        id: String, path: String, content: String, start: Int, end: Int, totalLines: Int, kind: FileKind
    ) {
        self.id = id
        self.path = path
        self.content = content
        self.start = start
        self.end = end
        self.totalLines = totalLines
        self.kind = kind
    }

    /// The `start`, `end` and `totalLines` of the binary result: a binary file
    /// has no lines.
    private static let binaryLineValue = 0

    /// The `content` sentence of the binary result.
    ///
    /// - Parameters:
    ///   - absolutePath: The absolute path of the winning copy.
    ///   - byteSize: The size of the winning copy in bytes.
    /// - Returns: The sentence that says the file is binary, and gives its
    ///   absolute path and its size.
    private static func binaryContent(absolutePath: String, byteSize: Int) -> String {
        "This file is binary. It is not shown as text. Its absolute path is `\(absolutePath)` "
            + "and its size is \(byteSize) bytes."
    }

    /// The kind of the file that `read resource` read.
    private enum FileKind: Sendable, Equatable {
        /// A UTF-8 text file. The result carries its lines.
        case text

        /// A file that is not UTF-8 text. The result carries the absolute
        /// path of the winning copy and its size in bytes.
        case binary(absolutePath: String, byteSize: Int)
    }

    /// The JSON keys of the result. The flat shape stays the same for the two
    /// kinds: a text read gives `binary: false`, and a binary read also gives
    /// `absolutePath` and `byteSize`.
    private enum CodingKeys: String, CodingKey {
        case id, path, content, start, end, totalLines, binary, absolutePath, byteSize
    }

    /// Encodes the flat JSON shape of the result.
    ///
    /// - Parameter encoder: The encoder to write into.
    /// - Throws: Whatever the keyed container throws.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(content, forKey: .content)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(totalLines, forKey: .totalLines)
        try container.encode(binary, forKey: .binary)
        try container.encodeIfPresent(absolutePath, forKey: .absolutePath)
        try container.encodeIfPresent(byteSize, forKey: .byteSize)
    }
}
