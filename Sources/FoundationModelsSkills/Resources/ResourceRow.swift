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

    /// Whether the file is binary, that is, not UTF-8 text.
    public let binary: Bool

    /// The absolute path of the winning copy of a binary file; `nil` for a
    /// text file. The model can give this path to a different tool, or to
    /// `read resource` again.
    public let absolutePath: String?

    /// The size of a binary file in bytes; `nil` for a text file.
    public let byteSize: Int?

    /// Creates a `ReadResourceResult` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - id: The resource's owning skill id.
    ///   - path: The resource's path, relative to the skill directory.
    ///   - content: The verbatim content of lines `start` through `end`, or
    ///     the sentence about a binary file.
    ///   - start: The first line returned.
    ///   - end: The last line returned.
    ///   - totalLines: The file's total line count.
    ///   - binary: Whether the file is binary. Defaults to `false`.
    ///   - absolutePath: The absolute path of the winning copy of a binary
    ///     file. Defaults to `nil`.
    ///   - byteSize: The size of a binary file in bytes. Defaults to `nil`.
    public init(
        id: String, path: String, content: String, start: Int, end: Int, totalLines: Int,
        binary: Bool = false, absolutePath: String? = nil, byteSize: Int? = nil
    ) {
        self.id = id
        self.path = path
        self.content = content
        self.start = start
        self.end = end
        self.totalLines = totalLines
        self.binary = binary
        self.absolutePath = absolutePath
        self.byteSize = byteSize
    }
}
