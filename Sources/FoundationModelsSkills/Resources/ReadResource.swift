import Foundation
import FoundationModels
import Operations

/// The outcome of a `read resource` operation: either the sliced content or
/// a corrective message (plan.md §7.3).
///
/// An unknown/stale/model-hidden `id`, a path confinement violation, an
/// unreadable file, non-UTF-8 content, or a single line larger than the
/// per-call content byte budget are the conditions
/// `ReadResource.execute(in:)` fails correctively on.
public typealias ReadResourceOutput = CorrectiveOutcome<ReadResourceResult>

/// Returns one skill resource file's content verbatim, sliced by line
/// (plan.md §7.3).
///
/// Never renders: no `$args` substitution, no shell injection, no Stencil --
/// resources are read exactly as they sit on disk.
///
/// **Paging semantics.** The file is streamed in fixed chunks, never loaded
/// whole, so a UTF-8 text resource of any size pages. Each call returns at
/// most `maxLinesPerCall` lines and at most `maxContentBytesPerCall` bytes of
/// content: when the next line of the requested window would push the
/// content past the byte budget, the window stops there and `end` reports
/// the last line actually returned, so the caller continues from `end + 1`.
/// `totalLines` is always the exact line count of the whole file -- every
/// call scans the file to its end (linear in file size, but bounded in
/// memory by one chunk plus the returned window). A line is a run of bytes
/// ended by `\n` (0x0A); a trailing newline does not add an empty final line,
/// matching `StringProtocol.splitIntoLines`.
///
/// Two conditions refuse the read with a corrective instead of paging: a
/// single line that alone exceeds the content byte budget (named by line
/// number), and content that is not valid UTF-8 (reported with the file's
/// stat'd byte size; the scan stops at the first invalid byte, so a binary
/// asset is never materialized).
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
    ///   - end: The last line to return; `nil` defaults to `start +
    ///     maxLinesPerCall - 1`.
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
            description:
                "The last line to return. Defaults to start + \(Self.maxLinesPerCall - 1), capped at "
                + "\(Self.maxLinesPerCall) lines and \(Self.maxContentBytesPerCall) content bytes per call; "
                + "the result's end reports the last line returned."
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
        GeneratedContentBuilder.make(
            required: [(Self.idKey, id), (Self.pathKey, path)],
            optional: [(Self.startKey, start), (Self.endKey, end)])
    }

    /// The maximum number of lines a successful read returns per call.
    private static let maxLinesPerCall = 500

    /// The maximum number of content bytes a successful read returns per
    /// call -- the bound on the memory one call retains for its window.
    /// A window whose lines would exceed it is cut short at the last line
    /// that fits (`end` reports it); a single line that alone exceeds it is
    /// refused with a corrective naming the line.
    private static let maxContentBytesPerCall = 1_000_000

    /// The number of bytes one streaming read pulls from the file at a
    /// time -- the other half of the per-call memory bound.
    private static let readChunkByteSize = 65_536

    /// Reads `path` under `id`'s directory, or returns a corrective message.
    ///
    /// - Parameter context: The shared context supplying the model-visible
    ///   registry.
    /// - Returns: `.success(_:)` carrying the sliced content on success;
    ///   `.corrective(_:)` for an unusable id, a confinement violation, an
    ///   unreadable file, non-UTF-8 content, or a single line over the
    ///   content byte budget.
    /// - Throws: Nothing; the signature carries `throws` to satisfy the
    ///   `OperationDefinition` protocol requirement.
    public func execute(in context: SkillsToolContext) async throws -> ReadResourceOutput {
        await ResourceIDLookup.withResolvedDirectory(id: id, context: context) { skillDirectory in
            guard let resolved = PathConfinement.resolvedURL(relativePath: path, in: skillDirectory) else {
                return .corrective(PathConfinement.deniedMessage(path: path))
            }
            guard let statedSize = Self.fileSize(at: resolved) else {
                return .corrective(Self.unreadableMessage(path: path))
            }
            let window = LineWindow(start: start, end: end, maxLines: Self.maxLinesPerCall)
            var scanner = LineWindowScanner(
                window: window, contentByteBudget: Self.maxContentBytesPerCall,
                chunkByteSize: Self.readChunkByteSize)
            switch scanner.scan(fileAt: resolved) {
            case .unreadable:
                return .corrective(Self.unreadableMessage(path: path))
            case .nonUTF8:
                return .corrective(Self.nonUTF8Message(path: path, byteSize: statedSize))
            case .oversizedLine(let lineNumber):
                return .corrective(Self.oversizedLineMessage(path: path, lineNumber: lineNumber))
            case .window(let lines, let totalLines):
                return .success(result(window: window, lines: lines, totalLines: totalLines))
            }
        }
    }

    /// `url`'s file size, read from filesystem metadata alone -- never opens
    /// or reads the file's content.
    ///
    /// - Parameter url: The file to stat.
    /// - Returns: The file's size in bytes, or `nil` if it could not be
    ///   stat'd.
    private static func fileSize(at url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    /// Assembles the successful result for the lines the scan retained.
    ///
    /// - Parameters:
    ///   - window: The requested window; its first line is the result's
    ///     `start`.
    ///   - lines: The retained lines, in order -- possibly fewer than the
    ///     window asked for when the file ended or the byte budget cut it.
    ///   - totalLines: The file's exact line count.
    /// - Returns: The result, whose `end` is the last line returned, or
    ///   `start - 1` when no line was.
    private func result(window: LineWindow, lines: [String], totalLines: Int) -> ReadResourceResult {
        ReadResourceResult(
            id: id, path: path, content: lines.joined(separator: "\n"), start: window.first,
            end: window.first + lines.count - 1, totalLines: totalLines)
    }

    /// The corrective message for a confined `path` that could not be read.
    ///
    /// - Parameter path: The path that could not be read.
    /// - Returns: The corrective message.
    private static func unreadableMessage(path: String) -> String {
        "The path `\(path)` could not be read."
    }

    /// The corrective message for a confined, readable `path` one of whose
    /// lines alone exceeds `maxContentBytesPerCall` -- no window can return
    /// that line, so the read is refused naming it.
    ///
    /// - Parameters:
    ///   - path: The resource's path.
    ///   - lineNumber: The 1-based number of the oversized line.
    /// - Returns: The corrective message.
    private static func oversizedLineMessage(path: String, lineNumber: Int) -> String {
        "Line \(lineNumber) of `\(path)` is longer than \(Self.maxContentBytesPerCall) bytes, exceeding the "
            + "\(Self.maxContentBytesPerCall)-byte content budget this operation returns per call."
    }

    /// The corrective message for a confined, readable `path` whose content
    /// is not valid UTF-8.
    ///
    /// - Parameters:
    ///   - path: The non-UTF-8 resource's path.
    ///   - byteSize: The resource's stat'd size in bytes.
    /// - Returns: The corrective message.
    private static func nonUTF8Message(path: String, byteSize: Int) -> String {
        "The resource `\(path)` is not valid UTF-8 text (\(byteSize) bytes) and cannot be returned as transcript content."
    }
}

