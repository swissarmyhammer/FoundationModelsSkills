import Foundation
import FoundationModels
import Operations

/// The outcome of a `read resource` operation: either the sliced content or
/// a corrective message (plan.md §7.3).
///
/// An unknown/stale/model-hidden `id`, a path confinement violation, or
/// non-UTF-8 content are the conditions `ReadResource.execute(in:)` fails
/// correctively on.
public typealias ReadResourceOutput = CorrectiveOutcome<ReadResourceResult>

/// Returns one skill resource file's content verbatim, sliced by line
/// (plan.md §7.3).
///
/// Never renders: no `$args` substitution, no shell injection, no Stencil --
/// resources are read exactly as they sit on disk. At most `maxLinesPerCall`
/// lines return per call; `totalLines` tells the caller how to page via
/// `start`/`end`.
public struct ReadResource: OperationDefinition {
    /// The shared context this operation dispatches against.
    public typealias Context = SkillsToolContext

    /// This operation's result: the sliced content, or a corrective
    /// message.
    public typealias Output = ReadResourceOutput

    /// The skill id owning the resource.
    public var id: String

    /// The resource's path, relative to the skill directory.
    public var path: String

    /// The first line to return (1-based); `nil` defaults to `1`.
    public var start: Int?

    /// The last line to return; `nil` defaults to `start + maxLinesPerCall -
    /// 1`.
    public var end: Int?

    /// Creates a `ReadResource` operation by directly assigning its
    /// parameters, bypassing `GeneratedContent` decoding.
    ///
    /// - Parameters:
    ///   - id: The skill id owning the resource.
    ///   - path: The resource's path, relative to the skill directory.
    ///   - start: The first line to return; `nil` defaults to `1`.
    ///   - end: The last line to return; `nil` defaults to `start + 499`.
    public init(id: String, path: String, start: Int? = nil, end: Int? = nil) {
        self.id = id
        self.path = path
        self.start = start
        self.end = end
    }

    /// The action this operation performs: `"read"`.
    public static let verb = "read"

    /// The resource this operation acts on: `"resource"`.
    public static let noun = resourceOperationNoun

    /// A human- and model-facing summary of what this operation does.
    public static let operationDescription =
        "Return a skill resource file's content verbatim, sliced by line."

    /// This operation's parameters, as the resolver and schema fusion need
    /// them: `id`/`path` (required), `start`/`end` (optional).
    public static let parameterMetadata: [ParamMeta] = [
        ParamMeta(name: idKey, type: .string, required: true, description: "The skill id owning the resource."),
        ParamMeta(
            name: pathKey, type: .string, required: true,
            description: "The resource's path, relative to the skill directory."),
        ParamMeta(
            name: startKey, type: .integer, required: false,
            description: "The first line to return (1-based). Defaults to 1."),
        ParamMeta(
            name: endKey, type: .integer, required: false,
            description: "The last line to return. Defaults to start + 499, capped at \(Self.maxLinesPerCall) lines per call."
        ),
    ]

    /// The `GeneratedContent` property name for `id`.
    private static let idKey = "id"

    /// The `GeneratedContent` property name for `path`.
    private static let pathKey = "path"

    /// The `GeneratedContent` property name for `start`.
    private static let startKey = "start"

    /// The `GeneratedContent` property name for `end`.
    private static let endKey = "end"

    /// Decodes a `ReadResource` from a resolved `GeneratedContent` payload.
    ///
    /// - Parameter content: The payload to decode, already resolved to this
    ///   operation's canonical parameter names.
    /// - Throws: Whatever `content.value(_:forProperty:)` throws for a
    ///   missing or mistyped `id`/`path`.
    public init(_ content: GeneratedContent) throws {
        id = try content.value(String.self, forProperty: Self.idKey)
        path = try content.value(String.self, forProperty: Self.pathKey)
        start = try content.value(Int?.self, forProperty: Self.startKey)
        end = try content.value(Int?.self, forProperty: Self.endKey)
    }

