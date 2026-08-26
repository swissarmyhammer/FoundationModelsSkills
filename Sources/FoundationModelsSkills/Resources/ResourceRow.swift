/// One resource file row `ListResource` returns (plan.md §7.3).
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
/// skill's directory, up to the 100-row cap (plan.md §7.3).
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
/// line (plan.md §7.3).
public struct ReadResourceResult: Encodable, Sendable, Equatable {
    /// The resource's owning skill id.
    public let id: String

    /// The resource's path, relative to the skill directory.
    public let path: String

    /// The verbatim content of lines `start` through `end`, joined by `\n`
    /// -- never passed through the §5 render pipeline.
    public let content: String

    /// The first line returned (1-based).
    public let start: Int

    /// The last line returned -- fewer than requested when the file ended or
    /// the per-call content byte budget cut the window short; `start - 1`
    /// when no line was returned. Paging continues from `end + 1`.
    public let end: Int

    /// The file's total line count, for paging via `start`/`end`.
    public let totalLines: Int

    /// Creates a `ReadResourceResult` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - id: The resource's owning skill id.
    ///   - path: The resource's path, relative to the skill directory.
    ///   - content: The verbatim content of lines `start` through `end`.
    ///   - start: The first line returned.
    ///   - end: The last line returned.
    ///   - totalLines: The file's total line count.
    public init(id: String, path: String, content: String, start: Int, end: Int, totalLines: Int) {
        self.id = id
        self.path = path
        self.content = content
        self.start = start
        self.end = end
        self.totalLines = totalLines
    }
}
