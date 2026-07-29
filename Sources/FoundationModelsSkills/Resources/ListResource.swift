import Foundation
import FoundationModels
import Operations

/// The outcome of a `list resource` operation: either the resource listing
/// or a corrective message (plan.md §7.3).
///
/// An unknown, stale, or model-hidden `id` is the one condition
/// `ListResource.execute(in:)` fails correctively on.
public typealias ListResourceOutput = CorrectiveOutcome<ListResourceResult>

/// Enumerates every regular file under a skill's directory except
/// `SKILL.md` (plan.md §7.3).
///
/// A passive, ungated read: every regular file, sorted by path, capped at
/// `rowCap` rows with `total` reporting the real count. Hidden files (any
/// path component starting with `.`) and symlinks resolving outside the
/// skill directory are silently skipped, never surfaced as rows or errors --
/// `ReadResource`'s `path` parameter is where an escaping symlink draws a
/// corrective, since only there does a caller name one explicitly.
public struct ListResource: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: the resource listing, or a corrective
    /// message.
    public typealias Output = ListResourceOutput

    /// The skill id whose resources to list.
    public var id: String

    /// Creates a `ListResource` operation by directly assigning its
    /// parameter, bypassing `GeneratedContent` decoding.
    ///
    /// - Parameter id: The skill id whose resources to list.
    public init(id: String) {
        self.id = id
    }

    /// The action this operation performs: `"list"`.
    public static let verb = "list"

    /// The resource this operation acts on: `"resource"`.
    public static let noun = resourceOperationNoun

    /// A human- and model-facing summary of what this operation does.
    public static let operationDescription =
        "List a skill's bundled resource files (scripts, references, assets), excluding SKILL.md."

    /// This operation's parameters, as the resolver and schema fusion need
    /// them: `id` (required).
    public static let parameterMetadata: [ParamMeta] = [
        ParamMeta(name: idKey, type: .string, required: true, description: "The skill id whose resources to list.")
    ]

    /// The `GeneratedContent` property name for `id`.
    ///
    /// The single source of truth shared by `parameterMetadata`, the
    /// decoding `init`, and `generatedContent`, so the two can never drift
    /// out of sync.
    private static let idKey = "id"

    /// Decodes a `ListResource` from a resolved `GeneratedContent` payload.
    ///
    /// - Parameter content: The payload to decode, already resolved to this
    ///   operation's canonical parameter names.
    /// - Throws: Whatever `content.value(_:forProperty:)` throws for a
    ///   missing or mistyped `id`.
    public init(_ content: GeneratedContent) throws {
        id = try content.value(String.self, forProperty: Self.idKey)
    }

    /// This operation's parameters re-encoded as `GeneratedContent`, e.g. for
    /// the CLI driver's round trip back to the model-facing payload shape.
    public var generatedContent: GeneratedContent {
        GeneratedContent(properties: [Self.idKey: id])
    }

    /// The maximum number of rows a successful listing returns.
    private static let rowCap = 100

    /// The skill definition file every listing excludes.
    private static let skillFileName = "SKILL.md"

    /// The file-system properties every directory-entry lookup below needs:
    /// whether an entry is a directory or a regular file, its size, and its
    /// executable bit.
    private static let requiredResourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .fileSizeKey, .isExecutableKey,
    ]

    /// Lists `id`'s resource files, or returns a corrective message.
    ///
    /// - Parameter context: The shared context supplying the model-visible
    ///   registry.
    /// - Returns: `.success(_:)` carrying the listing on success;
    ///   `.corrective(_:)` for an unknown, stale, or model-hidden id.
    /// - Throws: Nothing; the signature carries `throws` to satisfy the
    ///   `OperationDefinition` protocol requirement.
    public func execute(in context: SkillsToolContext) async throws -> ListResourceOutput {
        switch ResourceIDLookup.resolve(id: id, context: context) {
        case .corrective(let message):
            return .corrective(message)
        case .success(let skillDirectory):
            let rows = Self.resourceRows(in: skillDirectory).sorted { $0.path < $1.path }
            return .success(ListResourceResult(id: id, resources: Array(rows.prefix(Self.rowCap)), total: rows.count))
        }
    }

    /// Recursively enumerates every regular file under `skillDirectory`,
    /// except `SKILL.md`.
    ///
    /// - Parameter skillDirectory: The skill's root directory.
    /// - Returns: One row per regular file, unsorted.
    private static func resourceRows(in skillDirectory: URL) -> [ResourceRow] {
        Self.rows(inDirectory: skillDirectory, relativePrefix: "", skillDirectory: skillDirectory)
    }

    /// Enumerates one directory's entries, recursing into subdirectories and
    /// accumulating each regular file as a row.
    ///
    /// Builds every relative path purely from entry names accumulated
    /// through `relativePrefix`, never by diffing absolute URLs -- so a
    /// symlinked subdirectory's own descendants still report paths relative
    /// to `skillDirectory`, regardless of where the symlink's target
    /// actually resolves on disk.
    ///
    /// - Parameters:
    ///   - directory: The directory to enumerate.
    ///   - relativePrefix: `directory`'s own path relative to
    ///     `skillDirectory`, or `""` at the root.
    ///   - skillDirectory: The skill's root directory, for confinement.
    /// - Returns: One row per regular file found, unsorted.
    private static func rows(inDirectory directory: URL, relativePrefix: String, skillDirectory: URL) -> [ResourceRow]
    {
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Self.requiredResourceKeys,
                options: [.skipsHiddenFiles])) ?? []

        return entries.flatMap { entry in
            Self.rows(
                forEntryNamed: entry.lastPathComponent, relativePrefix: relativePrefix, skillDirectory: skillDirectory
            )
        }
    }

    /// Resolves one directory entry (by name, not by its own possibly
    /// symlink-target URL) against `skillDirectory`'s confinement, then
    /// either recurses (a directory) or yields its row (a regular file).
    ///
    /// - Parameters:
    ///   - name: The entry's file name within its parent directory.
    ///   - relativePrefix: The parent directory's own path relative to
    ///     `skillDirectory`, or `""` at the root.
    ///   - skillDirectory: The skill's root directory, for confinement.
    /// - Returns: Zero rows (excluded, escaping, or unreadable), one row (a
    ///   regular file), or every row recursion into a subdirectory finds.
    private static func rows(forEntryNamed name: String, relativePrefix: String, skillDirectory: URL) -> [ResourceRow]
    {
        let relativePath = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"
        guard relativePath != Self.skillFileName,
            let resolved = PathConfinement.resolvedURL(relativePath: relativePath, in: skillDirectory),
            let values = try? resolved.resourceValues(forKeys: Set(Self.requiredResourceKeys))
        else {
            return []
        }

        if values.isDirectory == true {
            return Self.rows(inDirectory: resolved, relativePrefix: relativePath, skillDirectory: skillDirectory)
        }
        guard values.isRegularFile == true else { return [] }

        return [
            ResourceRow(
                path: relativePath, kind: Self.kind(forRelativePath: relativePath),
                bytes: values.fileSize ?? 0, executable: values.isExecutable ?? false)
        ]
    }

    /// Maps a top-level resource folder name to its kind string.
    private static let kindsByTopLevelFolder = [
        "scripts": "script",
        "references": "reference",
        "assets": "asset",
    ]

    /// The default kind for a path with no recognized top-level folder,
    /// including a file directly at the skill directory's root.
    private static let otherKind = "other"

    /// The resource kind implied by `relativePath`'s top-level folder.
    ///
    /// - Parameter relativePath: The file's path, relative to the skill
    ///   directory.
    /// - Returns: `"script"`/`"reference"`/`"asset"` for a path under
    ///   `scripts/`/`references/`/`assets/`; `"other"` for anything else.
    private static func kind(forRelativePath relativePath: String) -> String {
        let topLevelFolder = relativePath.split(separator: "/", maxSplits: 1).first.map(String.init)
        return topLevelFolder.flatMap { Self.kindsByTopLevelFolder[$0] } ?? Self.otherKind
    }
}