    /// This operation's parameters re-encoded as `GeneratedContent`, e.g. for
    /// the CLI driver's round trip back to the model-facing payload shape.
    public var generatedContent: GeneratedContent {
        var properties: [(String, any ConvertibleToGeneratedContent)] = [(Self.idKey, id), (Self.pathKey, path)]
        if let start { properties.append((Self.startKey, start)) }
        if let end { properties.append((Self.endKey, end)) }
        return GeneratedContent(properties: properties, uniquingKeysWith: { _, new in new })
    }

    /// The maximum number of lines a successful read returns per call.
    private static let maxLinesPerCall = 500

    /// Reads `path` under `id`'s directory, or returns a corrective message.
    ///
    /// - Parameter context: The shared context supplying the model-visible
    ///   registry.
    /// - Returns: `.success(_:)` carrying the sliced content on success;
    ///   `.corrective(_:)` for an unusable id, a confinement violation, an
    ///   unreadable file, or non-UTF-8 content.
    /// - Throws: Nothing; the signature carries `throws` to satisfy the
    ///   `OperationDefinition` protocol requirement.
    public func execute(in context: SkillsToolContext) async throws -> ReadResourceOutput {
        let skillDirectory: URL
        switch ResourceIDLookup.resolve(id: id, context: context) {
        case .corrective(let message):
            return .corrective(message)
        case .success(let resolvedDirectory):
            skillDirectory = resolvedDirectory
        }

        guard let resolved = PathConfinement.resolvedURL(relativePath: path, in: skillDirectory) else {
            return .corrective(PathConfinement.deniedMessage(path: path))
        }
        guard let data = try? Data(contentsOf: resolved) else {
            return .corrective(Self.unreadableMessage(path: path))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .corrective(Self.nonUTF8Message(path: path, byteSize: data.count))
        }

        return .success(Self.slice(text: text, id: id, path: path, start: start, end: end))
    }

    /// Slices `text` to the requested (or defaulted) `start`/`end` line
    /// range, capped at `maxLinesPerCall` lines.
    ///
    /// - Parameters:
    ///   - text: The file's full, unrendered content.
    ///   - id: The resource's owning skill id, carried into the result.
    ///   - path: The resource's path, carried into the result.
    ///   - start: The requested first line, or `nil` for `1`.
    ///   - end: The requested last line, or `nil` for `start + 499`.
    /// - Returns: The sliced result.
    private static func slice(text: String, id: String, path: String, start: Int?, end: Int?) -> ReadResourceResult {
        let lines = text.splitIntoLines
        let resolvedStart = max(start ?? 1, 1)
        let maxAllowedEnd = resolvedStart + Self.maxLinesPerCall - 1
        let requestedEnd = end ?? maxAllowedEnd
        let resolvedEnd = min(requestedEnd, maxAllowedEnd, lines.count)

        guard resolvedStart <= resolvedEnd else {
            return ReadResourceResult(
                id: id, path: path, content: "", start: resolvedStart, end: resolvedStart - 1,
                totalLines: lines.count)
        }
        let content = lines[(resolvedStart - 1)..<resolvedEnd].joined(separator: "\n")
        return ReadResourceResult(
            id: id, path: path, content: content, start: resolvedStart, end: resolvedEnd, totalLines: lines.count)
    }

    /// The corrective message for a confined `path` that could not be read.
    ///
    /// - Parameter path: The path that could not be read.
    /// - Returns: The corrective message.
    private static func unreadableMessage(path: String) -> String {
        "The path `\(path)` could not be read."
    }

    /// The corrective message for a confined, readable `path` whose content
    /// is not valid UTF-8.
    ///
    /// - Parameters:
    ///   - path: The non-UTF-8 resource's path.
    ///   - byteSize: The resource's size in bytes.
    /// - Returns: The corrective message.
    private static func nonUTF8Message(path: String, byteSize: Int) -> String {
        "The resource `\(path)` is not valid UTF-8 text (\(byteSize) bytes) and cannot be returned as transcript content."
    }
}