/// The 1-based, inclusive line range one `read resource` call asks for,
/// after the `start`/`end` defaults and the per-call line cap are applied.
private struct LineWindow {
    /// The first line of the window; never below 1.
    let first: Int

    /// The last line the window may hold; below `first` for an empty window.
    let last: Int

    /// Resolves the requested range.
    ///
    /// - Parameters:
    ///   - start: The requested first line, or `nil` for `1`.
    ///   - end: The requested last line, or `nil` for `start + maxLines - 1`.
    ///   - maxLines: The per-call line cap the window is clamped to.
    init(start: Int?, end: Int?, maxLines: Int) {
        first = max(start ?? 1, 1)
        let maxAllowedLast = first + maxLines - 1
        last = min(end ?? maxAllowedLast, maxAllowedLast)
    }

    /// Whether `lineNumber` falls inside the window.
    ///
    /// - Parameter lineNumber: A 1-based line number.
    /// - Returns: Whether the window holds that line.
    func contains(_ lineNumber: Int) -> Bool {
        lineNumber >= first && lineNumber <= last
    }
}

/// Streams a resource file in fixed chunks, validating UTF-8 as it goes,
/// counting every line, and retaining only the lines inside one
/// `LineWindow` -- up to a content byte budget.
///
/// Memory is bounded by one chunk, the incomplete-scalar carry (at most
/// three bytes), the line being read (never past the budget), and the
/// retained window (never past the budget).
private struct LineWindowScanner {
    /// The outcome of one scan.
    enum Outcome {
        /// The window's lines, in order, and the file's exact line count.
        case window(lines: [String], totalLines: Int)

