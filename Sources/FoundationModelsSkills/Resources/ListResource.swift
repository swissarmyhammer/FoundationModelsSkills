import Foundation
import FoundationModels
import Operations

/// The outcome of a `list resource` operation: either the resource listing
/// or a corrective message.
///
/// An unknown, stale, or model-hidden `id` is the one condition
/// `ListResource.execute(in:)` fails correctively on.
public typealias ListResourceOutput = CorrectiveOutcome<ListResourceResult>

/// Lists every file of the combined view of a skill except `SKILL.md`.
///
/// A passive, ungated read: every file of the layer directories of the skill,
/// sorted by path, capped at `rowCap` rows with `total` reporting the real
/// count. Hidden files (any path component starting with `.`) are silently
/// skipped, and the combined view itself leaves out a file that resolves
/// outside its own layer directory -- `ReadResource`'s `path` parameter is
/// where an escaping symlink draws a corrective, since only there does a
/// caller name one explicitly.
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

    /// The byte count a row carries for a file whose size the combined view
    /// could not read.
    private static let unknownByteCount = 0

    /// Lists `id`'s resource files, or returns a corrective message.
    ///
    /// The unit of override is the file, thus the rows come from the combined
    /// view of the layer directories of the skill: a file that
    /// only a lower layer holds is a row of its own, and a path that two
    /// layers hold is one row that carries the copy of the higher layer.
    ///
    /// - Parameter context: The shared context supplying the model-visible
    ///   registry.
    /// - Returns: `.success(_:)` carrying the listing on success;
    ///   `.corrective(_:)` for an unknown, stale, or model-hidden id.
    /// - Throws: Nothing; the signature carries `throws` to satisfy the
    ///   `OperationDefinition` protocol requirement.
    public func execute(in context: SkillsToolContext) async throws -> ListResourceOutput {
        await ResourceIDLookup.withResolvedOverlay(id: id, context: context) { overlay in
            let rows = Self.resourceRows(in: overlay).sorted { $0.path < $1.path }
            return .success(ListResourceResult(id: id, resources: Array(rows.prefix(Self.rowCap)), total: rows.count))
        }
    }

    /// One row for each file of the combined view that a listing shows.
    ///
    /// The overlay gives each column that reads the disk -- the size of the
    /// file and its execute bit -- thus this operation opens no file, and each
    /// column speaks of the copy of the highest layer directory that holds the
    /// path.
    ///
    /// - Parameter overlay: The combined view of the layer directories of the
    ///   skill.
    /// - Returns: One row per listed file, unsorted.
    private static func resourceRows(in overlay: SkillOverlay) -> [ResourceRow] {
        overlay.entries().keys
            .filter { Self.isListed($0) }
            .map { path in
                ResourceRow(
                    path: path, kind: Self.kind(forRelativePath: path),
                    bytes: overlay.size(of: path) ?? Self.unknownByteCount,
                    executable: overlay.isExecutable(path))
            }
    }

    /// Whether a listing shows the file at `relativePath`.
    ///
    /// The `SKILL.md` of a skill is the definition of the skill and no
    /// resource of it, and a hidden file belongs to the tools of the author.
    ///
    /// - Parameter relativePath: The path of one file of the combined view.
    /// - Returns: Whether the listing shows the file.
    private static func isListed(_ relativePath: String) -> Bool {
        relativePath != Self.skillFileName && !Self.isHidden(relativePath)
    }

    /// Whether a component of `relativePath` starts with a full stop, which
    /// makes the file itself, or a directory above it, hidden.
    ///
    /// - Parameter relativePath: The path of one file of the combined view.
    /// - Returns: Whether the path is hidden.
    private static func isHidden(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains { $0.hasPrefix(".") }
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