        /// The file holds bytes that are not valid UTF-8.
        case nonUTF8

        /// The line with this 1-based number alone exceeds the content byte
        /// budget.
        case oversizedLine(number: Int)

        /// The file could not be opened or read.
        case unreadable
    }

    /// Why a scan stopped before the end of the file.
    private enum Interruption: Error {
        /// A byte sequence that is not valid UTF-8 was met.
        case nonUTF8

        /// The first window line alone exceeded the content byte budget.
        case oversizedLine(number: Int)
    }

    /// The byte that ends a line.
    private static let newline = UInt8(ascii: "\n")

    /// The longest UTF-8 encoding of one scalar, in bytes.
    private static let maxScalarByteLength = 4

    /// Each multi-byte UTF-8 lead-byte range with the scalar length it
    /// opens. A byte outside every range that is not a continuation byte is
    /// a one-byte scalar.
    private static let multiByteLeadRanges: [(leadBytes: ClosedRange<UInt8>, scalarLength: Int)] = [
        (0xC0...0xDF, 2),
        (0xE0...0xEF, 3),
        (0xF0...0xF7, 4),
    ]

    /// The window whose lines are retained.
    private let window: LineWindow

    /// The maximum byte size of the retained window, newlines included.
    private let contentByteBudget: Int

    /// The number of bytes each read pulls from the file.
    private let chunkByteSize: Int

    /// The 1-based number of the line being read.
    private var currentLineNumber = 1

    /// The byte count of the line being read, retained or not.
    private var currentLineByteCount = 0

    /// The bytes of the line being read, kept only while it is retained.
    private var currentLineBytes: [UInt8] = []

    /// The trailing bytes of the last chunk that open a multi-byte scalar
    /// the chunk did not complete; prepended to the next chunk.
    private var incompleteScalar: [UInt8] = []

    /// The window lines decoded so far.
    private var retainedLines: [String] = []

    /// The byte size of `retainedLines` joined by newlines.
    private var retainedByteCount = 0

    /// Whether the budget cut the window, so no further line is retained.
    private var budgetExhausted = false

    /// Creates a scanner for one window.
    ///
    /// - Parameters:
    ///   - window: The window whose lines are retained.
    ///   - contentByteBudget: The maximum byte size of the retained window.
    ///   - chunkByteSize: The number of bytes each read pulls from the file.
    init(window: LineWindow, contentByteBudget: Int, chunkByteSize: Int) {
        self.window = window
        self.contentByteBudget = contentByteBudget
        self.chunkByteSize = chunkByteSize
    }

    /// Scans the file at `url` to its end, or to the first byte that stops
    /// the scan.
    ///
    /// - Parameter url: The file to scan.
    /// - Returns: The scan's outcome.
    mutating func scan(fileAt url: URL) -> Outcome {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unreadable }
        defer { try? handle.close() }
        do {
            while let chunk = try handle.read(upToCount: chunkByteSize), !chunk.isEmpty {
                try consume(chunk: chunk)
            }
            try finish()
        } catch Interruption.nonUTF8 {
            return .nonUTF8
        } catch Interruption.oversizedLine(let number) {
            return .oversizedLine(number: number)
        } catch {
            return .unreadable
        }
        return .window(lines: retainedLines, totalLines: currentLineNumber - 1)
    }

    /// Validates one chunk (with the previous carry in front) as UTF-8 and
    /// feeds its complete scalars to the line splitter.
    ///
    /// - Parameter chunk: The bytes just read.
    /// - Throws: `Interruption.nonUTF8` for invalid bytes;
    ///   `Interruption.oversizedLine` from the line splitter.
    private mutating func consume(chunk: Data) throws {
        var bytes = incompleteScalar
        bytes.append(contentsOf: chunk)
        let completeCount = bytes.count - Self.incompleteTailLength(of: bytes)
        let complete = bytes[..<completeCount]
        guard String(validating: complete, as: UTF8.self) != nil else { throw Interruption.nonUTF8 }
        incompleteScalar = Array(bytes[completeCount...])
        try consumeLines(in: complete)
    }

    /// Ends the scan: a carry left over is a truncated scalar, and a final
    /// line without a newline still counts.
    ///
    /// - Throws: `Interruption.nonUTF8` for a truncated final scalar.
    private mutating func finish() throws {
        guard incompleteScalar.isEmpty else { throw Interruption.nonUTF8 }
        if currentLineByteCount > 0 {
            commitLine()
        }
    }

    /// Splits validated bytes into line segments and commits each line a
    /// newline ends.
    ///
    /// - Parameter bytes: Validated UTF-8 bytes.
    /// - Throws: `Interruption.oversizedLine` when the first window line
    ///   alone exceeds the budget.
    private mutating func consumeLines(in bytes: ArraySlice<UInt8>) throws {
        var segmentStart = bytes.startIndex
        while let newlineIndex = bytes[segmentStart...].firstIndex(of: Self.newline) {
            try append(segment: bytes[segmentStart..<newlineIndex])
            commitLine()
            segmentStart = newlineIndex + 1
        }
        try append(segment: bytes[segmentStart...])
    }

    /// Whether the line being read belongs to the retained window.
    private var isRetainingCurrentLine: Bool {
        window.contains(currentLineNumber) && !budgetExhausted
    }

    /// The byte size the retained window would have with the current line
    /// added: the retained bytes, a joining newline when one is needed, and
    /// the current line's bytes.
    private var projectedWindowByteCount: Int {
        retainedByteCount + (retainedLines.isEmpty ? 0 : 1) + currentLineBytes.count
    }

    /// Adds part of the current line, retaining its bytes only while the
    /// line is in the window and within the budget.
    ///
    /// - Parameter segment: The bytes to add; holds no newline.
    /// - Throws: `Interruption.oversizedLine` when the first window line
    ///   alone exceeds the budget.
    private mutating func append(segment: ArraySlice<UInt8>) throws {
        currentLineByteCount += segment.count
        guard isRetainingCurrentLine else { return }
        currentLineBytes.append(contentsOf: segment)
        guard projectedWindowByteCount > contentByteBudget else { return }
        guard !retainedLines.isEmpty else { throw Interruption.oversizedLine(number: currentLineNumber) }
        budgetExhausted = true
        currentLineBytes = []
    }

    /// Ends the current line: retains it when it belongs to the window,
    /// then moves to the next line number.
    private mutating func commitLine() {
        if isRetainingCurrentLine {
            retainedByteCount = projectedWindowByteCount
            retainedLines.append(String(decoding: currentLineBytes, as: UTF8.self))
        }
        currentLineBytes.removeAll(keepingCapacity: true)
        currentLineByteCount = 0
        currentLineNumber += 1
    }

    /// The count of bytes at the end of `bytes` that open a multi-byte UTF-8
    /// scalar the buffer does not complete -- `0` when the buffer ends on a
    /// scalar boundary. Only the last `maxScalarByteLength - 1` bytes can be
    /// such a tail.
    ///
    /// - Parameter bytes: The buffer to inspect.
    /// - Returns: The tail length to carry into the next chunk.
    private static func incompleteTailLength(of bytes: [UInt8]) -> Int {
        let searchStart = max(bytes.count - (Self.maxScalarByteLength - 1), 0)
        var index = bytes.count - 1
        while index >= searchStart {
            let byte = bytes[index]
            if !UTF8.isContinuation(byte) {
                let available = bytes.count - index
                return available < Self.scalarLength(leadByte: byte) ? available : 0
            }
            index -= 1
        }
        return 0
    }

    /// The encoded length of the scalar `leadByte` opens.
    ///
    /// - Parameter leadByte: A byte that is not a continuation byte.
    /// - Returns: The scalar's byte length; `1` for a one-byte scalar.
    private static func scalarLength(leadByte: UInt8) -> Int {
        Self.multiByteLeadRanges.first { $0.leadBytes.contains(leadByte) }?.scalarLength ?? 1
    }
}
